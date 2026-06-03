use std::sync::Arc;

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::{PgPool, Row};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

async fn test_state() -> AppState {
    let pool =
        PgPool::connect(&std::env::var("APP_DATABASE_URL").expect("APP_DATABASE_URL must be set"))
            .await
            .expect("failed to connect to test DB");
    AppState {
        pool,
        mailer: Arc::new(StubMailer),
    }
}

#[tokio::test]
async fn forgot_password_known_email_returns_200_and_sets_token() {
    let state = test_state().await;
    let email = format!("reset_{}@test.local", Uuid::new_v4());

    sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind) VALUES ($1, 'placeholder', 'patient')",
    )
    .bind(&email)
    .execute(&state.pool)
    .await
    .expect("insert test user");

    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/forgot")
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"email":"{}"}}"#, email)))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["message"], "Si un compte existe, un email a été envoyé.");

    let row = sqlx::query("SELECT password_reset_token FROM app_user WHERE email = $1")
        .bind(&email)
        .fetch_one(&state.pool)
        .await
        .expect("fetch user after forgot");

    let token: Option<String> = row.try_get("password_reset_token").unwrap();
    assert!(
        token.is_some(),
        "password_reset_token must be set for a known email"
    );

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&state.pool)
        .await
        .unwrap();
}

#[tokio::test]
async fn forgot_password_unknown_email_returns_200_neutral() {
    let state = test_state().await;

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/forgot")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"email":"nobody@nowhere.example"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["message"], "Si un compte existe, un email a été envoyé.");
}
