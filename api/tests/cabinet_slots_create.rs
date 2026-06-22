//! Tests d'intégration : POST /v1/cabinet/slots

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-slots-create";

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

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600
}

fn make_pro_jwt(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": role,
            "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère cabinet + app_user + practitioner + provider. Retourne (cabinet_id, user_id, provider_id).
async fn insert_fixture(db: &PgPool, tag: &str) -> (Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Slots Create {}", tag))
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("csc-{}@nubia.test", tag))
    .execute(db)
    .await
    .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, $5, false, false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(user_id)
    .bind(format!("Dr CSC {}", tag))
    .execute(db)
    .await
    .unwrap();

    (cabinet_id, user_id, provider_id)
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, user_id: Uuid) {
    sqlx::query("DELETE FROM availability_slot WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
}

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    }
}

// ── Test 1 : admin crée un créneau → 201 ─────────────────────────────────────

#[tokio::test]
async fn post_cabinet_slot_admin_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let tag = Uuid::new_v4().to_string();
    let (cabinet_id, user_id, provider_id) = insert_fixture(&db, &tag).await;

    let token = make_pro_jwt(user_id, cabinet_id, "admin");
    let body = json!({
        "starts_at": "2030-01-10T09:00:00Z",
        "ends_at":   "2030-01-10T09:30:00Z",
        "provider_id": provider_id,
        "capacity": 1
    });

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["id"].is_string());
    assert_eq!(v["status"], "available");
    assert_eq!(v["capacity"], 1);

    cleanup(&db, cabinet_id, user_id).await;
}

// ── Test 2 : secrétariat crée un créneau → 201 ───────────────────────────────

#[tokio::test]
async fn post_cabinet_slot_secretary_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let tag = Uuid::new_v4().to_string();
    let (cabinet_id, user_id, provider_id) = insert_fixture(&db, &tag).await;

    let token = make_pro_jwt(user_id, cabinet_id, "secretary");
    let body = json!({
        "starts_at": "2030-02-10T09:00:00Z",
        "ends_at":   "2030-02-10T09:30:00Z",
        "provider_id": provider_id
    });

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["id"].is_string());
    assert_eq!(v["status"], "available");

    cleanup(&db, cabinet_id, user_id).await;
}

// ── Test 3 : practitioner → 403 ──────────────────────────────────────────────

#[tokio::test]
async fn post_cabinet_slot_practitioner_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let tag = Uuid::new_v4().to_string();
    let (cabinet_id, user_id, provider_id) = insert_fixture(&db, &tag).await;

    let token = make_pro_jwt(user_id, cabinet_id, "practitioner");
    let body = json!({
        "starts_at": "2030-03-10T09:00:00Z",
        "ends_at":   "2030-03-10T09:30:00Z",
        "provider_id": provider_id
    });

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup(&db, cabinet_id, user_id).await;
}

// ── Test 4 : conflit EXCLUDE (23P01) → 409 slot_taken ────────────────────────

#[tokio::test]
async fn post_cabinet_slot_overlap_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let tag = Uuid::new_v4().to_string();
    let (cabinet_id, user_id, provider_id) = insert_fixture(&db, &tag).await;

    // Récupère practitioner_id pour pouvoir insérer un premier créneau directement.
    let row = sqlx::query("SELECT id FROM practitioner WHERE cabinet_id = $1 LIMIT 1")
        .bind(cabinet_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let prac_id: Uuid = sqlx::Row::try_get(&row, "id").unwrap();

    // Insère un premier créneau via nubia_owner (contourne RLS).
    sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status, online_booking) \
         VALUES ($1, $2, $3, $4, '2030-04-10T09:00:00Z', '2030-04-10T09:30:00Z', 'open', false)",
    )
    .bind(Uuid::new_v4())
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .execute(&db)
    .await
    .unwrap();

    // Deuxième créneau identique → 23P01 → 409.
    let token = make_pro_jwt(user_id, cabinet_id, "admin");
    let body = json!({
        "starts_at": "2030-04-10T09:00:00Z",
        "ends_at":   "2030-04-10T09:30:00Z",
        "provider_id": provider_id
    });

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CONFLICT);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "slot_taken");

    cleanup(&db, cabinet_id, user_id).await;
}
