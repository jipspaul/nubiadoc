//! Tests d'intégration : POST /v1/payments/pharmacy-quote-intent (#3732)

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

const JWT_SECRET: &str = "test-jwt-secret-pharmacy-quote-payment";

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

fn patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn pharma_jwt(pharmacy_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "pharma", "pharmacy_id": pharmacy_id,
                "role": "pharmacist", "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    user_id: Uuid,
    account_id: Uuid,
    pharmacy_id: Uuid,
    order_id: Uuid,
}

/// Fixture : commande `received` (le devis s'y rattache).
async fn seed(db: &PgPool) -> Fixture {
    let user_id = Uuid::new_v4();
    let pro_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let document_id = Uuid::new_v4();
    let prescription_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();
    let order_id = Uuid::new_v4();

    for (id, kind) in [(user_id, "patient"), (pro_user_id, "pro")] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(id)
        .bind(format!("pqp-{}@nubia.test", id))
        .bind(kind)
        .execute(db)
        .await
        .unwrap();
    }
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Jean', 'Demo')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet PQP')")
        .bind(cabinet_id)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Jean', 'Demo', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(pro_user_id)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, \
                               mime_type, sha256, scan_status, uploaded_by, size_bytes) \
         VALUES ($1, $2, $3, 'ordonnance', $4, 'ordo.pdf', 'application/pdf', \
                 repeat('0', 64), 'clean', $5, 0)",
    )
    .bind(document_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(format!("sk-{}", document_id))
    .bind(pro_user_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, \
                                   document_id, signed_at) \
         VALUES ($1, $2, $3, $4, 'sent', $5, now())",
    )
    .bind(prescription_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(document_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Pharmacie PQP', true)",
    )
    .bind(pharmacy_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO pharmacy_order (id, pharmacy_id, cabinet_id, patient_account_id, \
                                     prescription_id, document_id, created_by_kind, \
                                     pharmacy_name, patient_display_name) \
         VALUES ($1, $2, $3, $4, $5, $6, 'patient', 'Pharmacie PQP', 'Jean D.')",
    )
    .bind(order_id)
    .bind(pharmacy_id)
    .bind(cabinet_id)
    .bind(account_id)
    .bind(prescription_id)
    .bind(document_id)
    .execute(db)
    .await
    .unwrap();

    Fixture {
        user_id,
        account_id,
        pharmacy_id,
        order_id,
    }
}

async fn call(
    method: &str,
    uri: &str,
    token: &str,
    idempotency_key: Option<&str>,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("Authorization", format!("Bearer {}", token));
    if let Some(key) = idempotency_key {
        builder = builder.header("Idempotency-Key", key);
    }
    if body.is_some() {
        builder = builder.header("content-type", "application/json");
    }
    let response = app(AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        builder
            .body(match body {
                Some(v) => Body::from(v.to_string()),
                None => Body::empty(),
            })
            .unwrap(),
    )
    .await
    .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
    (status, v)
}

/// Repro exacte de #3732 : un 2e intent avec une clé d'idempotence DIFFÉRENTE
/// sur le même devis `accepted` doit être refusé (reste dû = 0), et non créer
/// un 2e paiement plein-montant.
#[tokio::test]
async fn second_intent_with_different_key_returns_422_no_remaining_due() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharmacist = pharma_jwt(fx.pharmacy_id);
    let patient = patient_jwt(fx.user_id, fx.account_id);

    let (status, quote) = call(
        "POST",
        "/v1/pharmacy/quotes",
        &pharmacist,
        None,
        Some(json!({
            "order_id": fx.order_id,
            "items": [{"label": "Bain de bouche", "qty": 1, "unit_price_cents": 500}]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {quote}");
    let quote_id = quote["id"].as_str().unwrap().to_string();

    call(
        "POST",
        &format!("/v1/pharmacy/quotes/{quote_id}/send"),
        &pharmacist,
        None,
        None,
    )
    .await;
    let (status, quote) = call(
        "POST",
        &format!("/v1/account/pharmacy-quotes/{quote_id}/accept"),
        &patient,
        None,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {quote}");

    // 1er intent (clé K1) → 201, payment plein-montant. Clés générées par run
    // (pas de littéral fixe) : idempotency_keys a un cache TTL 24h partagé
    // entre exécutions de test, une clé constante collisionnerait entre runs.
    let key1 = format!("qa-3732-{}", Uuid::new_v4());
    let key2 = format!("qa-3732-{}", Uuid::new_v4());
    let (status, first) = call(
        "POST",
        "/v1/payments/pharmacy-quote-intent",
        &patient,
        Some(&key1),
        Some(json!({"pharmacy_quote_id": quote_id, "method": "card"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {first}");

    // 2e intent (clé K2, DIFFÉRENTE) sur le MÊME devis → doit être refusé.
    let (status, second) = call(
        "POST",
        "/v1/payments/pharmacy-quote-intent",
        &patient,
        Some(&key2),
        Some(json!({"pharmacy_quote_id": quote_id, "method": "card"})),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "body: {second} — reste dû doit être 0 après le 1er paiement"
    );

    // Un seul paiement en base pour ce devis.
    let count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM payment WHERE pharmacy_quote_id = $1::uuid")
            .bind(&quote_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(count, 1, "un seul paiement doit exister pour ce devis");
}
