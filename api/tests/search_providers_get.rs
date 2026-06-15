//! Tests d'intégration : GET /v1/search/providers

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

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

// ── Helpers de fixture ────────────────────────────────────────────────────────

/// Insère un provider listé (is_listed=true) avec son cabinet et son app_user.
/// Retourne le provider_id.
async fn insert_provider(db: &PgPool, suffix: &str) -> Uuid {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Providers Test {}", suffix))
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("providers-pro-{}@nubia.test", suffix))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(user_id)
    .bind(format!("Dr Providers {}", suffix))
    .execute(db)
    .await
    .unwrap();

    provider_id
}

/// Insère un provider non listé (is_listed=false).
/// Retourne le provider_id.
async fn insert_unlisted_provider(db: &PgPool, suffix: &str) -> Uuid {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Unlisted {}", suffix))
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("unlisted-pro-{}@nubia.test", suffix))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, true, false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(user_id)
    .bind(format!("Dr Unlisted {}", suffix))
    .execute(db)
    .await
    .unwrap();

    provider_id
}

// ── Test 1 : happy path — provider listé → apparaît dans data avec structure correcte ──

#[tokio::test]
async fn search_providers_happy_path_returns_listed_provider() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string()).await;

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

    // Structure de réponse correcte
    let data = v["data"].as_array().expect("data doit être un tableau");
    assert!(v["facets"].is_object(), "facets doit être un objet");
    assert!(v["page"].is_object(), "page doit être un objet");
    assert!(
        v["page"]["page"].is_number(),
        "page.page doit être un nombre"
    );
    assert!(
        v["page"]["per_page"].is_number(),
        "page.per_page doit être un nombre"
    );
    assert!(
        v["page"]["total"].is_number(),
        "page.total doit être un nombre"
    );

    // Le provider inséré doit apparaître
    let entry = data
        .iter()
        .find(|e| e["provider_id"].as_str() == Some(&provider_id.to_string()))
        .expect("le provider listé doit apparaître dans data");

    // Structure d'un item
    assert!(
        entry["provider_id"].is_string(),
        "provider_id doit être une string"
    );
    assert!(
        entry["display_name"].is_string(),
        "display_name doit être une string"
    );
    assert!(
        entry["is_listed"].as_bool() == Some(true),
        "is_listed doit être true"
    );

    // Nettoyage
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : provider non listé → absent de data ──────────────────────────────

#[tokio::test]
async fn search_providers_unlisted_provider_excluded() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_unlisted_provider(&db, &Uuid::new_v4().to_string()).await;

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
    let data = v["data"].as_array().expect("data doit être un tableau");

    // Le provider non listé NE DOIT PAS apparaître
    let found = data
        .iter()
        .any(|e| e["provider_id"].as_str() == Some(&provider_id.to_string()));
    assert!(
        !found,
        "provider is_listed=false ne doit pas apparaître dans data"
    );

    // Nettoyage
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3 : `near` malformé → 422 UNPROCESSABLE_ENTITY ──────────────────────

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

    // "near=abc" ne contient pas de virgule → parsing lat échoue → 422
    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/providers?near=abc")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 4 : `bbox` malformé (3 parts au lieu de 4) → 422 ───────────────────

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

    // bbox attend 4 valeurs : minLng,minLat,maxLng,maxLat → 3 ici → 422
    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/providers?bbox=2.0,48.0,3.0")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 5 : pagination par défaut (page=1, per_page=20) ─────────────────────

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

    // Valeurs par défaut : page=1, per_page=20
    assert_eq!(
        v["page"]["page"].as_i64(),
        Some(1),
        "page par défaut doit être 1"
    );
    assert_eq!(
        v["page"]["per_page"].as_i64(),
        Some(20),
        "per_page par défaut doit être 20"
    );
    // data ne dépasse jamais per_page
    let data = v["data"].as_array().expect("data doit être un tableau");
    assert!(
        data.len() <= 20,
        "data ne doit pas dépasser per_page=20 résultats"
    );
}
