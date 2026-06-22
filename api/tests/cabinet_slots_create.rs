//! Tests d'intégration : POST /v1/cabinet/slots — créer un créneau (admin/secrétariat, issue #2510)

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

fn make_admin_token(cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": Uuid::new_v4(), "kind": "pro",
            "cabinet_id": cabinet_id, "role": "admin", "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_secretary_token(cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": Uuid::new_v4(), "kind": "pro",
            "cabinet_id": cabinet_id, "role": "secretary", "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_practitioner_token(cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": Uuid::new_v4(), "kind": "pro",
            "cabinet_id": cabinet_id, "role": "practitioner", "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    provider_id: Uuid,
    prac_id: Uuid,
    user_id: Uuid,
}

async fn setup(db: &PgPool, label: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("slots-{}-{}@nubia.test", label, user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Slots {} {}", label, cabinet_id))
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
        "INSERT INTO provider \
         (id, cabinet_id, practitioner_id, user_id, display_name, is_listed) \
         VALUES ($1, $2, $3, $4, 'Dr Test', false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        provider_id,
        prac_id,
        user_id,
    }
}

async fn teardown(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM availability_slot WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(f.provider_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(f.prac_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : admin crée un créneau → 201 ────────────────────────────────────

#[tokio::test]
async fn create_slot_admin_returns_201() {
    if !db_available() {
        return;
    }

    let db = owner_pool().await;
    let f = setup(&db, "admin201").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_admin_token(f.cabinet_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "starts_at":   "2031-06-01T09:00:00Z",
                        "ends_at":     "2031-06-01T10:00:00Z",
                        "capacity":    1,
                        "provider_id": f.provider_id
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["id"].is_string(), "id attendu");
    assert_eq!(v["status"], "available");
    assert_eq!(v["capacity"], 1);

    teardown(&db, &f).await;
}

// ── Test 2 : secrétariat crée un créneau → 201 ───────────────────────────────

#[tokio::test]
async fn create_slot_secretary_returns_201() {
    if !db_available() {
        return;
    }

    let db = owner_pool().await;
    let f = setup(&db, "sec201").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_secretary_token(f.cabinet_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "starts_at":   "2031-07-01T09:00:00Z",
                        "ends_at":     "2031-07-01T10:00:00Z",
                        "capacity":    2,
                        "provider_id": f.provider_id
                    })
                    .to_string(),
                ))
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
    assert_eq!(v["capacity"], 2);

    teardown(&db, &f).await;
}

// ── Test 3 : praticien → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn create_slot_practitioner_returns_403() {
    if !db_available() {
        return;
    }

    let db = owner_pool().await;
    let f = setup(&db, "prac403").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_practitioner_token(f.cabinet_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "starts_at":   "2031-08-01T09:00:00Z",
                        "ends_at":     "2031-08-01T10:00:00Z",
                        "capacity":    1,
                        "provider_id": f.provider_id
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    teardown(&db, &f).await;
}

// ── Test 4 : chevauchement EXCLUDE → 409 slot_taken ──────────────────────────

#[tokio::test]
async fn create_slot_overlap_returns_409() {
    if !db_available() {
        return;
    }

    let db = owner_pool().await;
    let f = setup(&db, "excl409").await;

    // Premier créneau inséré directement (nubia_owner bypasse RLS).
    sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status, online_booking) \
         VALUES ($1, $2, $3, $4, '2031-09-01T09:00:00Z', '2031-09-01T10:00:00Z', 'open', false)",
    )
    .bind(Uuid::new_v4())
    .bind(f.provider_id)
    .bind(f.cabinet_id)
    .bind(f.prac_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Créneau chevauchant (09:30 → 10:30) → 409 slot_taken.
    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_admin_token(f.cabinet_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "starts_at":   "2031-09-01T09:30:00Z",
                        "ends_at":     "2031-09-01T10:30:00Z",
                        "capacity":    1,
                        "provider_id": f.provider_id
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CONFLICT);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "slot_taken");

    teardown(&db, &f).await;
}
