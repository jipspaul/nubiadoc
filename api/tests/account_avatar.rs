//! Tests d'intégration : PUT + GET /v1/account/avatar (photo de profil patient)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use base64::Engine as _;
use jsonwebtoken::{encode, EncodingKey, Header};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-account-avatar";

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

async fn owner_pool() -> PgPool {
    let url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_owner@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

fn make_patient_token(sub: Uuid, account_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        account_id: Uuid,
        exp: u64,
    }
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "patient".into(),
            account_id,
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn insert_account(db: &PgPool) -> (Uuid, Uuid) {
    let account_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(account_user_id)
    .bind(format!("avatar+{}@nubia.test", account_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Ava', 'Tar')",
    )
    .bind(account_id)
    .bind(account_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    (account_user_id, account_id)
}

async fn cleanup_account(db: &PgPool, account_user_id: Uuid, account_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(account_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

fn state_sync(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

// ── Test 1 : PUT puis GET → mêmes octets, bon content-type ───────────────────

#[tokio::test]
async fn put_then_get_roundtrip() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (user_id, account_id) = insert_account(&owner).await;
    let token = make_patient_token(user_id, account_id);
    let pixels: Vec<u8> = vec![0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4];
    let b64 = base64::engine::general_purpose::STANDARD.encode(&pixels);

    let put = app(state_sync(app_pool().await))
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/avatar")
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"mime":"image/png","data_base64":"{b64}"}}"#
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(put.status(), StatusCode::NO_CONTENT);

    let get = app(state_sync(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/avatar")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(get.status(), StatusCode::OK);
    assert_eq!(get.headers().get("content-type").unwrap(), "image/png");
    let body = axum::body::to_bytes(get.into_body(), usize::MAX)
        .await
        .unwrap();
    assert_eq!(body.as_ref(), pixels.as_slice());

    cleanup_account(&owner, user_id, account_id).await;
}

// ── Test 2 : MIME interdit / base64 invalide / trop gros → 422 ───────────────

#[tokio::test]
async fn invalid_payloads_return_422() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (user_id, account_id) = insert_account(&owner).await;
    let token = make_patient_token(user_id, account_id);

    let too_big = base64::engine::general_purpose::STANDARD.encode(vec![0u8; 301 * 1024]);
    for body in [
        r#"{"mime":"image/gif","data_base64":"aGVsbG8="}"#.to_string(),
        r#"{"mime":"image/png","data_base64":"%%%pas-du-base64%%%"}"#.to_string(),
        format!(r#"{{"mime":"image/png","data_base64":"{too_big}"}}"#),
    ] {
        let put = app(state_sync(app_pool().await))
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri("/v1/account/avatar")
                    .header("authorization", format!("Bearer {token}"))
                    .header("content-type", "application/json")
                    .body(Body::from(body))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(put.status(), StatusCode::UNPROCESSABLE_ENTITY);
    }

    cleanup_account(&owner, user_id, account_id).await;
}

// ── Test 3 : sans avatar → 404 ; autre compte → ne voit pas le mien ──────────

#[tokio::test]
async fn no_avatar_404_and_isolation() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (user_id, account_id) = insert_account(&owner).await;
    let token = make_patient_token(user_id, account_id);

    // Pas encore d'avatar → 404.
    let get = app(state_sync(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/avatar")
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(get.status(), StatusCode::NOT_FOUND);

    // Un AUTRE compte (inexistant) → 404, jamais l'avatar d'autrui.
    let other = make_patient_token(Uuid::new_v4(), Uuid::new_v4());
    let get_other = app(state_sync(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/avatar")
                .header("authorization", format!("Bearer {other}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(get_other.status(), StatusCode::NOT_FOUND);

    cleanup_account(&owner, user_id, account_id).await;
}
