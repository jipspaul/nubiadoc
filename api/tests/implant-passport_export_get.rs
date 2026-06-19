//! Tests d'intégration : GET /v1/implant-passport/export

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

use nubia_api::{app, app_with_dispatcher, AppState, StorageSigner, StubJobDispatcher, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-implant-passport-export";

fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "role": "admin",
                "account_id": Uuid::nil(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_app_state() -> AppState {
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

// ── Test 1 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn implant_passport_export_no_jwt_returns_401() {
    let response = app(make_app_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/implant-passport/export")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 2 : token pro → 403 ──────────────────────────────────────────────────

#[tokio::test]
async fn implant_passport_export_pro_token_returns_403() {
    let token = make_pro_jwt(Uuid::new_v4(), Uuid::new_v4());

    let response = app(make_app_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/implant-passport/export")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 3 : happy path — patient valide → 302 avec Location ─────────────────

#[tokio::test]
async fn implant_passport_export_patient_returns_302_with_location() {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let token = make_patient_jwt(user_id, account_id);

    let response = app(make_app_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/implant-passport/export")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FOUND);

    let location = response
        .headers()
        .get("location")
        .expect("header Location absent")
        .to_str()
        .unwrap();

    // Le StubStorageSigner génère une URL contenant la clé de stockage du compte.
    assert!(
        location.contains(&account_id.to_string()),
        "Location doit contenir l'account_id : {location}"
    );
}

// ── Test 4 : edge case — Cache-Control: no-store présent ─────────────────────

#[tokio::test]
async fn implant_passport_export_response_has_no_store_cache_control() {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let token = make_patient_jwt(user_id, account_id);

    let response = app(make_app_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/implant-passport/export")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FOUND);

    let cache_control = response
        .headers()
        .get("cache-control")
        .expect("header Cache-Control absent")
        .to_str()
        .unwrap();

    assert_eq!(cache_control, "no-store");
}

// ── Test 5 : signer défaillant → 410 Gone ─────────────────────────────────────

/// Signer stub qui retourne toujours `None` (simule une clé expirée / bucket inaccessible).
struct FailingSigner;

impl StorageSigner for FailingSigner {
    fn sign(&self, _storage_key: &str) -> Option<String> {
        None
    }
}

#[tokio::test]
async fn implant_passport_export_failing_signer_returns_410() {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let token = make_patient_jwt(user_id, account_id);

    let response = app_with_dispatcher(
        make_app_state(),
        Arc::new(StubJobDispatcher),
        Arc::new(FailingSigner),
    )
    .oneshot(
        Request::builder()
            .method("GET")
            .uri("/v1/implant-passport/export")
            .header("Authorization", format!("Bearer {}", token))
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();

    assert_eq!(response.status(), StatusCode::GONE);
}
