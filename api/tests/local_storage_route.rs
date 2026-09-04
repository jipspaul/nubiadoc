//! Tests d'intégration : GET /v1/storage/local/*key (#6425)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;

use nubia_api::{app_with_dispatcher, AppState, StubJobDispatcher, StubMailer, StubStorageSigner};

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

async fn state() -> AppState {
    AppState {
        db: app_pool().await,
        jwt_secret: "test-jwt-secret-local-storage".to_string(),
        mailer: Arc::new(StubMailer),
    }
}

#[tokio::test]
async fn serve_local_object_rejects_a_tampered_signature() {
    if !db_available() {
        return;
    }

    let response = app_with_dispatcher(
        state().await,
        Arc::new(StubJobDispatcher),
        Arc::new(StubStorageSigner),
    )
    .oneshot(
        Request::builder()
            .method("GET")
            .uri("/v1/storage/local/some-key?expires=9999999999&sig=deadbeef")
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::FORBIDDEN,
        "signature invalide -> 403, pas de contenu servi"
    );
}

#[tokio::test]
async fn serve_local_object_missing_query_params_returns_400() {
    if !db_available() {
        return;
    }

    let response = app_with_dispatcher(
        state().await,
        Arc::new(StubJobDispatcher),
        Arc::new(StubStorageSigner),
    )
    .oneshot(
        Request::builder()
            .method("GET")
            .uri("/v1/storage/local/some-key")
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}
