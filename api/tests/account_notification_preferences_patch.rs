//! Tests d'intégration : PATCH /v1/account/notification-preferences

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

const JWT_SECRET: &str = "test-jwt-secret-notif-prefs-patch";

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

// ── Test 1 : PATCH { sms_rdv: false } → 200, seul sms_rdv change ─────────────

#[tokio::test]
async fn patch_notification_preferences_partial_updates_only_given_fields() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("notif-patch+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Patch')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(user_id, account_id);

    // PATCH avec un seul champ
    let router = app(state.clone());
    let response = router
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/account/notification-preferences")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(r#"{"sms_rdv": false}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let patch_json: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(patch_json["sms_rdv"], false, "sms_rdv doit être false");
    assert_eq!(patch_json["email_rdv"], true, "email_rdv doit rester true");
    assert_eq!(patch_json["push_rdv"], true);
    assert_eq!(patch_json["email_messagerie"], true);
    assert_eq!(patch_json["push_messagerie"], true);
    assert_eq!(patch_json["email_rappels"], true);
    assert_eq!(patch_json["push_rappels"], true);

    // GET vérifie que la valeur est bien persistée
    let router2 = app(state);
    let get_response = router2
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/notification-preferences")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_response.status(), StatusCode::OK);

    let get_body = axum::body::to_bytes(get_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let get_json: serde_json::Value = serde_json::from_slice(&get_body).unwrap();

    assert_eq!(get_json["sms_rdv"], false);
    assert_eq!(get_json["email_rdv"], true);
}

// ── Test 2 : pas de JWT → 401 ─────────────────────────────────────────────────

#[tokio::test]
async fn patch_notification_preferences_no_auth_returns_401() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let router = app(state);

    let response = router
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/account/notification-preferences")
                .header("Content-Type", "application/json")
                .body(Body::from(r#"{"sms_rdv": false}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 3 : token pro → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn patch_notification_preferences_pro_token_returns_403() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let pro_token = encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "pro", "cabinet_id": Uuid::new_v4(),
                "role": "admin", "account_id": Uuid::nil(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/account/notification-preferences")
                .header("Authorization", format!("Bearer {}", pro_token))
                .header("Content-Type", "application/json")
                .body(Body::from(r#"{"sms_rdv": false}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}
