//! Tests d'intégration : GET /v1/acts

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

/// Sans filtre : retourne tous les actes (au moins 5 en seed).
#[tokio::test]
async fn acts_no_filter_returns_all() {
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
                .uri("/v1/acts")
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
    let data = v["data"].as_array().expect("data doit être un tableau");
    assert!(data.len() >= 5, "au moins 5 actes attendus (seed)");
    assert!(data[0]["id"].is_string());
    assert!(data[0]["label"].is_string());
    assert!(data[0]["motifs"].is_array());
}

/// Avec ?specialty_id= : retourne uniquement les actes de cette spécialité.
#[tokio::test]
async fn acts_filtered_by_specialty_returns_subset() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    // Spécialité "Orthodontie" (seed 0039) → 2 actes
    let specialty_id = "d2000000-0000-0000-0000-000000000003";

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/acts?specialty_id={specialty_id}"))
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
    let data = v["data"].as_array().expect("data doit être un tableau");
    assert_eq!(data.len(), 2, "2 actes pour Orthodontie");
    for item in data {
        assert_eq!(item["specialty_id"].as_str().unwrap(), specialty_id);
    }
}
