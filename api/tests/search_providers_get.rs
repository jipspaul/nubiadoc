//! Tests d'intégration : GET /v1/search/providers

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

/// Happy path : requête sans filtre → 200 avec structure attendue (data, facets, page).
#[tokio::test]
async fn search_providers_no_filter_returns_200() {
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
                .uri("/v1/search/providers")
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

    assert!(v["data"].is_array(), "data doit être un tableau");
    assert!(
        v["facets"]["specialty"].is_array(),
        "facets.specialty doit être un tableau"
    );
    assert!(
        v["facets"]["sector"].is_array(),
        "facets.sector doit être un tableau"
    );
    assert!(v["page"]["page"].is_number(), "page.page doit être un nombre");
    assert!(
        v["page"]["per_page"].is_number(),
        "page.per_page doit être un nombre"
    );
    assert!(
        v["page"]["total"].is_number(),
        "page.total doit être un nombre"
    );
}

/// Pagination par défaut : page=1, per_page=20 reflétés dans la réponse.
#[tokio::test]
async fn search_providers_default_pagination() {
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
                .uri("/v1/search/providers?page=1&per_page=5")
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

    assert_eq!(v["page"]["page"].as_i64().unwrap(), 1);
    assert_eq!(v["page"]["per_page"].as_i64().unwrap(), 5);
    // Au plus 5 résultats dans data
    let data_len = v["data"].as_array().unwrap().len();
    assert!(data_len <= 5, "data ne doit pas dépasser per_page=5");
}

/// `near` mal formé (une seule valeur) → 422 Unprocessable Entity.
#[tokio::test]
async fn search_providers_near_malformed_returns_422() {
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
                .uri("/v1/search/providers?near=48.8566")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

/// `bbox` avec 3 valeurs au lieu de 4 → 422 Unprocessable Entity.
#[tokio::test]
async fn search_providers_bbox_malformed_returns_422() {
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
                .uri("/v1/search/providers?bbox=2.2,48.8,2.4")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

/// Terme inconnu → 200 avec tableau data vide.
#[tokio::test]
async fn search_providers_unknown_term_returns_empty_data() {
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
                .uri("/v1/search/providers?q=zzztermeinconnu99999")
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
    assert_eq!(
        v["data"].as_array().unwrap().len(),
        0,
        "aucun résultat attendu pour un terme inconnu"
    );
    assert_eq!(v["page"]["total"].as_i64().unwrap(), 0);
}
