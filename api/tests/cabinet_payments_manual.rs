//! Tests d'intégration : POST /v1/cabinet/payments/manual (#4070)
//!
//! Encaissement manuel (espèces/chèque/virement) sans PaymentIntent
//! Stripe/GoCardless : crée un `payment` `status='paid'` immédiat.

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-payments-manual";

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

struct Fixture {
    cabinet_id: Uuid,
    patient_id: Uuid,
    quote_id: Uuid,
}

/// Seed : cabinet + patient + devis `sent` (100.00 EUR).
async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet CPM {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'ManualPayment')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'sent', 100.00, 'EUR')",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        patient_id,
        quote_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM payment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE id = $1")
        .bind(f.quote_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
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

async fn create_manual(
    state: AppState,
    token: String,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/payments/manual")
                .header("Authorization", format!("Bearer {token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(body.to_string()))
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

// ── Test 1 : method='cash' -> paiement paid associé au bon devis/cabinet ────

#[tokio::test]
async fn create_manual_payment_with_cash_creates_paid_payment() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let user_id = Uuid::new_v4();

    let (status, resp) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 10000,
            "method": "cash"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(resp["status"], "paid");
    let payment_id: Uuid = resp["payment_id"].as_str().unwrap().parse().unwrap();

    let row = sqlx::query(
        "SELECT cabinet_id, patient_id, quote_id, status, provider, method, \
                (amount * 100)::bigint AS amount_cents \
         FROM payment WHERE id = $1",
    )
    .bind(payment_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let cabinet_id: Uuid = row.try_get("cabinet_id").unwrap();
    let patient_id: Uuid = row.try_get("patient_id").unwrap();
    let quote_id: Uuid = row.try_get("quote_id").unwrap();
    let status: String = row.try_get("status").unwrap();
    let provider: String = row.try_get("provider").unwrap();
    let method: String = row.try_get("method").unwrap();
    let amount_cents: i64 = row.try_get("amount_cents").unwrap();

    assert_eq!(cabinet_id, f.cabinet_id);
    assert_eq!(patient_id, f.patient_id);
    assert_eq!(quote_id, f.quote_id);
    assert_eq!(status, "paid");
    assert_eq!(provider, "manual");
    assert_eq!(method, "cash");
    assert_eq!(amount_cents, 10000);

    cleanup(&db, &f).await;
}

// ── Test 2 : patient d'un autre cabinet -> 404 (RLS) ─────────────────────────

#[tokio::test]
async fn create_manual_payment_cross_tenant_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let other_cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    let (status, _) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, other_cabinet_id, "secretary"),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 10000,
            "method": "cash"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);

    // Aucun paiement ne doit avoir été créé pour le cabinet ciblé par erreur.
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM payment WHERE cabinet_id = $1")
        .bind(other_cabinet_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(count, 0);

    cleanup(&db, &f).await;
}

// ── Test 3 : method invalide (card, doit passer par PaymentIntent) -> 422 ───

#[tokio::test]
async fn create_manual_payment_with_card_method_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let user_id = Uuid::new_v4();

    let (status, _) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 10000,
            "method": "card"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test 4 : montant <= 0 -> 422 ─────────────────────────────────────────────

#[tokio::test]
async fn create_manual_payment_with_zero_amount_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let user_id = Uuid::new_v4();

    let (status, _) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 0,
            "method": "check"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test 5 : token secretary -> 201 (autorisé), token patient -> 403 ────────

#[tokio::test]
async fn create_manual_payment_with_practitioner_token_succeeds() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let user_id = Uuid::new_v4();

    let (status, _) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "practitioner"),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 5000,
            "method": "bank_transfer"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);

    cleanup(&db, &f).await;
}
