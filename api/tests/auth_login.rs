//! Tests d'intégration : POST /v1/auth/login

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
    Argon2,
};
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

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

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

fn hash_password(password: &str) -> String {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .unwrap()
        .to_string()
}

// ── Test 1 : happy path → 200 + { access_token, refresh_token, token_type, expires_in } ──

#[tokio::test]
async fn login_happy_path_returns_200_with_tokens() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let email = format!("login_{}@test.local", Uuid::new_v4());
    let password = "password123";
    let hash = hash_password(password);

    sqlx::query("INSERT INTO app_user (email, password_hash, kind) VALUES ($1, $2, 'patient')")
        .bind(&email)
        .bind(&hash)
        .execute(&db)
        .await
        .expect("insert test user");

    sqlx::query(
        "INSERT INTO patient_account (app_user_id, first_name, last_name) \
         SELECT id, '', '' FROM app_user WHERE email = $1",
    )
    .bind(&email)
    .execute(&db)
    .await
    .expect("insert patient_account");

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email": email, "password": password}).to_string(),
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
    assert!(
        v["access_token"].is_string(),
        "access_token doit être présent"
    );
    assert!(
        v["refresh_token"].is_string(),
        "refresh_token doit être présent"
    );
    assert_eq!(v["token_type"], "Bearer");
    assert!(v["expires_in"].is_number(), "expires_in doit être présent");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : mauvais mot de passe → 401 unauthenticated ──────────────────────

#[tokio::test]
async fn login_wrong_password_returns_401_unauthenticated() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let email = format!("login_bad_pw_{}@test.local", Uuid::new_v4());
    let hash = hash_password("correct-password");

    sqlx::query("INSERT INTO app_user (email, password_hash, kind) VALUES ($1, $2, 'patient')")
        .bind(&email)
        .bind(&hash)
        .execute(&db)
        .await
        .expect("insert test user");

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email": email, "password": "wrong-password"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "unauthenticated");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3 : pro avec MFA activée, sans mfa_code → 401 mfa_required ──────────

#[tokio::test]
async fn login_pro_mfa_enabled_without_code_returns_401_mfa_required() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let email = format!("login_mfa_{}@test.local", Uuid::new_v4());
    let password = "password123";
    let hash = hash_password(password);

    sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind, totp_enabled, totp_secret) \
         VALUES ($1, $2, 'pro', true, 'JBSWY3DPEHPK3PXP')",
    )
    .bind(&email)
    .bind(&hash)
    .execute(&db)
    .await
    .expect("insert pro test user with totp");

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email": email, "password": password}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "mfa_required");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&db)
        .await
        .ok();
}
