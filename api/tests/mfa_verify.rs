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
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
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
    // Skip when no DB is reachable (CI rust-ci.yml has no Postgres sidecar).
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    let db = owner_pool().await;
    let user_id = insert_test_user(&db).await;
    let (secret_b32, totp) = test_totp();
    let code = totp.generate_current().unwrap();

    let state = nubia_api::AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: std::sync::Arc::new(nubia_api::StubMailer),
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
    // Skip when no DB is reachable (CI rust-ci.yml has no Postgres sidecar).
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    let db = owner_pool().await;
    let user_id = insert_test_user(&db).await;
    let (secret_b32, _) = test_totp();

    let state = nubia_api::AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: std::sync::Arc::new(nubia_api::StubMailer),
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

// ── Test 4 : JWT patient → 403 ────────────────────────────────────────────────
// ProClaims extractor : `kind != "pro"` → AppError::Forbidden.
// mfa/verify est pro-only ; un token patient valide doit retourner 403.

#[tokio::test]
async fn mfa_verify_patient_jwt_returns_403() {
    // Pas besoin d'un vrai DB — ProClaims extractor rejette avant d'accéder à la DB.
    let db = sqlx::PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = nubia_api::AppState {
        db,
        jwt_secret: JWT_SECRET.into(),
        mailer: std::sync::Arc::new(nubia_api::StubMailer),
    };

    let user_id = Uuid::new_v4();
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let patient_token = jsonwebtoken::encode(
        &jsonwebtoken::Header::default(),
        &serde_json::json!({"sub": user_id, "kind": "patient", "account_id": user_id, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let (secret_b32, _) = test_totp();

    let response = nubia_api::app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/verify")
                .header("Authorization", format!("Bearer {}", patient_token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::json!({"totp_secret": secret_b32, "totp_code": "123456"})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn mfa_verify_without_jwt_returns_401() {
    // Skip when no DB is reachable (CI rust-ci.yml has no Postgres sidecar).
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    let (secret_b32, _) = test_totp();

    let state = nubia_api::AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: std::sync::Arc::new(nubia_api::StubMailer),
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
