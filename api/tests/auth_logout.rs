//! Tests d'intégration : POST /v1/auth/logout

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

const JWT_SECRET: &str = "test-jwt-secret-logout";

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

fn make_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère un app_user + un refresh_token. Retourne `(user_id, raw_token)`.
async fn insert_user_with_token(db: &PgPool) -> (Uuid, String) {
    let user_id = Uuid::new_v4();
    let raw_token = Uuid::new_v4().to_string();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("logout-test+{}@nubia.test", user_id))
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

// ── Test 1 : happy path → 204 + revoked_at IS NOT NULL ───────────────────────

#[tokio::test]
async fn logout_happy_path_returns_204_and_sets_revoked_at() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, raw_token) = insert_user_with_token(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/logout")
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"refresh_token": raw_token}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    let row = sqlx::query(
        "SELECT COUNT(*) AS cnt FROM refresh_token \
         WHERE app_user_id = $1 AND revoked_at IS NOT NULL",
    )
    .bind(user_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let cnt: i64 = row.try_get("cnt").unwrap();
    assert_eq!(cnt, 1, "revoked_at doit être défini après logout");

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : sans JWT → 401 ──────────────────────────────────────────────────

#[tokio::test]
async fn logout_without_jwt_returns_401() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/logout")
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"refresh_token": "dummy-token"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 4 : X-Revoke-All: true → 204 + tous les tokens révoqués ─────────────
// La branche `revoke_all` dans le handler révoque toutes les sessions actives
// en une seule UPDATE. Vérifie que tous les tokens de l'utilisateur ont
// `revoked_at IS NOT NULL` après l'appel.

#[tokio::test]
async fn logout_revoke_all_returns_204_and_revokes_all_tokens() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("logout-revoke-all+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    // Insère 3 tokens actifs pour ce user.
    for _ in 0..3 {
        let raw = Uuid::new_v4().to_string();
        sqlx::query(
            r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
               VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
        )
        .bind(user_id)
        .bind(&raw)
        .execute(&db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/logout")
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .header("X-Revoke-All", "true")
                .header("Content-Type", "application/json")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    let row = sqlx::query(
        "SELECT COUNT(*) AS cnt FROM refresh_token \
         WHERE app_user_id = $1 AND revoked_at IS NULL",
    )
    .bind(user_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let remaining: i64 = row.try_get("cnt").unwrap();
    assert_eq!(
        remaining, 0,
        "X-Revoke-All doit révoquer tous les tokens actifs"
    );

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

#[tokio::test]
async fn logout_other_user_refresh_token_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    // User A : porteur du JWT
    let user_a_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_a_id)
    .bind(format!("logout-a+{}@nubia.test", user_a_id))
    .execute(&db)
    .await
    .unwrap();

    // User B : propriétaire du refresh token
    let (user_b_id, raw_token_b) = insert_user_with_token(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/logout")
                .header("Authorization", format!("Bearer {}", make_jwt(user_a_id)))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"refresh_token": raw_token_b}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    sqlx::query("DELETE FROM app_user WHERE id = ANY($1)")
        .bind(vec![user_a_id, user_b_id])
        .execute(&db)
        .await
        .ok();
}
