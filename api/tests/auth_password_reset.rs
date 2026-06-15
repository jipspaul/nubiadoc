use std::sync::Arc;

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::{PgPool, Row};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

async fn owner_pool() -> Option<PgPool> {
    let url = std::env::var("DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

async fn test_state() -> Option<AppState> {
    let url = std::env::var("APP_DATABASE_URL").ok()?;
    let pool = PgPool::connect(&url).await.ok()?;
    Some(AppState {
        db: pool,
        jwt_secret: String::new(),
        mailer: Arc::new(StubMailer),
    })
}

#[tokio::test]
async fn reset_valid_token_returns_204_and_updates_password() {
    let Some(state) = test_state().await else {
        return;
    };
    let Some(owner_db) = owner_pool().await else {
        return;
    };
    let email = format!("reset_ok_{}@test.local", Uuid::new_v4());
    let token = Uuid::new_v4().to_string();

    sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind, \
         password_reset_token, password_reset_expires_at) \
         VALUES ($1, 'placeholder', 'patient', \
                 encode(digest($2, 'sha256'), 'hex'), now() + interval '1 hour')",
    )
    .bind(&email)
    .bind(&token)
    .execute(&owner_db)
    .await
    .expect("insert test user");

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/reset")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"token":"{}","new_password":"NewPass1"}}"#,
                    token
                )))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    let row =
        sqlx::query("SELECT password_hash, password_reset_token FROM app_user WHERE email = $1")
            .bind(&email)
            .fetch_one(&owner_db)
            .await
            .expect("fetch user after reset");

    let hash: String = row.try_get("password_hash").unwrap();
    assert_ne!(hash, "placeholder", "password_hash must be updated");

    let reset_token: Option<String> = row.try_get("password_reset_token").unwrap();
    assert!(
        reset_token.is_none(),
        "password_reset_token must be NULL after reset"
    );

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_db)
        .await
        .unwrap();
}

#[tokio::test]
async fn reset_expired_token_returns_410_link_expired() {
    let Some(state) = test_state().await else {
        return;
    };
    let Some(owner_db) = owner_pool().await else {
        return;
    };
    let email = format!("reset_exp_{}@test.local", Uuid::new_v4());
    let token = Uuid::new_v4().to_string();

    sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind, \
         password_reset_token, password_reset_expires_at) \
         VALUES ($1, 'placeholder', 'patient', \
                 encode(digest($2, 'sha256'), 'hex'), now() - interval '2 hours')",
    )
    .bind(&email)
    .bind(&token)
    .execute(&owner_db)
    .await
    .expect("insert test user");

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/reset")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"token":"{}","new_password":"NewPass1"}}"#,
                    token
                )))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::GONE);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "link_expired");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_db)
        .await
        .unwrap();
}

/// Edge case état DB : un reset réussi révoque tous les refresh tokens actifs (forced logout).
/// Le handler UPDATE refresh_token SET revoked_at=now() après le reset du mot de passe.
#[tokio::test]
async fn reset_valid_token_revokes_all_refresh_tokens() {
    let Some(state) = test_state().await else {
        return;
    };
    let Some(owner_db) = owner_pool().await else {
        return;
    };
    let email = format!("reset_revoke_{}@test.local", uuid::Uuid::new_v4());
    let token = uuid::Uuid::new_v4().to_string();

    sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind, \
         password_reset_token, password_reset_expires_at) \
         VALUES ($1, 'placeholder', 'patient', \
                 encode(digest($2, 'sha256'), 'hex'), now() + interval '1 hour')",
    )
    .bind(&email)
    .bind(&token)
    .execute(&owner_db)
    .await
    .expect("insert test user");

    // Récupère l'user_id pour y rattacher des refresh tokens.
    let user_id: uuid::Uuid = sqlx::query("SELECT id FROM app_user WHERE email = $1")
        .bind(&email)
        .fetch_one(&owner_db)
        .await
        .expect("fetch user_id")
        .try_get("id")
        .unwrap();

    // Insère 2 refresh tokens actifs pour cet utilisateur.
    for _ in 0..2 {
        let raw = uuid::Uuid::new_v4().to_string();
        sqlx::query(
            r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
               VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
        )
        .bind(user_id)
        .bind(&raw)
        .execute(&owner_db)
        .await
        .unwrap();
    }

    let response = app(state)
        .oneshot(
            axum::http::Request::builder()
                .method("POST")
                .uri("/v1/auth/password/reset")
                .header("content-type", "application/json")
                .body(axum::body::Body::from(format!(
                    r#"{{"token":"{}","new_password":"NewPass1"}}"#,
                    token
                )))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), axum::http::StatusCode::NO_CONTENT);

    let row = sqlx::query(
        "SELECT COUNT(*) AS cnt FROM refresh_token \
         WHERE app_user_id = $1 AND revoked_at IS NULL",
    )
    .bind(user_id)
    .fetch_one(&owner_db)
    .await
    .unwrap();
    let remaining: i64 = row.try_get("cnt").unwrap();
    assert_eq!(
        remaining, 0,
        "reset doit révoquer tous les refresh tokens actifs"
    );

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_db)
        .await
        .unwrap();
}

#[tokio::test]
async fn reset_unknown_token_returns_404() {
    let Some(state) = test_state().await else {
        return;
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/reset")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"token":"no-such-token-anywhere","new_password":"NewPass1"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "not_found");
}
