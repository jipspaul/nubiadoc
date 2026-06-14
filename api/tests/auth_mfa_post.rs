//! Tests d'intégration : POST /v1/auth/mfa/verify

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

const JWT_SECRET: &str = "test-jwt-secret-for-mfa-post";

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

fn make_patient_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let claims =
        json!({"sub": user_id, "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp});
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn lazy_app_state() -> nubia_api::AppState {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    nubia_api::AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: std::sync::Arc::new(nubia_api::StubMailer),
    }
}

fn valid_totp_pair() -> (String, String) {
    let secret = Secret::generate_secret();
    let secret_b32 = secret.to_encoded().to_string();
    let totp = TOTP::new(Algorithm::SHA1, 6, 1, 30, secret.to_bytes().unwrap()).unwrap();
    let code = totp.generate_current().unwrap();
    (secret_b32, code)
}

// ── Test 1 : happy path — code valide → 200 + mfa_enabled = true en DB ─────

#[tokio::test]
async fn mfa_verify_valid_code_returns_200_and_activates() {
    let Some(owner_url) = std::env::var("DATABASE_URL").ok() else {
        return;
    };
    let Some(app_url) = std::env::var("APP_DATABASE_URL").ok() else {
        return;
    };

    let owner_db = PgPool::connect(&owner_url).await.unwrap();
    let app_db = PgPool::connect(&app_url).await.unwrap();

    let user_id = Uuid::new_v4();
    sqlx::query!(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        user_id,
        format!("mfa_post_ok+{}@nubia.test", user_id),
    )
    .execute(&owner_db)
    .await
    .unwrap();

    let (secret_b32, code) = valid_totp_pair();

    let state = nubia_api::AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
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

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["message"], "MFA activée.");

    let row = sqlx::query!("SELECT mfa_enabled FROM app_user WHERE id = $1", user_id)
        .fetch_one(&owner_db)
        .await
        .unwrap();
    assert!(row.mfa_enabled);

    sqlx::query!("DELETE FROM app_user WHERE id = $1", user_id)
        .execute(&owner_db)
        .await
        .unwrap();
}

// ── Test 2 : JWT absent → 401 ─────────────────────────────────────────────

#[tokio::test]
async fn mfa_verify_no_jwt_returns_401() {
    let (secret_b32, code) = valid_totp_pair();
    let response = nubia_api::app(lazy_app_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/verify")
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"totp_secret": secret_b32, "totp_code": code}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 3 : JWT patient → 403 ────────────────────────────────────────────

#[tokio::test]
async fn mfa_verify_patient_jwt_returns_403() {
    let (secret_b32, code) = valid_totp_pair();
    let user_id = Uuid::new_v4();
    let response = nubia_api::app(lazy_app_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/verify")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"totp_secret": secret_b32, "totp_code": code}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 4 : secret TOTP malformé → 422 (validé avant toute DB) ─────────

#[tokio::test]
async fn mfa_verify_invalid_totp_secret_returns_422() {
    let user_id = Uuid::new_v4();
    let response = nubia_api::app(lazy_app_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/verify")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(user_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"totp_secret": "NOT-A-VALID-BASE32!!!", "totp_code": "123456"})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "validation_error");
}
