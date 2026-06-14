//! Tests d'intégration : GET /v1/search/slots

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
        .bind(format!("Cabinet Slots Test {}", suffix))
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("slots-pro-{}@nubia.test", suffix))
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
    .bind(format!("Dr Slots {}", suffix))
    .execute(db)
    .await
    .unwrap();

    provider_id
}

// ── Test 1 : happy path — 2 slots open pour un provider → data groupé correctement ──

#[tokio::test]
async fn search_slots_happy_path_returns_grouped_slots() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string()).await;

    // 2 créneaux futurs open pour le même provider
    sqlx::query(
        "INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, status) VALUES \
         ($1, $2, now() + interval '2 days', now() + interval '2 days 30 minutes', 'open'), \
         ($3, $2, now() + interval '1 day',  now() + interval '1 day 30 minutes',  'open')",
    )
    .bind(Uuid::new_v4())
    .bind(provider_id)
    .bind(Uuid::new_v4())
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/slots")
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

    // Au moins une entrée provider dans la réponse (peut y en avoir d'autres)
    let entry = data
        .iter()
        .find(|e| e["provider_id"].as_str() == Some(&provider_id.to_string()))
        .expect("le provider inséré doit apparaître dans data");

    // Structure correcte
    assert!(
        entry["provider_id"].is_string(),
        "provider_id doit être une string"
    );
    assert!(
        entry["display_name"].is_string(),
        "display_name doit être une string"
    );
    assert!(
        entry["first_slot_at"].is_string(),
        "first_slot_at doit être une string"
    );
    let slots = entry["slots"]
        .as_array()
        .expect("slots doit être un tableau");
    assert_eq!(slots.len(), 2, "2 slots open attendus pour ce provider");

    // Tri ASC : first_slot_at == le plus ancien des deux slots
    let t0 = slots[0]["starts_at"].as_str().unwrap();
    let t1 = slots[1]["starts_at"].as_str().unwrap();
    assert!(t0 < t1, "slots doivent être triés ASC par starts_at");
    assert_eq!(
        entry["first_slot_at"].as_str().unwrap(),
        t0,
        "first_slot_at doit correspondre au premier slot"
    );

    // Structure d'un slot
    assert!(
        slots[0]["slot_id"].is_string(),
        "slot_id doit être une string"
    );
    assert!(
        slots[0]["starts_at"].is_string(),
        "starts_at doit être une string"
    );

    // Nettoyage
    sqlx::query("DELETE FROM availability_slot WHERE provider_id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : `near` malformé → 422 UNPROCESSABLE_ENTITY ──────────────────────

#[tokio::test]
async fn search_slots_near_malformed_returns_422() {
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
                .uri("/v1/search/slots?near=abc")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 3 : `bbox` malformé (3 parts au lieu de 4) → 422 ───────────────────

#[tokio::test]
async fn search_slots_bbox_malformed_returns_422() {
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
                .uri("/v1/search/slots?bbox=2.0,48.0,3.0")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 4 : slot `held` exclu — status != 'open' → absent de data ────────────

#[tokio::test]
async fn search_slots_held_slot_excluded() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string()).await;

    // Un slot 'held' (réservation en cours) — ne doit PAS apparaître dans search/slots
    sqlx::query(
        "INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, status) \
         VALUES ($1, $2, now() + interval '1 day', now() + interval '1 day 30 minutes', 'held')",
    )
    .bind(Uuid::new_v4())
    .bind(provider_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/slots")
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

    // Ce provider ne doit PAS apparaître : son seul slot est 'held'
    let found = data
        .iter()
        .any(|e| e["provider_id"].as_str() == Some(&provider_id.to_string()));
    assert!(
        !found,
        "provider avec slot held seulement ne doit pas apparaître dans data"
    );

    // Nettoyage
    sqlx::query("DELETE FROM availability_slot WHERE provider_id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
}
