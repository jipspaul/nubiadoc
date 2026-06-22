//! Tests d'intégration : POST /v1/cabinet/slots — créer un créneau (issue #2510)
//!
//! Couvre :
//! - Admin crée un créneau → 201
//! - Secrétariat crée un créneau → 201
//! - Praticien → 403
//! - Chevauchement EXCLUDE → 409 slot_taken

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

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

fn make_token(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": role,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
    provider_id: Uuid,
}

async fn setup(db: &PgPool, prefix: &str) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("slots-create-{}-{}@nubia.test", prefix, user_id))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Slots {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, is_listed) \
         VALUES ($1, $2, $3, $4, 'Dr. Slot', false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        user_id,
        provider_id,
    }
}

async fn cleanup(db: &PgPool, user_id: Uuid) {
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : admin crée un créneau → 201 ─────────────────────────────────────

#[tokio::test]
async fn create_slot_admin_returns_201() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let f = setup(&db, "admin").await;

    let token = make_token(f.user_id, f.cabinet_id, "admin");

    let body = json!({
        "starts_at": "2030-01-10T09:00:00Z",
        "ends_at": "2030-01-10T09:30:00Z",
        "capacity": 1,
        "provider_id": f.provider_id
    });

    let resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    assert!(v["id"].as_str().is_some(), "id doit être présent");
    assert_eq!(v["capacity"], 1, "capacity doit être 1");
    assert_eq!(v["status"], "available", "status doit être available");

    cleanup(&owner_pool().await, f.user_id).await;
}

// ── Test 2 : secrétariat crée un créneau → 201 ───────────────────────────────

#[tokio::test]
async fn create_slot_secretary_returns_201() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let f = setup(&db, "secretary").await;

    let token = make_token(f.user_id, f.cabinet_id, "secretary");

    let body = json!({
        "starts_at": "2030-01-11T10:00:00Z",
        "ends_at": "2030-01-11T10:30:00Z",
        "capacity": 1,
        "provider_id": f.provider_id
    });

    let resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    assert_eq!(v["status"], "available");

    cleanup(&owner_pool().await, f.user_id).await;
}

// ── Test 3 : praticien → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn create_slot_practitioner_returns_403() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let f = setup(&db, "prac403").await;

    let token = make_token(f.user_id, f.cabinet_id, "practitioner");

    let body = json!({
        "starts_at": "2030-01-12T14:00:00Z",
        "ends_at": "2030-01-12T14:30:00Z",
        "capacity": 1,
        "provider_id": f.provider_id
    });

    let resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup(&owner_pool().await, f.user_id).await;
}

// ── Test 4 : chevauchement EXCLUDE → 409 slot_taken ──────────────────────────

#[tokio::test]
async fn create_slot_overlap_returns_409_slot_taken() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let f = setup(&db, "overlap").await;

    let token = make_token(f.user_id, f.cabinet_id, "admin");

    let body = json!({
        "starts_at": "2030-01-13T08:00:00Z",
        "ends_at": "2030-01-13T08:30:00Z",
        "capacity": 1,
        "provider_id": f.provider_id
    });

    // Premier créneau → 201
    let resp1 = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        resp1.status(),
        StatusCode::CREATED,
        "premier créneau doit réussir"
    );

    // Deuxième créneau chevauchant → 409
    let resp2 = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        resp2.status(),
        StatusCode::CONFLICT,
        "chevauchement doit retourner 409"
    );

    let bytes = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(
        v["code"], "slot_taken",
        "code d'erreur doit être slot_taken (23P01)"
    );

    cleanup(&owner_pool().await, f.user_id).await;
}
