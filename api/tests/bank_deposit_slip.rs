//! Tests d'intégration : GET /v1/cabinet/payments/bank-deposit-slip (#4128).

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

const JWT_SECRET: &str = "test-secret-bank-deposit-slip";

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

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &json!({
            "sub": sub, "kind": "pro", "cabinet_id": cabinet_id,
            "role": "secretary", "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    secretary_user_id: Uuid,
    check_payment_id: Uuid,
    already_included_payment_id: Uuid,
}

async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let secretary_user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let check_payment_id = Uuid::new_v4();
    let already_included_payment_id = Uuid::new_v4();
    let card_payment_id = Uuid::new_v4();
    let old_slip_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(secretary_user_id)
    .bind(format!(
        "bordereau-secretary+{secretary_user_id}@nubia.test"
    ))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Bordereau Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Cheque', 'Payeur')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Chèque encaissé dans la période, jamais inclus sur un bordereau : doit apparaître.
    sqlx::query(
        "INSERT INTO payment (id, cabinet_id, patient_id, amount, currency, kind, provider, status, method, created_at) \
         VALUES ($1, $2, $3, 120.00, 'EUR', 'full', 'manual', 'paid', 'check', now() - interval '2 days')",
    )
    .bind(check_payment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Chèque déjà inclus dans un bordereau précédent : doit être exclu.
    sqlx::query(
        "INSERT INTO payment (id, cabinet_id, patient_id, amount, currency, kind, provider, status, method, created_at) \
         VALUES ($1, $2, $3, 80.00, 'EUR', 'full', 'manual', 'paid', 'check', now() - interval '3 days')",
    )
    .bind(already_included_payment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO bank_deposit_slip (id, cabinet_id, period_from, period_to, total_amount_cents) \
         VALUES ($1, $2, (now() - interval '10 days')::date, (now() - interval '4 days')::date, 8000)",
    )
    .bind(old_slip_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO bank_deposit_slip_payment (cabinet_id, slip_id, payment_id) VALUES ($1, $2, $3)",
    )
    .bind(cabinet_id)
    .bind(old_slip_id)
    .bind(already_included_payment_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Paiement carte dans la période : ne doit jamais apparaître (mauvais method).
    sqlx::query(
        "INSERT INTO payment (id, cabinet_id, patient_id, amount, currency, kind, provider, status, method, created_at) \
         VALUES ($1, $2, $3, 999.00, 'EUR', 'full', 'stripe', 'paid', 'card', now() - interval '2 days')",
    )
    .bind(card_payment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        secretary_user_id,
        check_payment_id,
        already_included_payment_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM bank_deposit_slip_payment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM bank_deposit_slip WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM payment WHERE cabinet_id = $1")
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
        .bind(f.secretary_user_id)
        .execute(db)
        .await
        .ok();
}

#[tokio::test]
async fn bank_deposit_slip_excludes_already_included_and_non_check_payments() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_secretary_token(f.secretary_user_id, f.cabinet_id);

    let from = (chrono::Utc::now() - chrono::Duration::days(9))
        .format("%Y-%m-%d")
        .to_string();
    let to = chrono::Utc::now().format("%Y-%m-%d").to_string();

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/payments/bank-deposit-slip?from={from}&to={to}"
                ))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let body: serde_json::Value = serde_json::from_slice(
        &axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap(),
    )
    .unwrap();

    let data = body["data"].as_array().unwrap();
    assert_eq!(data.len(), 1);
    assert_eq!(data[0]["payment_id"], f.check_payment_id.to_string());
    assert_eq!(body["total_amount_cents"], 12000);
    assert!(!body["slip_id"].is_null());
    assert!(!body["pdf_url"].is_null());

    // Le chèque déjà bordereauté ne doit jamais réapparaître.
    for item in data {
        assert_ne!(
            item["payment_id"],
            f.already_included_payment_id.to_string()
        );
    }

    cleanup_fixtures(&db, &f).await;
}

#[tokio::test]
async fn bank_deposit_slip_second_call_returns_nothing_new() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_secretary_token(f.secretary_user_id, f.cabinet_id);

    let from = (chrono::Utc::now() - chrono::Duration::days(9))
        .format("%Y-%m-%d")
        .to_string();
    let to = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let uri = format!("/v1/cabinet/payments/bank-deposit-slip?from={from}&to={to}");

    let app_instance = app(make_state(app_pool().await));
    let first = app_instance
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&uri)
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::OK);

    let second = app_instance
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(&uri)
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::OK);
    let body: serde_json::Value = serde_json::from_slice(
        &axum::body::to_bytes(second.into_body(), usize::MAX)
            .await
            .unwrap(),
    )
    .unwrap();

    assert_eq!(body["data"].as_array().unwrap().len(), 0);
    assert_eq!(body["total_amount_cents"], 0);
    assert!(body["slip_id"].is_null());
    assert!(body["pdf_url"].is_null());

    cleanup_fixtures(&db, &f).await;
}

#[tokio::test]
async fn bank_deposit_slip_rejects_invalid_date_range() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_secretary_token(f.secretary_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/payments/bank-deposit-slip?from=2026-01-10&to=2026-01-01")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, &f).await;
}
