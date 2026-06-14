//! Tests d'intégration : GET /v1/providers/:id

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
        .bind(format!("Cabinet Get Test {}", suffix))
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("get-pro-{}@nubia.test", suffix))
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
    .bind(format!("Dr Get {}", suffix))
    .bind(is_listed)
    .execute(db)
    .await
    .unwrap();

    provider_id
}

async fn cleanup_provider(db: &PgPool, provider_id: Uuid) {
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : happy path — provider listé → 200 + body conforme ───────────────

#[tokio::test]
async fn get_provider_happy_path_returns_200_with_profile() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let provider_id = insert_provider(&db, &suffix, true).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/providers/{}", provider_id))
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
        v["provider_id"].as_str().unwrap(),
        provider_id.to_string(),
        "provider_id doit correspondre"
    );
    assert_eq!(
        v["display_name"].as_str().unwrap(),
        format!("Dr Get {}", suffix)
    );
    assert!(v["rpps_verified"].as_bool().unwrap(), "rpps_verified=true");
    assert!(v["is_listed"].as_bool().unwrap(), "is_listed=true");
    assert!(v["review_count"].is_number(), "review_count doit être présent");

    cleanup_provider(&db, provider_id).await;
}

// ── Test 2 : provider inexistant → 404 ───────────────────────────────────────

#[tokio::test]
async fn get_provider_unknown_id_returns_404() {
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
                .uri(format!("/v1/providers/{}", random_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "ID inexistant → 404"
    );
}

// ── Test 3 : provider non listé → 404 (masquage d'existence) ─────────────────

#[tokio::test]
async fn get_provider_unlisted_returns_404() {
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
                .uri(format!("/v1/providers/{}", provider_id))
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
async fn get_provider_invalid_uuid_returns_error() {
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
                .uri("/v1/providers/not-a-uuid")
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
async fn get_provider_no_jwt_is_public_returns_200() {
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

    // Aucun header Authorization — la route doit rester accessible
    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/providers/{}", provider_id))
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
