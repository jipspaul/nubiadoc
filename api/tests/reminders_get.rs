//! Tests d'intégration : GET /v1/reminders

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

const JWT_SECRET: &str = "test-jwt-secret-reminders";

fn make_patient_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_pro_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": Uuid::new_v4(), "role": "admin",
                "account_id": Uuid::nil(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn lazy_state() -> AppState {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

// ── Test 1 : happy path → 200 + data contient ≥1 rappel ──────────────────────

#[tokio::test]
async fn reminders_list_returns_200_with_data() {
    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(Uuid::new_v4())),
                )
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
        v["data"].is_array(),
        "la réponse doit contenir un champ data tableau"
    );
    assert!(
        !v["data"].as_array().unwrap().is_empty(),
        "data ne doit pas être vide (rappels mockés attendus)"
    );
}

// ── Test 2 : structure des items → champs obligatoires présents ───────────────

#[tokio::test]
async fn reminders_items_have_required_fields() {
    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(Uuid::new_v4())),
                )
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

    for item in v["data"].as_array().unwrap() {
        assert!(item["id"].is_string(), "id doit être une string");
        assert!(item["type"].is_string(), "type doit être une string");
        assert!(item["title"].is_string(), "title doit être une string");
        assert!(item["due_at"].is_string(), "due_at doit être une string");
        assert!(item["status"].is_string(), "status doit être une string");
    }
}

// ── Test 3 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn reminders_no_jwt_returns_401() {
    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 4 : token pro → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn reminders_pro_token_returns_403() {
    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(Uuid::new_v4())),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 5 : token expiré → 401 ──────────────────────────────────────────────

#[tokio::test]
async fn reminders_expired_jwt_returns_401() {
    let exp_past: u64 = 1_000_000; // timestamp passé
    let expired_token = encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp_past}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header("Authorization", format!("Bearer {}", expired_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
