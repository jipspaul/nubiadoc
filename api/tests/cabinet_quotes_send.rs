//! Tests d'intégration : POST /v1/cabinet/quotes/:id/send (issue #3436)
//!
//! Envoi d'un devis (brouillon) au patient côté praticien : transition
//! `draft → sent`, idempotence, isolation tenant (RLS), statuts non envoyables.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-cabinet-quotes-send";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": user_id,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": role,
            "exp": exp
        }),
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
        &json!({
            "sub": user_id,
            "kind": "patient",
            "account_id": account_id,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Seed : cabinet + patient + un devis au statut `status`. Retourne le quote_id.
async fn seed_quote(db: &PgPool, cabinet_id: Uuid, patient_id: Uuid, status: &str) -> Uuid {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet CQS {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Patient')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    let quote_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, $4, 380, 'EUR')",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    quote_id
}

async fn quote_status(db: &PgPool, cabinet_id: Uuid, quote_id: Uuid) -> String {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT status FROM quote WHERE id = $1")
        .bind(quote_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    let status: String = row.try_get("status").unwrap();
    tx.commit().await.unwrap();
    status
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn send(state: AppState, quote_id: Uuid, token: String) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/quotes/{quote_id}/send"))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

// ── Test 1 : happy path — brouillon envoyé, statut passe à `sent` ─────────────

#[tokio::test]
async fn send_draft_quote_transitions_to_sent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let quote_id = seed_quote(&db, cabinet_id, patient_id, "draft").await;

    let (status, body) = send(
        state_with(app_pool().await),
        quote_id,
        make_pro_jwt(user_id, cabinet_id, "practitioner"),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "sent");
    assert_eq!(body["sent"], true);
    assert_eq!(body["id"], quote_id.to_string());

    // Le changement est persisté côté serveur (plus factice).
    assert_eq!(quote_status(&db, cabinet_id, quote_id).await, "sent");

    cleanup(&db, cabinet_id).await;
}

// ── Test 2 : idempotence — un devis déjà `sent` renvoie 200 ──────────────────

#[tokio::test]
async fn send_already_sent_quote_is_idempotent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let quote_id = seed_quote(&db, cabinet_id, patient_id, "sent").await;

    let (status, body) = send(
        state_with(app_pool().await),
        quote_id,
        make_pro_jwt(user_id, cabinet_id, "secretary"),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "sent");

    cleanup(&db, cabinet_id).await;
}

// ── Test 3 : devis inexistant → 404 ──────────────────────────────────────────

#[tokio::test]
async fn send_unknown_quote_returns_404() {
    if !db_available() {
        return;
    }
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    let (status, _) = send(
        state_with(app_pool().await),
        Uuid::new_v4(),
        make_pro_jwt(user_id, cabinet_id, "practitioner"),
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
}

// ── Test 4 : devis d'un autre cabinet → 404 (isolation RLS) ──────────────────

#[tokio::test]
async fn send_quote_of_other_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = Uuid::new_v4();
    let other_cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let quote_id = seed_quote(&db, cabinet_id, patient_id, "draft").await;

    // Token scopé sur un AUTRE cabinet → le devis est invisible (404), pas envoyé.
    let (status, _) = send(
        state_with(app_pool().await),
        quote_id,
        make_pro_jwt(user_id, other_cabinet_id, "practitioner"),
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(quote_status(&db, cabinet_id, quote_id).await, "draft");

    cleanup(&db, cabinet_id).await;
}

// ── Test 5 : devis déjà signé → 409 (statut non envoyable) ───────────────────

#[tokio::test]
async fn send_signed_quote_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let quote_id = seed_quote(&db, cabinet_id, patient_id, "signed").await;

    let (status, body) = send(
        state_with(app_pool().await),
        quote_id,
        make_pro_jwt(user_id, cabinet_id, "practitioner"),
    )
    .await;

    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "invalid_status");

    cleanup(&db, cabinet_id).await;
}

// ── Test 6 : token patient → 403 ─────────────────────────────────────────────

#[tokio::test]
async fn send_with_patient_token_returns_403() {
    let (status, _) = send(
        state_with(
            PgPool::connect_lazy(
                &std::env::var("APP_DATABASE_URL")
                    .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
            )
            .unwrap(),
        ),
        Uuid::new_v4(),
        make_patient_jwt(Uuid::new_v4(), Uuid::new_v4()),
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);
}
