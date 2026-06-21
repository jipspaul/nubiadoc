use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok()
}

#[tokio::test]
async fn health_db_returns_200_ok() {
    if !db_available() {
        return;
    }
    let state = nubia_api::AppState {
        db: app_pool().await,
        jwt_secret: String::new(),
        mailer: Arc::new(nubia_api::StubMailer),
    };
    let app = nubia_api::app(state);
    let response = app
        .oneshot(
            Request::builder()
                .uri("/v1/health/db")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["ok"], serde_json::json!(true));
    assert!(v["ms"].is_number());
}

#[tokio::test]
async fn health_returns_200_ok() {
    let app = nubia_api::router();
    let response = app
        .oneshot(
            Request::builder()
                .uri("/v1/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v, serde_json::json!({"status": "ok"}));
}
