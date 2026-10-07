//! Tests d'intégration : PATCH /v1/me (#6850 — nom affichable des pros
//! non-praticiens, ex. secrétariat, utilisé par `cabinet_team_messages.rs`).

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

const JWT_SECRET: &str = "test-jwt-secret-me-patch";

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

fn make_pro_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
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

// ── Test 1 : PATCH first_name/last_name (secrétaire sans nom) → 200 + display_name,
//    puis GET /v1/me reflète la mise à jour ──────────────────────────────────

#[tokio::test]
async fn me_patch_sets_display_name_for_pro_without_name() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("me-patch+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let jwt = make_pro_jwt(user_id);

    let patch_resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/me")
                .header("Authorization", format!("Bearer {}", jwt))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_vec(&json!({"first_name": "Sonia", "last_name": "Petit"}))
                        .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(patch_resp.status(), StatusCode::OK);
    let body = axum::body::to_bytes(patch_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["display_name"], "Sonia Petit");
    assert_eq!(v["user_id"], user_id.to_string());

    let get_resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me")
                .header("Authorization", format!("Bearer {}", jwt))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_resp.status(), StatusCode::OK);
    let body = axum::body::to_bytes(get_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["display_name"], "Sonia Petit");

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : PATCH partiel (uniquement last_name) → first_name déjà connu
//    conservé (COALESCE) ───────────────────────────────────────────────────

#[tokio::test]
async fn me_patch_partial_update_keeps_existing_field() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind, first_name) \
         VALUES ($1, $2, 'hash', 'pro', 'Sonia')",
    )
    .bind(user_id)
    .bind(format!("me-patch-partial+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let jwt = make_pro_jwt(user_id);

    let patch_resp = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/me")
                .header("Authorization", format!("Bearer {}", jwt))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_vec(&json!({"last_name": "Petit"})).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(patch_resp.status(), StatusCode::OK);
    let body = axum::body::to_bytes(patch_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["display_name"], "Sonia Petit");

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3 : first_name vide/blanc → 422 ──────────────────────────────────────

#[tokio::test]
async fn me_patch_blank_first_name_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("me-patch-blank+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let jwt = make_pro_jwt(user_id);

    let patch_resp = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/me")
                .header("Authorization", format!("Bearer {}", jwt))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_vec(&json!({"first_name": "   "})).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(patch_resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 4 : token patient (pas pro) → 403 ────────────────────────────────────

#[tokio::test]
async fn me_patch_patient_jwt_returns_403() {
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
    .bind(format!("me-patch-patient+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let patch_resp = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/me")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_vec(&json!({"first_name": "Bob"})).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(patch_resp.status(), StatusCode::FORBIDDEN);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}
