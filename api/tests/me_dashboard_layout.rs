//! Tests d'intégration : GET/PUT /v1/me/dashboard-layout (#7162)

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

const JWT_SECRET: &str = "test-jwt-secret-me-dashboard-layout";

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

fn make_jwt(user_id: Uuid, kind: &str, role: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": kind, "role": role, "exp": exp}),
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

async fn insert_app_user(db: &PgPool, user_id: Uuid, kind: &str) {
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
    )
    .bind(user_id)
    .bind(format!("me-dashboard-layout+{}@nubia.test", user_id))
    .bind(kind)
    .execute(db)
    .await
    .unwrap();
}

// ── Test 1 : pas de ligne → 200 + défauts dépendant du rôle ──────────────────

#[tokio::test]
async fn no_row_returns_role_defaults() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let user_id = Uuid::new_v4();
    insert_app_user(&owner_db, user_id, "pro").await;

    let token = make_jwt(user_id, "pro", "secretary");

    let response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/dashboard-layout")
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

    let widgets = json["widgets"].as_array().unwrap();
    assert!(widgets.iter().any(|w| w == "today_schedule"));
    assert!(!widgets.iter().any(|w| w == "kpi_tiles"));
}

// ── Test 2 : PUT persiste, re-GET confirme (round-trip) ──────────────────────

#[tokio::test]
async fn put_persists_and_get_reflects_it() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let user_id = Uuid::new_v4();
    insert_app_user(&owner_db, user_id, "pro").await;

    let token = make_jwt(user_id, "pro", "practitioner");

    let put_response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/me/dashboard-layout")
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"widgets": ["today_notes", "kpi_tiles"]}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(put_response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(put_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(json["widgets"], json!(["today_notes", "kpi_tiles"]));

    let get_response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/dashboard-layout")
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
    assert_eq!(json["widgets"], json!(["today_notes", "kpi_tiles"]));
}

// ── Test 3 : identifiant de widget inconnu → 422 ─────────────────────────────

#[tokio::test]
async fn unknown_widget_id_rejected() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let user_id = Uuid::new_v4();
    insert_app_user(&owner_db, user_id, "pro").await;

    let token = make_jwt(user_id, "pro", "practitioner");

    let response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/me/dashboard-layout")
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(json!({"widgets": ["not_a_widget"]}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 4 : widget dupliqué → 422 ───────────────────────────────────────────

#[tokio::test]
async fn duplicate_widget_id_rejected() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let user_id = Uuid::new_v4();
    insert_app_user(&owner_db, user_id, "pro").await;

    let token = make_jwt(user_id, "pro", "practitioner");

    let response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/me/dashboard-layout")
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"widgets": ["kpi_tiles", "kpi_tiles"]}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 5 : pas de JWT → 401 ─────────────────────────────────────────────────

#[tokio::test]
async fn no_auth_returns_401() {
    if !db_available() {
        return;
    }
    let response = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/dashboard-layout")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 6 : isolation par user ───────────────────────────────────────────────

#[tokio::test]
async fn layout_is_isolated_per_user() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let user_a = Uuid::new_v4();
    let user_b = Uuid::new_v4();
    insert_app_user(&owner_db, user_a, "pro").await;
    insert_app_user(&owner_db, user_b, "pro").await;

    let token_a = make_jwt(user_a, "pro", "practitioner");
    let token_b = make_jwt(user_b, "pro", "practitioner");

    app(make_state().await)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/me/dashboard-layout")
                .header("Authorization", format!("Bearer {}", token_a))
                .header("content-type", "application/json")
                .body(Body::from(json!({"widgets": ["week_summary"]}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    let response_b = app(make_state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/dashboard-layout")
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
    assert!(!json["widgets"]
        .as_array()
        .unwrap()
        .iter()
        .any(|w| w == "week_summary"));
}
