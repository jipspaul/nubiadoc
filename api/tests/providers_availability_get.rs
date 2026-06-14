//! Tests d'intégration : GET /v1/providers/:id/availability
//!
//! Couvre les cas HTTP / navigation de la route.
//! Les cas de filtrage métier (slots held/booked, tri ASC) sont dans
//! `marketplace_availability.rs`.

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

/// Insère un provider avec `is_listed` configurable. Retourne le provider_id.
async fn insert_provider(db: &PgPool, suffix: &str, is_listed: bool) -> Uuid {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Avail Get Test {}", suffix))
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("avail-get-{}@nubia.test", suffix))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, true, $5)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(user_id)
    .bind(format!("Dr Avail Get {}", suffix))
    .bind(is_listed)
    .execute(db)
    .await
    .unwrap();

    provider_id
}

async fn cleanup_provider(db: &PgPool, provider_id: Uuid) {
    sqlx::query("DELETE FROM availability_slot WHERE provider_id = $1")
        .bind(provider_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : happy path — provider listé + slot open → 200 + body conforme ───

#[tokio::test]
async fn availability_get_happy_path_returns_200_with_slots() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string(), true).await;

    // 1 créneau ouvert dans le futur
    let slot_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, status) \
         VALUES ($1, $2, now() + interval '1 day', now() + interval '1 day 30 minutes', 'open')",
    )
    .bind(slot_id)
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

    assert_eq!(data.len(), 1, "1 slot open futur attendu");
    assert_eq!(
        data[0]["slot_id"].as_str().unwrap(),
        slot_id.to_string(),
        "slot_id doit correspondre"
    );
    assert!(
        data[0]["starts_at"].is_string(),
        "starts_at doit être présent"
    );
    assert!(data[0]["ends_at"].is_string(), "ends_at doit être présent");

    cleanup_provider(&db, provider_id).await;
}

// ── Test 2 : provider inexistant → 404 ───────────────────────────────────────

#[tokio::test]
async fn availability_get_unknown_provider_returns_404() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let random_id = Uuid::new_v4();

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/providers/{}/availability", random_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "provider inexistant → 404"
    );
}

// ── Test 3 : provider non listé → 404 (masquage d'existence) ─────────────────

#[tokio::test]
async fn availability_get_unlisted_provider_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string(), false).await;

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

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "provider is_listed=false → 404 (masquage d'existence)"
    );

    cleanup_provider(&db, provider_id).await;
}

// ── Test 4 : UUID mal formé → 400 / 422 (rejet avant handler) ────────────────

#[tokio::test]
async fn availability_get_invalid_uuid_returns_error() {
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
                .uri("/v1/providers/not-a-uuid/availability")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Axum rejette le path param UUID invalide avec 400 ou 422
    let status = response.status().as_u16();
    assert!(
        status == 400 || status == 422,
        "UUID invalide → 400 ou 422, got {}",
        status
    );
}

// ── Test 5 (edge) : route publique — sans JWT → 200 pour provider listé ───────

#[tokio::test]
async fn availability_get_no_jwt_is_public_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string(), true).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    // Aucun header Authorization — route publique, pas de JWT requis
    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/providers/{}/availability", provider_id))
                // pas de header Authorization
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::OK,
        "route publique → 200 sans JWT"
    );

    cleanup_provider(&db, provider_id).await;
}
