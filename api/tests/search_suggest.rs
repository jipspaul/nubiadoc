//! Tests d'intégration : GET /v1/search/suggest

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;

use nubia_api::{app, AppState, StubMailer};

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok()
}

/// Happy path : "dent" correspond au motif "dent manquante" de l'acte "Pose d'implant".
#[tokio::test]
async fn suggest_match_dent_returns_results() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/suggest?q=dent")
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
    assert!(
        v["specialties"].is_array(),
        "specialties doit être un tableau"
    );
    assert!(v["acts"].is_array(), "acts doit être un tableau");

    let total = v["specialties"].as_array().unwrap().len() + v["acts"].as_array().unwrap().len();
    assert!(total >= 1, "au moins 1 résultat attendu pour 'dent'");

    // score fixé à 1.0
    if let Some(item) = v["acts"].as_array().unwrap().first() {
        assert_eq!(item["score"].as_f64().unwrap(), 1.0);
    }
}

/// Requête trop courte (1 char) → 422 Unprocessable Entity.
#[tokio::test]
async fn suggest_too_short_returns_422() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/suggest?q=x")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

/// Terme inconnu → 200 avec listes vides.
#[tokio::test]
async fn suggest_unknown_term_returns_empty() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/suggest?q=zzztermeinconnu")
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
    assert_eq!(v["specialties"].as_array().unwrap().len(), 0);
    assert_eq!(v["acts"].as_array().unwrap().len(), 0);
}
