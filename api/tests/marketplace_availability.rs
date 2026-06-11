//! Tests d'intégration : GET /v1/providers/:id/availability

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
        .bind(format!("Cabinet Avail Test {}", suffix))
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("avail-pro-{}@nubia.test", suffix))
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
    .bind(format!("Dr Avail {}", suffix))
    .execute(db)
    .await
    .unwrap();

    provider_id
}

// ── Test 1 : happy path — 3 slots open futurs → data contient les 3, triés ASC ──

#[tokio::test]
async fn availability_happy_path_returns_open_slots_sorted_asc() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string()).await;

    // 3 créneaux futurs, insérés dans le désordre pour vérifier le tri ASC
    sqlx::query(
        "INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, status) VALUES \
         ($1, $2, now() + interval '3 days', now() + interval '3 days 30 minutes', 'open'), \
         ($3, $2, now() + interval '1 day',  now() + interval '1 day 30 minutes',  'open'), \
         ($4, $2, now() + interval '2 days', now() + interval '2 days 30 minutes', 'open')",
    )
    .bind(Uuid::new_v4())
    .bind(provider_id)
    .bind(Uuid::new_v4())
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
                .uri(format!("/v1/providers/{}/availability", provider_id))
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

    assert_eq!(data.len(), 3, "3 slots open futurs attendus");
    // Vérifie le tri ASC par starts_at
    let t0 = data[0]["starts_at"].as_str().unwrap();
    let t1 = data[1]["starts_at"].as_str().unwrap();
    let t2 = data[2]["starts_at"].as_str().unwrap();
    assert!(t0 < t1, "slot 0 doit précéder slot 1 (tri ASC)");
    assert!(t1 < t2, "slot 1 doit précéder slot 2 (tri ASC)");
    // Vérifie la structure d'un item
    assert!(data[0]["slot_id"].is_string());
    assert!(data[0]["starts_at"].is_string());
    assert!(data[0]["ends_at"].is_string());

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

// ── Test 2 : empty path — provider sans slot open futur → data:[] ────────────

#[tokio::test]
async fn availability_empty_path_returns_empty_data() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string()).await;

    // Pas de slots insérés pour ce provider

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/providers/{}/availability", provider_id))
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

    assert_eq!(v["data"], serde_json::json!([]), "data doit être vide");

    // Nettoyage
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
}
