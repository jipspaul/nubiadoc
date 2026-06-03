//! Tests d'intégration : POST /v1/auth/mfa/verify
//!
//! Requiert un Postgres accessible via APP_DATABASE_URL / DATABASE_URL
//! (sidecar CI ou env local).

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::time::{SystemTime, UNIX_EPOCH};
use totp_rs::{Algorithm, Secret, TOTP};
use tower::ServiceExt;
use uuid::Uuid;

const JWT_SECRET: &str = "test-jwt-secret-for-mfa-verify";

fn make_pro_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let claims = json!({"sub": user_id, "kind": "pro", "exp": exp});
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
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

async fn insert_test_user(pool: &PgPool) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query!(
        "INSERT INTO app_user (id, email, password_hash) VALUES ($1, $2, 'hash')",
        id,
        format!("mfa-test+{}@nubia.test", id),
    )
    .execute(pool)
    .await
    .unwrap();
    id
}

fn test_totp() -> (String, TOTP) {
    let secret = Secret::generate_secret();
    let secret_b32 = secret.to_encoded().to_string();
    let totp = TOTP::new(Algorithm::SHA1, 6, 1, 30, secret.to_bytes().unwrap()).unwrap();
    (secret_b32, totp)
}

// ── Test 1 : code valide → 200 + mfa_enabled = true en DB ─────────────────

#[tokio::test]
async fn mfa_verify_valid_totp_returns_200_and_activates_mfa() {
    let db = owner_pool().await;
    let user_id = insert_test_user(&db).await;
    let (secret_b32, totp) = test_totp();
    let code = totp.generate_current().unwrap();

    let state = nubia_api::AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
    };
    let response = nubia_api::app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/verify")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"totp_secret": secret_b32, "totp_code": code}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let row = sqlx::query!("SELECT mfa_enabled FROM app_user WHERE id = $1", user_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(row.mfa_enabled);
}

// ── Test 2 : code invalide → 422 ──────────────────────────────────────────

#[tokio::test]
async fn mfa_verify_invalid_totp_returns_422() {
    let db = owner_pool().await;
    let user_id = insert_test_user(&db).await;
    let (secret_b32, _) = test_totp();

    let state = nubia_api::AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
    };
    let response = nubia_api::app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/verify")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"totp_secret": secret_b32, "totp_code": "wrongcode"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 3 : sans JWT → 401 ────────────────────────────────────────────────

#[tokio::test]
async fn mfa_verify_without_jwt_returns_401() {
    let (secret_b32, _) = test_totp();

    let state = nubia_api::AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
    };
    let response = nubia_api::app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/verify")
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"totp_secret": secret_b32, "totp_code": "123456"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
