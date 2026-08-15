//! Tests d'intégration : GET /v1/cabinet/quotes?overdue=true (#4130)

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-quotes-overdue";

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
    user_id: Uuid,
    patient_id: Uuid,
}

async fn seed_cabinet(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("cq-overdue+{user_id}@nubia.test"))
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
        .bind(format!("Cabinet CQ Overdue {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES ($1, $2, 'Bob', 'Impaye')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
        patient_id,
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
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn overdue_ids(state: AppState, token: &str) -> Vec<String> {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/quotes?status=signed&overdue=true")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    v.as_array()
        .unwrap()
        .iter()
        .filter_map(|q| q["id"].as_str().map(String::from))
        .collect()
}

// ── Test 1 : devis signé il y a >30j, sans paiement → apparaît ──────────────

#[tokio::test]
async fn signed_over_30_days_unpaid_appears_in_overdue() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed_cabinet(&db).await;
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, signed_at) \
         VALUES ($1, $2, $3, 'signed', 200.00, 'EUR', now() - interval '31 days')",
    )
    .bind(quote_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, qty, unit_amount, amo_part, amc_part) \
         VALUES ($1, $2, 'Soin', 1, 200.00, 0, 0)",
    )
    .bind(f.cabinet_id)
    .bind(quote_id)
    .execute(&db)
    .await
    .unwrap();

    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");
    let ids = overdue_ids(state_with(app_pool().await), &token).await;
    assert!(
        ids.contains(&quote_id.to_string()),
        "devis signé sans paiement depuis 31 jours doit apparaître en impayé"
    );

    cleanup(&db, &f).await;
}

// ── Test 2 : même devis mais soldé → n'apparaît pas ──────────────────────────

#[tokio::test]
async fn signed_over_30_days_but_fully_paid_does_not_appear() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed_cabinet(&db).await;
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, signed_at) \
         VALUES ($1, $2, $3, 'signed', 200.00, 'EUR', now() - interval '31 days')",
    )
    .bind(quote_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, qty, unit_amount, amo_part, amc_part) \
         VALUES ($1, $2, 'Soin', 1, 200.00, 0, 0)",
    )
    .bind(f.cabinet_id)
    .bind(quote_id)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO payment (cabinet_id, patient_id, quote_id, amount, kind, provider, status) \
         VALUES ($1, $2, $3, 200.00, 'full', 'manual', 'paid')",
    )
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .bind(quote_id)
    .execute(&db)
    .await
    .unwrap();

    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");
    let ids = overdue_ids(state_with(app_pool().await), &token).await;
    assert!(
        !ids.contains(&quote_id.to_string()),
        "devis soldé ne doit PAS apparaître en impayé"
    );

    cleanup(&db, &f).await;
}

// ── Test 3 : devis signé récemment (<30j), impayé → n'apparaît pas encore ───

#[tokio::test]
async fn signed_recently_unpaid_does_not_appear_yet() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed_cabinet(&db).await;
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, signed_at) \
         VALUES ($1, $2, $3, 'signed', 200.00, 'EUR', now() - interval '2 days')",
    )
    .bind(quote_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, qty, unit_amount, amo_part, amc_part) \
         VALUES ($1, $2, 'Soin', 1, 200.00, 0, 0)",
    )
    .bind(f.cabinet_id)
    .bind(quote_id)
    .execute(&db)
    .await
    .unwrap();

    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");
    let ids = overdue_ids(state_with(app_pool().await), &token).await;
    assert!(
        !ids.contains(&quote_id.to_string()),
        "devis signé il y a 2 jours seulement ne doit pas encore apparaître en impayé"
    );

    cleanup(&db, &f).await;
}

// ── Test 4 : devis 100% tiers-payant (part patient nulle) → n'apparaît pas ──
// #5535 : le filtre comparait les paiements au total BRUT (AMO+AMC inclus)
// au lieu du reste-à-charge patient net, classant à tort en impayé un devis
// intégralement couvert par le tiers-payant.

#[tokio::test]
async fn signed_over_30_days_full_third_party_payer_does_not_appear() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed_cabinet(&db).await;
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, signed_at) \
         VALUES ($1, $2, $3, 'signed', 800.00, 'EUR', now() - interval '55 days')",
    )
    .bind(quote_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, qty, unit_amount, amo_part, amc_part) \
         VALUES ($1, $2, 'Soin', 1, 800.00, 600.00, 200.00)",
    )
    .bind(f.cabinet_id)
    .bind(quote_id)
    .execute(&db)
    .await
    .unwrap();

    let token = make_pro_jwt(f.user_id, f.cabinet_id, "admin");
    let ids = overdue_ids(state_with(app_pool().await), &token).await;
    assert!(
        !ids.contains(&quote_id.to_string()),
        "devis 100% tiers-payant (part patient nulle) ne doit PAS apparaître en impayé"
    );

    cleanup(&db, &f).await;
}
