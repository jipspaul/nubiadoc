//! Tests d'intégration : `PATCH /v1/account/coverage` journalise dans
//! `audit_log` (#4095).

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

const JWT_SECRET: &str = "test-jwt-secret-coverage-audit-log";

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

async fn insert_account(db: &PgPool, tag: &str) -> (Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("cov-audit-{tag}+{user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Dupont')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
    (user_id, account_id)
}

async fn patch_coverage(
    server: axum::Router,
    user_id: Uuid,
    account_id: Uuid,
    regime: &str,
) -> StatusCode {
    let response = server
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/account/coverage")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"regime_obligatoire": regime}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    response.status()
}

/// Spec de l'issue : un PATCH coverage crée une ligne audit_log
/// correspondante (action='update_coverage'), avec l'ancien/nouveau régime
/// en metadata.
#[tokio::test]
async fn patch_coverage_creates_audit_log_entry() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id) = insert_account(&db, "first").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let status = patch_coverage(app(state), user_id, account_id, "regime_general").await;
    assert_eq!(status, StatusCode::OK);

    let row = sqlx::query_as::<_, (String, Uuid, serde_json::Value)>(
        "SELECT action, entity_id, metadata FROM audit_log \
         WHERE action = 'update_coverage' AND entity_id = $1 \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(account_id)
    .fetch_optional(&db)
    .await
    .unwrap();

    let (action, entity_id, metadata) =
        row.expect("audit_log doit contenir une ligne update_coverage");
    assert_eq!(action, "update_coverage");
    assert_eq!(entity_id, account_id);
    assert!(
        metadata["old_regime_obligatoire"].is_null(),
        "première déclaration : pas de régime antérieur — metadata: {metadata}"
    );
    assert_eq!(
        metadata["new_regime_obligatoire"], "regime_general",
        "metadata: {metadata}"
    );

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

/// Deuxième PATCH changeant de régime → l'ancien et le nouveau régime sont
/// tous deux journalisés.
#[tokio::test]
async fn patch_coverage_regime_change_logs_old_and_new() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id) = insert_account(&db, "change").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let status1 = patch_coverage(app(state.clone()), user_id, account_id, "regime_general").await;
    assert_eq!(status1, StatusCode::OK);

    let status2 = patch_coverage(app(state), user_id, account_id, "css").await;
    assert_eq!(status2, StatusCode::OK);

    let row = sqlx::query_as::<_, (serde_json::Value,)>(
        "SELECT metadata FROM audit_log \
         WHERE action = 'update_coverage' AND entity_id = $1 \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(account_id)
    .fetch_optional(&db)
    .await
    .unwrap();

    let (metadata,) = row.expect("audit_log doit contenir la 2e entrée update_coverage");
    assert_eq!(
        metadata["old_regime_obligatoire"], "regime_general",
        "metadata: {metadata}"
    );
    assert_eq!(
        metadata["new_regime_obligatoire"], "css",
        "metadata: {metadata}"
    );

    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit_log WHERE action = 'update_coverage' AND entity_id = $1",
    )
    .bind(account_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(count, 2, "une entrée audit_log par PATCH");

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}
