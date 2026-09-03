//! Tests d'intégration : GET/PATCH /v1/me/notification-preferences (#6257, #6265)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-me-notif-prefs";

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

fn make_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pharma", "pharmacy_id": Uuid::new_v4(),
                "role": "pharmacist", "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn make_state() -> AppState {
    AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn insert_app_user(db: &PgPool, user_id: Uuid) {
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("me-notif-prefs+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();
}

// ── Test 1 : pas de ligne → 200 + défauts (in-app true, email false) ────────

#[tokio::test]
async fn no_row_returns_defaults() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let user_id = Uuid::new_v4();
    insert_app_user(&owner_db, user_id).await;

    let router = app(make_state().await);
    let token = make_jwt(user_id);

    let response = router
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/notification-preferences")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["inapp_rdv"], true);
    assert_eq!(json["inapp_messagerie"], true);
    assert_eq!(json["inapp_devis"], true);
    assert_eq!(json["inapp_stock"], true);
    assert_eq!(json["inapp_labo"], true);
    assert_eq!(json["inapp_visites"], true);
    assert_eq!(json["email_rdv"], false);
    assert_eq!(json["email_messagerie"], false);
    assert_eq!(json["email_devis"], false);
    assert_eq!(json["push_rdv"], true);
    assert_eq!(json["push_messagerie"], true);
    assert_eq!(json["push_devis"], true);
    assert_eq!(json["push_stock"], true);
    assert_eq!(json["push_labo"], true);
    assert_eq!(json["push_visites"], true);
}

// ── Test 1b (#6322) : PATCH push_* persiste au re-GET ────────────────────────

#[tokio::test]
async fn patch_push_key_persists() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let user_id = Uuid::new_v4();
    insert_app_user(&owner_db, user_id).await;

    let token = make_jwt(user_id);

    let patch_response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/me/notification-preferences")
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(json!({"push_messagerie": false}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(patch_response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(patch_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["push_messagerie"], false);
    assert_eq!(json["push_rdv"], true);

    let get_response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/notification-preferences")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(get_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["push_messagerie"], false);
    assert_eq!(json["push_rdv"], true);
}

// ── Test 2 : PATCH partiel ne touche que les clés envoyées, re-GET confirme ──

#[tokio::test]
async fn patch_partial_persists_and_leaves_other_keys_untouched() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let user_id = Uuid::new_v4();
    insert_app_user(&owner_db, user_id).await;

    let token = make_jwt(user_id);

    let patch_response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/me/notification-preferences")
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(json!({"inapp_labo": false}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(patch_response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(patch_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["inapp_labo"], false);
    assert_eq!(json["inapp_rdv"], true);

    let get_response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/notification-preferences")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(get_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["inapp_labo"], false);
    assert_eq!(json["inapp_rdv"], true);
    assert_eq!(json["inapp_messagerie"], true);
    assert_eq!(json["email_rdv"], false);
}

// ── Test 3 : clé inconnue dans le PATCH → 422 (deny_unknown_fields) ──────────

#[tokio::test]
async fn patch_unknown_key_rejected() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let user_id = Uuid::new_v4();
    insert_app_user(&owner_db, user_id).await;

    let token = make_jwt(user_id);

    let response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/me/notification-preferences")
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(json!({"inapp_prevention": false}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 4 : pas de JWT → 401 ─────────────────────────────────────────────────

#[tokio::test]
async fn no_auth_returns_401() {
    if !db_available() {
        return;
    }
    let response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/notification-preferences")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 5 : isolation par user — les prefs d'un user n'affectent pas l'autre ─

#[tokio::test]
async fn preferences_are_isolated_per_user() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let user_a = Uuid::new_v4();
    let user_b = Uuid::new_v4();
    insert_app_user(&owner_db, user_a).await;
    insert_app_user(&owner_db, user_b).await;

    let token_a = make_jwt(user_a);
    let token_b = make_jwt(user_b);

    app(make_state().await)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/me/notification-preferences")
                .header("Authorization", format!("Bearer {}", token_a))
                .header("content-type", "application/json")
                .body(Body::from(json!({"inapp_stock": false}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    let response_b = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/notification-preferences")
                .header("Authorization", format!("Bearer {}", token_b))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    let body = axum::body::to_bytes(response_b.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["inapp_stock"], true);
}
