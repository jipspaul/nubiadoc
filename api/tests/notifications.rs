//! Tests d'intégration : GET /v1/notifications

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

const JWT_SECRET: &str = "test-jwt-secret-notifications";

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
        &json!({"sub": user_id, "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère une notification via nubia_app (RLS : current_user_id = app_user_id).
async fn insert_notification(
    app_db: &PgPool,
    user_id: Uuid,
    kind: &str,
    title: &str,
    is_read: bool,
) -> Uuid {
    let id = Uuid::new_v4();
    let mut tx = app_db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO notification \
         (id, app_user_id, kind, title, body_ciphertext, body_key_ref, is_read) \
         VALUES ($1, $2, $3, $4, '\\x00'::bytea, 'stub', $5)",
    )
    .bind(id)
    .bind(user_id)
    .bind(kind)
    .bind(title)
    .bind(is_read)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    id
}

// ── Test 1 : liste basique → 200 + données ────────────────────────────────────

#[tokio::test]
async fn notifications_list_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let app_db = app_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("notif-list+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    insert_notification(&app_db, user_id, "rdv", "Votre RDV", false).await;
    insert_notification(&app_db, user_id, "message", "Nouveau message", true).await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/notifications")
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
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
    assert!(v["data"].is_array());
    assert_eq!(v["data"].as_array().unwrap().len(), 2);
    assert!(v["page"]["next_cursor"].is_null());

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : ?unread_only=true → filtre les lues ──────────────────────────────

#[tokio::test]
async fn notifications_unread_only_returns_only_unread() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let app_db = app_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("notif-unread+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    insert_notification(&app_db, user_id, "rdv", "RDV non lu", false).await;
    insert_notification(&app_db, user_id, "rdv", "RDV lu", true).await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/notifications?unread_only=true")
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
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
    let data = v["data"].as_array().unwrap();
    assert_eq!(data.len(), 1);
    assert_eq!(data[0]["is_read"], false);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn notifications_no_jwt_returns_401() {
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

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/notifications")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 4 : pagination cursor → next_cursor puis page 2 ─────────────────────

#[tokio::test]
async fn notifications_pagination_cursor() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let app_db = app_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("notif-pag+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    // Insert 3 notifications avec des created_at distincts.
    for i in 0u32..3 {
        let id = Uuid::new_v4();
        let mut tx = app_pool().await.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(user_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO notification \
             (id, app_user_id, kind, title, body_ciphertext, body_key_ref, \
              created_at) \
             VALUES ($1, $2, 'rdv', $3, '\\x00'::bytea, 'stub', \
                     now() - ($4 * interval '1 second'))",
        )
        .bind(id)
        .bind(user_id)
        .bind(format!("Notif {i}"))
        .bind(i as i64)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Page 1 : limit=2
    let resp1 = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/notifications?limit=2")
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp1.status(), StatusCode::OK);
    let body1 = axum::body::to_bytes(resp1.into_body(), usize::MAX)
        .await
        .unwrap();
    let v1: serde_json::Value = serde_json::from_slice(&body1).unwrap();
    assert_eq!(v1["data"].as_array().unwrap().len(), 2);
    let cursor = v1["page"]["next_cursor"].as_str().unwrap().to_string();

    // Page 2 : use cursor
    let app_db2 = app_pool().await;
    let state2 = AppState {
        db: app_db2,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Le curseur contient uniquement des chiffres, un `|` et un UUID : sûr en query string.
    let resp2 = app(state2)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/notifications?limit=2&cursor={cursor}"))
                .header("Authorization", format!("Bearer {}", make_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp2.status(), StatusCode::OK);
    let body2 = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&body2).unwrap();
    assert_eq!(v2["data"].as_array().unwrap().len(), 1);
    assert!(v2["page"]["next_cursor"].is_null());

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}
