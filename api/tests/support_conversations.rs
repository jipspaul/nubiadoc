//! Tests d'intégration : POST /v1/support/conversations (#4169)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-support-conversations";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": user_id,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": role,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn insert_cabinet_with_admin(db: &PgPool, tag: &str) -> (Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let admin_user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(admin_user_id)
    .bind(format!(
        "support-{}-admin+{}@nubia.test",
        tag, admin_user_id
    ))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, $2)")
        .bind(cabinet_id)
        .bind(format!("Cabinet Support {} {}", tag, cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    (cabinet_id, admin_user_id)
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, admin_user_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM conversation WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(admin_user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test : sans JWT → 401 ────────────────────────────────────────────────────

#[tokio::test]
async fn open_support_conversation_no_jwt_returns_401() {
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
                .method("POST")
                .uri("/v1/support/conversations")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test : rôle non-admin (practitioner) → 403 ───────────────────────────────

#[tokio::test]
async fn open_support_conversation_practitioner_returns_403() {
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
                .method("POST")
                .uri("/v1/support/conversations")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "practitioner")
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test : admin → 201, conversation créée, idempotent, isolée par RLS ─────

#[tokio::test]
async fn open_support_conversation_admin_creates_and_is_idempotent_and_isolated() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_a, admin_a) = insert_cabinet_with_admin(&db, "a").await;
    let (cabinet_b, admin_b) = insert_cabinet_with_admin(&db, "b").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // 1er appel : crée la conversation.
    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/support/conversations")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(admin_a, cabinet_a, "admin")),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let conversation_id: Uuid = v["conversation_id"].as_str().unwrap().parse().unwrap();

    // Vérifie l'état en base : scope='platform_support', patient_id NULL.
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_a.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT scope, patient_id, cabinet_id FROM conversation WHERE id = $1")
        .bind(conversation_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    let scope: String = row.try_get("scope").unwrap();
    let patient_id: Option<Uuid> = row.try_get("patient_id").unwrap();
    let row_cabinet_id: Uuid = row.try_get("cabinet_id").unwrap();
    assert_eq!(scope, "platform_support");
    assert!(patient_id.is_none());
    assert_eq!(row_cabinet_id, cabinet_a);

    // 2e appel (idempotence) : même conversation_id, pas de doublon.
    let response2 = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/support/conversations")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(admin_a, cabinet_a, "admin")),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response2.status(), StatusCode::CREATED);
    let bytes2 = axum::body::to_bytes(response2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&bytes2).unwrap();
    assert_eq!(
        v2["conversation_id"], v["conversation_id"],
        "un 2e appel doit renvoyer la même conversation (idempotent)"
    );

    // RLS : le cabinet B ne peut pas lire cette conversation (endpoint
    // existant GET /v1/cabinet/conversations/:id/messages, filtre tenant).
    let response3 = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/conversations/{}/messages",
                    conversation_id
                ))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(admin_b, cabinet_b, "admin")),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        response3.status(),
        StatusCode::NOT_FOUND,
        "le cabinet B ne doit pas pouvoir lire la conversation de support du cabinet A (RLS)"
    );

    cleanup(&db, cabinet_a, admin_a).await;
    cleanup(&db, cabinet_b, admin_b).await;
}
