//! Tests d'intégration : POST /v1/auth/refresh

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

/// Insère un app_user patient + patient_account + un refresh_token valide.
/// Retourne `(user_id, raw_token)`.
async fn insert_user_with_token(db: &PgPool) -> (Uuid, String) {
    let user_id = Uuid::new_v4();
    let raw_token = Uuid::new_v4().to_string();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("refresh-test+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (app_user_id, first_name, last_name) VALUES ($1, '', '')",
    )
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
           VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
    )
    .bind(user_id)
    .bind(&raw_token)
    .execute(db)
    .await
    .unwrap();

    (user_id, raw_token)
}

// ── Test 1 : happy path → 200 + nouveaux tokens ──────────────────────────────

#[tokio::test]
async fn refresh_happy_path_returns_200_with_new_tokens() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, raw_token) = insert_user_with_token(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret-refresh".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/refresh")
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"refresh_token": raw_token}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(v["access_token"].is_string(), "access_token manquant");
    assert!(v["refresh_token"].is_string(), "refresh_token manquant");
    assert_ne!(
        v["refresh_token"].as_str().unwrap(),
        raw_token,
        "le nouveau refresh_token doit être différent de l'ancien"
    );
    assert_eq!(v["token_type"], "Bearer");
    assert!(v["expires_in"].is_number(), "expires_in manquant");

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : token révoqué → 401 ─────────────────────────────────────────────

#[tokio::test]
async fn refresh_revoked_token_returns_401() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, raw_token) = insert_user_with_token(&db).await;

    // Révoquer manuellement le token
    sqlx::query(
        "UPDATE refresh_token SET revoked_at = now() \
         WHERE token_hash = encode(digest($1, 'sha256'), 'hex')",
    )
    .bind(&raw_token)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret-refresh".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/refresh")
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"refresh_token": raw_token}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3 : replay — l'ancien token est inutilisable après rotation ──────────

#[tokio::test]
async fn refresh_replay_of_old_token_returns_401() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, raw_token) = insert_user_with_token(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret-refresh".into(),
        mailer: Arc::new(StubMailer),
    };

    // Première rotation : succès
    let first = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/refresh")
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"refresh_token": raw_token}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::OK);

    // Replay avec l'ancien token : doit échouer
    let replay = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/refresh")
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"refresh_token": raw_token}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(replay.status(), StatusCode::UNAUTHORIZED);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}
