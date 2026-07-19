//! Tests d'intégration : DELETE /v1/cabinet/slots/:id
//!
//! Couvre :
//! - 204 No Content (happy path)
//! - 409 has_booking (appointment actif référence le créneau)
//! - 404 créneau d'un autre cabinet

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-slots-delete";

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

fn make_admin_token(sub: Uuid, cabinet_id: Uuid) -> String {
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
            "role": "admin",
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
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
            "role": "practitioner",
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct SlotFixture {
    cabinet_id: Uuid,
    user_id: Uuid,
    practitioner_id: Uuid,
    slot_id: Uuid,
}

/// Crée cabinet + user + practitioner + provider + slot.
async fn insert_slot_fixture(db: &PgPool, suffix: &str) -> SlotFixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let slot_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("csd-pro-{}@nubia.test", suffix))
    .execute(db)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet CSD {}", suffix))
        .execute(db)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, true, false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(user_id)
    .bind(format!("Dr CSD {}", suffix))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, \
                 now() + interval '5 days', \
                 now() + interval '5 days 30 minutes', \
                 'open')",
    )
    .bind(slot_id)
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(practitioner_id)
    .execute(db)
    .await
    .unwrap();

    SlotFixture {
        cabinet_id,
        user_id,
        practitioner_id,
        slot_id,
    }
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, user_id: Uuid) {
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
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

// ── Test 1 : DELETE créneau libre → 204 ──────────────────────────────────────

#[tokio::test]
async fn delete_slot_happy_path_returns_204() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let f = insert_slot_fixture(&db, &suffix).await;

    let token = make_admin_token(f.user_id, f.cabinet_id);
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/cabinet/slots/{}", f.slot_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    cleanup(&db, f.cabinet_id, f.user_id).await;
}

// ── Test 1b : praticien → 403 (mêmes rôles que create_cabinet_slot, #3742) ──

#[tokio::test]
async fn delete_slot_practitioner_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let f = insert_slot_fixture(&db, &suffix).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/cabinet/slots/{}", f.slot_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        resp.status(),
        StatusCode::FORBIDDEN,
        "un praticien ne doit pas pouvoir supprimer un créneau (secretary/admin uniquement)"
    );

    cleanup(&db, f.cabinet_id, f.user_id).await;
}

// ── Test 2 : DELETE créneau avec RDV actif → 409 has_booking ─────────────────

#[tokio::test]
async fn delete_slot_with_booking_returns_409_has_booking() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let f = insert_slot_fixture(&db, &suffix).await;

    // Insère un patient et un RDV confirmé référençant le créneau.
    let patient_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES ($1, $2, 'Alice', 'Test')",
    )
    .bind(patient_id)
    .bind(f.cabinet_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, slot_id) \
         VALUES ($1, $2, $3, $4, \
                 now() + interval '5 days', \
                 now() + interval '5 days 30 minutes', \
                 'confirmed', $5)",
    )
    .bind(Uuid::new_v4())
    .bind(f.cabinet_id)
    .bind(patient_id)
    .bind(f.practitioner_id)
    .bind(f.slot_id)
    .execute(&db)
    .await
    .unwrap();

    let token = make_admin_token(f.user_id, f.cabinet_id);
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/cabinet/slots/{}", f.slot_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CONFLICT);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "has_booking");

    cleanup(&db, f.cabinet_id, f.user_id).await;
}

// ── Test 3 : DELETE créneau d'un autre cabinet → 404 ─────────────────────────

#[tokio::test]
async fn delete_slot_other_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let f = insert_slot_fixture(&db, &suffix).await;

    // JWT d'un cabinet différent
    let other_cabinet_id = Uuid::new_v4();
    let token = make_admin_token(f.user_id, other_cabinet_id);
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/cabinet/slots/{}", f.slot_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup(&db, f.cabinet_id, f.user_id).await;
}
