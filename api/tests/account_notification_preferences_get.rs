//! Tests d'intégration : GET /v1/account/notification-preferences

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

const JWT_SECRET: &str = "test-jwt-secret-notif-prefs";

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

// ── Test 1 : patient sans préférence → 200 + tous les champs true ────────────

#[tokio::test]
async fn notification_preferences_no_row_returns_all_defaults_true() {
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
    .bind(format!("notif-prefs+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Notif')",
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
    let router = app(state);

    let token = make_patient_jwt(user_id, account_id);
    let response = router
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

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["email_rdv"], true);
    assert_eq!(json["sms_rdv"], true);
    assert_eq!(json["push_rdv"], true);
    assert_eq!(json["email_messagerie"], true);
    assert_eq!(json["push_messagerie"], true);
    assert_eq!(json["email_rappels"], true);
    assert_eq!(json["push_rappels"], true);
}

// ── Test 2 : patient avec une ligne → 200 + valeurs stockées ─────────────────

#[tokio::test]
async fn notification_preferences_with_row_returns_stored_values() {
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
    .bind(format!("notif-prefs-row+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Notif')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    // notification_preference has FORCE ROW LEVEL SECURITY (policy TO nubia_app only).
    // Insert via nubia_app pool with app.patient_account_id GUC set in a transaction.
    {
        let seed_db = app_pool().await;
        let mut tx = seed_db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
            .bind(account_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO notification_preference \
             (patient_account_id, email_rdv, sms_rdv, push_rdv, \
              email_messagerie, push_messagerie, email_rappels, push_rappels) \
             VALUES ($1, false, true, false, true, false, true, false)",
        )
        .bind(account_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let router = app(state);

    let token = make_patient_jwt(user_id, account_id);
    let response = router
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

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(json["email_rdv"], false);
    assert_eq!(json["sms_rdv"], true);
    assert_eq!(json["push_rdv"], false);
    assert_eq!(json["email_messagerie"], true);
    assert_eq!(json["push_messagerie"], false);
    assert_eq!(json["email_rappels"], true);
    assert_eq!(json["push_rappels"], false);
}

// ── Test 3 : pas de JWT → 401 ─────────────────────────────────────────────────

#[tokio::test]
async fn notification_preferences_no_auth_returns_401() {
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
                .method("GET")
                .uri("/v1/account/notification-preferences")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
