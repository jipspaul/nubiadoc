//! Tests d'intégration : `GET /v1/cabinet/patients/:id` expose `balance_due_cents`
//! (#4044, US-4.6.2).
//!
//! Couvre le critère d'acceptation de l'issue : solde calculé pour un patient
//! avec facture (devis signé) partiellement payée vs soldée.
//!
//! Token `role: "admin"` : bypass volontaire des gardes de scope secrétariat
//! (`in_scope`, provider_secretariat) et relation de soin praticien
//! (`has_appointment`) de `get_cabinet_patient` — hors-sujet pour ce test,
//! qui porte uniquement sur le calcul du solde (présent pour tous les rôles
//! pro, `PatientAdminSection` est commune).

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

const JWT_SECRET: &str = "test-secret-patient-balance";

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

async fn seed_pool() -> PgPool {
    let url = std::env::var("SEED_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_seed@localhost:5432/nubia".into());
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
        + 900;
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": "admin",
            "exp": exp,
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère cabinet + admin user + patient + un devis SIGNÉ (`total_amount`)
/// et un paiement PAID (`paid_amount`, ou aucun paiement si `None`) ;
/// retourne `(cabinet_id, admin_user_id, patient_id, quote_id)`.
async fn insert_fixture(
    db: &PgPool,
    suffix: &str,
    total_amount: &str,
    paid_amount: Option<&str>,
) -> (Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let admin_user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(admin_user_id)
    .bind(format!("patient-balance-admin-{suffix}@nubia.test"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet PatientBalance {suffix}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Marc', 'Solde')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount) \
         VALUES ($1, $2, $3, 'signed', $4::numeric)",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(total_amount)
    .execute(&mut *tx)
    .await
    .unwrap();

    if let Some(amount) = paid_amount {
        sqlx::query(
            "INSERT INTO payment \
             (cabinet_id, patient_id, quote_id, amount, currency, kind, provider, status) \
             VALUES ($1, $2, $3, $4::numeric, 'EUR', 'full', 'stripe', 'paid')",
        )
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(quote_id)
        .bind(amount)
        .execute(&mut *tx)
        .await
        .unwrap();
    }

    tx.commit().await.unwrap();

    (cabinet_id, admin_user_id, patient_id, quote_id)
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, admin_user_id: Uuid, patient_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM payment WHERE patient_id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE patient_id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(admin_user_id)
        .execute(db)
        .await
        .ok();
}

async fn get_patient(server: axum::Router, patient_id: Uuid, token: &str) -> serde_json::Value {
    let response = server
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

/// Devis signé de 500,00 € avec un paiement partiel de 200,00 € → solde 300,00 €.
#[tokio::test]
async fn balance_due_reflects_partial_payment() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, admin_user_id, patient_id, _quote_id) = insert_fixture(
        &seed_db,
        &Uuid::new_v4().to_string(),
        "500.00",
        Some("200.00"),
    )
    .await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_admin_token(Uuid::new_v4(), cabinet_id);
    let body = get_patient(app(state), patient_id, &token).await;

    assert_eq!(body["balance_due_cents"], 30_000, "body: {body}");

    cleanup(&seed_db, cabinet_id, admin_user_id, patient_id).await;
}

/// Devis signé de 300,00 € intégralement payé → solde 0.
#[tokio::test]
async fn balance_due_is_zero_when_quote_fully_paid() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, admin_user_id, patient_id, _quote_id) = insert_fixture(
        &seed_db,
        &Uuid::new_v4().to_string(),
        "300.00",
        Some("300.00"),
    )
    .await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_admin_token(Uuid::new_v4(), cabinet_id);
    let body = get_patient(app(state), patient_id, &token).await;

    assert_eq!(body["balance_due_cents"], 0, "body: {body}");

    cleanup(&seed_db, cabinet_id, admin_user_id, patient_id).await;
}
