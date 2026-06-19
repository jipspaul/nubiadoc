//! Tests d'intégration : POST /v1/auth/mfa/enroll

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

const JWT_SECRET: &str = "test-jwt-secret-for-mfa-enroll";

fn make_pro_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let claims = json!({"sub": user_id, "kind": "pro", "exp": exp});
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_patient_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let claims =
        json!({"sub": user_id, "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp});
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn test_state() -> nubia_api::AppState {
    // mfa_enroll ne touche pas la DB ; pool lazy pour éviter un Postgres réel.
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    nubia_api::AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: std::sync::Arc::new(nubia_api::StubMailer),
    }
}

// ── Test 1 : JWT pro valide → 200 + totp_secret + otpauth_url ─────────────

#[tokio::test]
async fn mfa_enroll_pro_jwt_returns_200() {
    let user_id = Uuid::new_v4();
    let response = nubia_api::app(test_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/enroll")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
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

    let secret = json["totp_secret"].as_str().unwrap();
    assert!(!secret.is_empty());
    let url = json["otpauth_url"].as_str().unwrap();
    assert!(url.starts_with("otpauth://totp/"));
    assert!(url.contains(secret));
}

// ── Test 2 : JWT absent → 401 ─────────────────────────────────────────────

#[tokio::test]
async fn mfa_enroll_no_jwt_returns_401() {
    let response = nubia_api::app(test_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/enroll")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 3 : JWT expiré → 401 ─────────────────────────────────────────────
// Valide que `validate_exp = true` est bien actif dans ProClaims.

#[tokio::test]
async fn mfa_enroll_expired_jwt_returns_401() {
    let user_id = Uuid::new_v4();
    // exp dans le passé (il y a 1 seconde)
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        - 1;
    let claims = serde_json::json!({"sub": user_id, "kind": "pro", "exp": exp});
    let token = jsonwebtoken::encode(
        &jsonwebtoken::Header::default(),
        &claims,
        &jsonwebtoken::EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let response = nubia_api::app(test_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/enroll")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 4 : JWT patient → 403 ────────────────────────────────────────────

#[tokio::test]
async fn mfa_enroll_patient_jwt_returns_403() {
    let user_id = Uuid::new_v4();
    let response = nubia_api::app(test_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/enroll")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}
