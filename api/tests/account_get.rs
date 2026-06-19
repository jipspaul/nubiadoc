//! Tests d'intégration : GET /v1/account

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-account-get";

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

fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── Test 1 : JWT patient valide → 200 + champs présents ──────────────────────

#[tokio::test]
async fn account_get_returns_200_with_fields() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("account-get+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Dupont')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["id"], account_id.to_string());
    assert_eq!(v["first_name"], "Alice");
    assert_eq!(v["last_name"], "Dupont");
    assert!(v["email"].is_string(), "email doit être présent");
    assert!(v["created_at"].is_string(), "created_at doit être présent");
    // nss ne doit jamais apparaître
    assert!(v["nss"].is_null());
    assert!(v["nss_ciphertext"].is_null());

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : token pro → 403 ─────────────────────────────────────────────────

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id,
                "role": "admin", "account_id": Uuid::nil(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

#[tokio::test]
async fn account_get_pro_token_returns_403() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(Uuid::new_v4(), Uuid::new_v4())),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 3 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn account_get_no_jwt_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
