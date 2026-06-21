//! Tests d'intégration : rate limit par IP sur POST /v1/auth/login

use axum::{
    body::Body,
    extract::ConnectInfo,
    http::{Request, StatusCode},
};
use serde_json::json;
use sqlx::PgPool;
use std::net::SocketAddr;
use std::sync::Arc;
use tower::ServiceExt;

use nubia_api::{app, AppState, StubMailer};

fn lazy_state() -> AppState {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    AppState {
        db,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    }
}

// ── Test : 5 tentatives → 6ème → 429 + Retry-After ──────────────────────────
// Le rate limit IP (5/60s) se déclenche avant tout accès DB : pas de vraie
// base de données requise pour ce test.

#[tokio::test]
async fn login_ip_rate_limit_returns_429_on_sixth_attempt() {
    let ip: SocketAddr = "10.0.0.1:1234".parse().unwrap();

    for attempt in 0..5 {
        let response = app(lazy_state())
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/auth/login")
                    .extension(ConnectInfo(ip))
                    .header("content-type", "application/json")
                    .body(Body::from(
                        json!({"email": "rate@test.local", "password": "wrong"}).to_string(),
                    ))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_ne!(
            response.status(),
            StatusCode::TOO_MANY_REQUESTS,
            "tentative {} : ne doit pas encore être rate-limitée",
            attempt + 1
        );
    }

    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .extension(ConnectInfo(ip))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email": "rate@test.local", "password": "wrong"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::TOO_MANY_REQUESTS);
    assert!(
        response.headers().contains_key("retry-after"),
        "le header Retry-After doit être présent sur la réponse 429"
    );
}
