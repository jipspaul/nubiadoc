//! Tests d'intégration : POST /v1/auth/mfa/disable (#7328)
//!
//! Requiert un Postgres accessible via APP_DATABASE_URL / DATABASE_URL
//! (sidecar CI ou env local) et `KMS_MASTER_KEY` (posée par le test si
//! absente — l'enrôlement MFA préalable chiffre le secret TOTP).

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
    Argon2,
};
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use base64::{engine::general_purpose::STANDARD, Engine};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::time::{SystemTime, UNIX_EPOCH};
use totp_rs::{Algorithm, Secret, TOTP};
use tower::ServiceExt;
use uuid::Uuid;

const JWT_SECRET: &str = "test-jwt-secret-for-mfa-disable";

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

fn ensure_kms_key() {
    if std::env::var("KMS_MASTER_KEY").is_err() {
        std::env::set_var("KMS_MASTER_KEY", STANDARD.encode([7u8; 32]));
    }
}

fn app_state(db: PgPool) -> nubia_api::AppState {
    nubia_api::AppState {
        db,
        jwt_secret: JWT_SECRET.into(),
        mailer: std::sync::Arc::new(nubia_api::StubMailer),
    }
}

fn hash_password(password: &str) -> String {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .unwrap()
        .to_string()
}

async fn json_body(response: axum::response::Response) -> serde_json::Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

fn post_json(uri: &str, bearer: Option<&str>, body: serde_json::Value) -> Request<Body> {
    let mut builder = Request::builder()
        .method("POST")
        .uri(uri)
        .header("Content-Type", "application/json");
    if let Some(token) = bearer {
        builder = builder.header("Authorization", format!("Bearer {token}"));
    }
    builder.body(Body::from(body.to_string())).unwrap()
}

fn current_code(secret_b32: &str) -> String {
    let bytes = Secret::Encoded(secret_b32.to_string()).to_bytes().unwrap();
    TOTP::new(Algorithm::SHA1, 6, 1, 30, bytes)
        .unwrap()
        .generate_current()
        .unwrap()
}

/// Crée un compte pro avec MFA déjà activée (enroll + verify), retourne
/// `(user_id, email, password)`.
async fn insert_pro_with_mfa_enabled(db: &PgPool) -> (Uuid, String, String) {
    ensure_kms_key();
    let user_id = Uuid::new_v4();
    let email = format!("mfa-disable+{user_id}@nubia.test");
    let password = "password123";
    sqlx::query("INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, $3, 'pro')")
        .bind(user_id)
        .bind(&email)
        .bind(hash_password(password))
        .execute(db)
        .await
        .unwrap();
    let jwt = make_pro_jwt(user_id);
    let secret = Secret::generate_secret();
    let secret_b32 = secret.to_encoded().to_string();
    let code = current_code(&secret_b32);
    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/mfa/verify",
            Some(&jwt),
            json!({"totp_secret": secret_b32, "totp_code": code}),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    (user_id, email, password.to_string())
}

// ── Scénario QA #7328 : mot de passe correct → MFA désactivée, un login
//    mot de passe seul redevient possible ─────────────────────────────────

#[tokio::test]
async fn mfa_disable_correct_password_returns_200_and_login_no_longer_requires_code() {
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, email, password) = insert_pro_with_mfa_enabled(&db).await;
    let jwt = make_pro_jwt(user_id);

    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/mfa/disable",
            Some(&jwt),
            json!({"password": password}),
        ))
        .await
        .unwrap();
    let status = response.status();
    let body = json_body(response).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["message"], "MFA désactivée.");

    let row = sqlx::query!("SELECT totp_enabled FROM app_user WHERE id = $1", user_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(!row.totp_enabled);
    let count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM mfa_enrollment WHERE app_user_id = $1")
            .bind(user_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(count, 0);

    // Login mot de passe seul redevient possible (mot de passe inchangé).
    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/login",
            None,
            json!({"email": email, "password": password}),
        ))
        .await
        .unwrap();
    let status = response.status();
    let body = json_body(response).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert!(body["access_token"].as_str().is_some_and(|t| !t.is_empty()));
}

// ── Mauvais mot de passe → 401, MFA reste active ──────────────────────────

#[tokio::test]
async fn mfa_disable_wrong_password_returns_401_and_leaves_mfa_enabled() {
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, _email, _password) = insert_pro_with_mfa_enabled(&db).await;
    let jwt = make_pro_jwt(user_id);

    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/mfa/disable",
            Some(&jwt),
            json!({"password": "totalement-faux"}),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);

    let row = sqlx::query!("SELECT totp_enabled FROM app_user WHERE id = $1", user_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(row.totp_enabled);
}

// ── MFA pas activée → 409 invalid_status ──────────────────────────────────

#[tokio::test]
async fn mfa_disable_when_not_enabled_returns_409() {
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let password = "password123";
    sqlx::query("INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, $3, 'pro')")
        .bind(user_id)
        .bind(format!("mfa-disable-noop+{user_id}@nubia.test"))
        .bind(hash_password(password))
        .execute(&db)
        .await
        .unwrap();

    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/mfa/disable",
            Some(&make_pro_jwt(user_id)),
            json!({"password": password}),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CONFLICT);
    assert_eq!(json_body(response).await["code"], "invalid_status");
}

// ── Sans JWT → 401 ─────────────────────────────────────────────────────────

#[tokio::test]
async fn mfa_disable_without_jwt_returns_401() {
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    let state = app_state(app_pool().await);
    let response = nubia_api::app(state)
        .oneshot(post_json(
            "/v1/auth/mfa/disable",
            None,
            json!({"password": "whatever123"}),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
