//! Tests d'intégration : GET /v1/payments (liste patient, #3238)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-payments-list";

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

fn make_patient_token(sub: Uuid, account_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        account_id: Uuid,
        exp: u64,
    }
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "patient".into(),
            account_id,
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Fixture : cabinet + compte + patient + paiement 114,00 € deposit paid.
async fn insert_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let account_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let payment_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(account_user_id)
    .bind(format!("payments+{}@nubia.test", account_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Payments', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Pay', 'Ments')",
    )
    .bind(account_id)
    .bind(account_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name) \
         VALUES ($1, $2, $3, 'Pay', 'Ments')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO payment (id, cabinet_id, patient_id, amount, kind, provider, status) \
         VALUES ($1, $2, $3, 114.00, 'deposit', 'stripe', 'paid')",
    )
    .bind(payment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    (
        cabinet_id,
        account_user_id,
        account_id,
        patient_id,
        payment_id,
    )
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    account_user_id: Uuid,
    account_id: Uuid,
    patient_id: Uuid,
    payment_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    for q in [
        ("DELETE FROM payment WHERE id = $1", payment_id),
        ("DELETE FROM patient WHERE id = $1", patient_id),
        ("DELETE FROM patient_account WHERE id = $1", account_id),
        ("DELETE FROM cabinet WHERE id = $1", cabinet_id),
        ("DELETE FROM app_user WHERE id = $1", account_user_id),
    ] {
        sqlx::query(q.0).bind(q.1).execute(&mut *tx).await.ok();
    }
    tx.commit().await.ok();
}

async fn get_payments(token: &str) -> (StatusCode, serde_json::Value) {
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/payments")
                .header("authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null),
    )
}

// ── Test 1 : le patient voit son paiement avec les bons champs ────────────────

#[tokio::test]
async fn patient_sees_own_payment() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, account_user_id, account_id, patient_id, payment_id) =
        insert_fixture(&owner).await;

    let (status, json) = get_payments(&make_patient_token(account_user_id, account_id)).await;

    assert_eq!(status, StatusCode::OK);
    let data = json["data"].as_array().expect("data tableau");
    let item = data
        .iter()
        .find(|p| p["payment_id"] == payment_id.to_string())
        .expect("le paiement du patient doit apparaître");
    assert_eq!(item["kind"], "deposit");
    assert_eq!(item["status"], "paid");
    assert_eq!(item["amount_cents"], 11400);
    assert_eq!(item["currency"], "EUR");

    cleanup_fixture(
        &owner,
        cabinet_id,
        account_user_id,
        account_id,
        patient_id,
        payment_id,
    )
    .await;
}

// ── Test 2 : isolation RLS — un autre patient ne voit pas ce paiement ─────────

#[tokio::test]
async fn other_patient_cannot_see_payment() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, account_user_id, account_id, patient_id, payment_id) =
        insert_fixture(&owner).await;

    let (status, json) = get_payments(&make_patient_token(Uuid::new_v4(), Uuid::new_v4())).await;

    assert_eq!(status, StatusCode::OK);
    let data = json["data"].as_array().unwrap();
    assert!(
        !data
            .iter()
            .any(|p| p["payment_id"] == payment_id.to_string()),
        "fuite RLS : paiement visible par un autre patient"
    );

    cleanup_fixture(
        &owner,
        cabinet_id,
        account_user_id,
        account_id,
        patient_id,
        payment_id,
    )
    .await;
}
