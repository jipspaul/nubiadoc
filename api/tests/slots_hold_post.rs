//! Tests d'intégration : POST /v1/slots/:id/hold

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

const JWT_SECRET: &str = "test-jwt-secret-slots-hold-post";

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

/// Forge un JWT patient valide.
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

/// Forge un JWT pro (kind="pro") — ne doit pas être accepté par hold_slot.
fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "role": "admin", "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── Helpers de fixture ────────────────────────────────────────────────────────

/// Insère un patient (app_user + patient_account). Retourne (user_id, account_id).
async fn insert_patient(db: &PgPool, suffix: &str) -> (Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("shp-patient-{}@nubia.test", suffix))
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'SHP')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
    (user_id, account_id)
}

/// Insère un provider listé + un slot open. Retourne (provider_id, slot_id).
async fn insert_provider_with_open_slot(db: &PgPool, suffix: &str) -> (Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let slot_id = Uuid::new_v4();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet SHP {}", suffix))
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("shp-pro-{}@nubia.test", suffix))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(user_id)
    .bind(format!("Dr SHP {}", suffix))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, status) \
         VALUES ($1, $2, now() + interval '1 day', now() + interval '1 day 30 minutes', 'open')",
    )
    .bind(slot_id)
    .bind(provider_id)
    .execute(db)
    .await
    .unwrap();

    (provider_id, slot_id)
}

// ── Test 1 : happy path — slot open + patient JWT valide → 200 + hold_token ──

#[tokio::test]
async fn hold_slot_happy_path_returns_200_and_token() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let (_, slot_id) = insert_provider_with_open_slot(&db, &suffix).await;
    let (user_id, account_id) = insert_patient(&db, &suffix).await;

    let token = make_patient_jwt(user_id, account_id);
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/slots/{}/hold", slot_id))
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
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert!(v["hold_token"].is_string(), "hold_token doit être présent");
    assert!(
        !v["hold_token"].as_str().unwrap().is_empty(),
        "hold_token ne doit pas être vide"
    );
    assert!(v["expires_at"].is_string(), "expires_at doit être présent");

    // Vérifie que le slot est passé en 'held' en DB.
    let row = sqlx::query("SELECT status FROM availability_slot WHERE id = $1")
        .bind(slot_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let status: String = sqlx::Row::try_get(&row, "status").unwrap();
    assert_eq!(
        status, "held",
        "le slot doit être en statut 'held' après hold"
    );

    // Nettoyage
    sqlx::query("DELETE FROM slot_holds WHERE slot_id = $1")
        .bind(slot_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM availability_slot WHERE id = $1")
        .bind(slot_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : pas de JWT → 401 ─────────────────────────────────────────────────

#[tokio::test]
async fn hold_slot_no_auth_returns_401() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let (_, slot_id) = insert_provider_with_open_slot(&db, &suffix).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    // Aucun header Authorization
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/slots/{}/hold", slot_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);

    // Nettoyage
    sqlx::query("DELETE FROM availability_slot WHERE id = $1")
        .bind(slot_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3 : JWT pro (kind="pro") → 403 ──────────────────────────────────────

#[tokio::test]
async fn hold_slot_pro_jwt_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let (_, slot_id) = insert_provider_with_open_slot(&db, &suffix).await;

    // Forge un token pro (scope incorrect pour ce endpoint patient)
    let pro_user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let token = make_pro_jwt(pro_user_id, cabinet_id);

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/slots/{}/hold", slot_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    // Nettoyage
    sqlx::query("DELETE FROM availability_slot WHERE id = $1")
        .bind(slot_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 4 : slot inexistant → 404 ───────────────────────────────────────────

#[tokio::test]
async fn hold_slot_unknown_slot_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let (user_id, account_id) = insert_patient(&db, &suffix).await;
    let token = make_patient_jwt(user_id, account_id);

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    // UUID qui n'existe pas dans availability_slot
    let ghost_slot_id = Uuid::new_v4();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/slots/{}/hold", ghost_slot_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

// ── Test 5 : slot déjà held → 409 slot_taken ─────────────────────────────────

#[tokio::test]
async fn hold_slot_already_held_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let (_, slot_id) = insert_provider_with_open_slot(&db, &suffix).await;

    // Un premier patient prend le slot directement en DB (simule un hold existant).
    let first_user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(first_user_id)
    .bind(format!("shp-first-{}@nubia.test", suffix))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query("UPDATE availability_slot SET status = 'held' WHERE id = $1")
        .bind(slot_id)
        .execute(&db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO slot_holds (slot_id, user_id, hold_token, expires_at) \
         VALUES ($1, $2, 'existing-token', now() + interval '5 minutes')",
    )
    .bind(slot_id)
    .bind(first_user_id)
    .execute(&db)
    .await
    .unwrap();

    // Deuxième patient tente un hold sur le même slot.
    let suffix2 = Uuid::new_v4().to_string();
    let (user_id2, account_id2) = insert_patient(&db, &suffix2).await;
    let token2 = make_patient_jwt(user_id2, account_id2);

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/slots/{}/hold", slot_id))
                .header("Authorization", format!("Bearer {}", token2))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Slot déjà held → 409 slot_taken.
    assert_eq!(response.status(), StatusCode::CONFLICT);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(
        v["code"].as_str(),
        Some("slot_taken"),
        "code d'erreur doit être slot_taken"
    );

    // Nettoyage
    sqlx::query("DELETE FROM slot_holds WHERE slot_id = $1")
        .bind(slot_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM availability_slot WHERE id = $1")
        .bind(slot_id)
        .execute(&db)
        .await
        .ok();
}
