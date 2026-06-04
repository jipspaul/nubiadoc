use std::sync::Arc;

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::{PgPool, Row};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

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
async fn reset_valid_token_updates_password() {
    let Some(state) = test_state().await else {
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
    .execute(&state.db)
    .await
    .expect("insert test user");

    let response = app(state.clone())
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

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["message"], "Mot de passe réinitialisé.");

    let row =
        sqlx::query("SELECT password_hash, password_reset_token FROM app_user WHERE email = $1")
            .bind(&email)
            .fetch_one(&state.db)
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
        .execute(&state.db)
        .await
        .unwrap();
}

#[tokio::test]
async fn reset_expired_token_returns_422() {
    let Some(state) = test_state().await else {
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
    .execute(&state.db)
    .await
    .expect("insert test user");

    let response = app(state.clone())
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

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "validation_error");
    assert_eq!(v["detail"], "Token invalide ou expiré.");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&state.db)
        .await
        .unwrap();
}

#[tokio::test]
async fn reset_unknown_token_returns_422() {
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

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "validation_error");
    assert_eq!(v["detail"], "Token invalide ou expiré.");
}
