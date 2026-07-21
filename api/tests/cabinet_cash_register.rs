//! Tests d'intégration : POST /v1/cabinet/cash-register/closing (#4071)
//!
//! Clôture de caisse journalière : agrège les paiements `paid` du jour par
//! méthode (manual/cash, card, sepa) et fige le résultat.

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-cash-register";

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

/// Seed : cabinet + patient + devis + 4 paiements aujourd'hui
/// (manual/cash=30.00 paid, stripe/card=50.00 paid, gocardless/sepa=20.00
/// paid, stripe/card=99.00 PENDING — ne doit PAS être agrégé) + 1 paiement
/// d'hier (manual/cash=1000.00 paid — ne doit PAS être agrégé, hors jour).
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
        .bind(format!("Cabinet CCR {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'CashRegister')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'sent', 199.00, 'EUR')",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Paiements du jour, 3 méthodes distinctes, tous paid.
    sqlx::query(
        "INSERT INTO payment \
         (cabinet_id, patient_id, quote_id, amount, currency, kind, provider, status, method, created_at) \
         VALUES \
           ($1, $2, $3, 30.00, 'EUR', 'full', 'manual', 'paid', 'cash', now()), \
           ($1, $2, $3, 50.00, 'EUR', 'full', 'stripe', 'paid', 'card', now()), \
           ($1, $2, $3, 20.00, 'EUR', 'full', 'gocardless', 'paid', 'sepa', now()), \
           ($1, $2, $3, 99.00, 'EUR', 'full', 'stripe', 'pending', 'card', now())",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Paiement d'hier : ne doit pas être agrégé dans la clôture du jour.
    sqlx::query(
        "INSERT INTO payment \
         (cabinet_id, patient_id, quote_id, amount, currency, kind, provider, status, method, created_at) \
         VALUES ($1, $2, $3, 1000.00, 'EUR', 'full', 'manual', 'paid', 'cash', now() - interval '1 day')",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(quote_id)
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
    sqlx::query("DELETE FROM cash_register_closing WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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

async fn close_register(
    state: AppState,
    token: String,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/cash-register/closing")
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

// ── Test 1 : la clôture agrège correctement manual+card+sepa du jour ────────

#[tokio::test]
async fn close_cash_register_aggregates_todays_paid_payments_by_method() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let user_id = Uuid::new_v4();

    let (status, resp) = close_register(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        json!({}),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(resp["totals_by_method"]["cash"], 3000);
    assert_eq!(resp["totals_by_method"]["card"], 5000);
    assert_eq!(resp["totals_by_method"]["sepa"], 2000);
    // Le paiement pending et celui d'hier ne doivent apparaître nulle part.
    assert_eq!(
        resp["total_amount_cents"], 10000,
        "30+50+20 EUR = 10000 cents"
    );

    let closing_id: Uuid = resp["id"].as_str().unwrap().parse().unwrap();
    let row = sqlx::query(
        "SELECT totals_by_method, (total_amount * 100)::bigint AS total_cents \
         FROM cash_register_closing WHERE id = $1",
    )
    .bind(closing_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let totals: serde_json::Value = row.try_get("totals_by_method").unwrap();
    let total_cents: i64 = row.try_get("total_cents").unwrap();
    assert_eq!(totals["cash"], 3000);
    assert_eq!(total_cents, 10000);

    cleanup(&db, &f).await;
}

// ── Test 2 : une deuxième clôture le même jour → 409 ─────────────────────────

#[tokio::test]
async fn close_cash_register_twice_same_day_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let user_id = Uuid::new_v4();

    let (first_status, _) = close_register(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        json!({}),
    )
    .await;
    assert_eq!(first_status, StatusCode::CREATED);

    let (second_status, second_body) = close_register(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        json!({}),
    )
    .await;
    assert_eq!(second_status, StatusCode::CONFLICT);
    assert_eq!(second_body["code"], "cash_register_already_closed");

    cleanup(&db, &f).await;
}
