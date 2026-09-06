//! Tests d'intégration : devis d'officine (lot B7, issue #3312)

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

const JWT_SECRET: &str = "test-jwt-secret-pharmacy-quotes";

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

fn pharma_jwt(pharmacy_id: Uuid, role: &str) -> String {
    encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "pharma", "pharmacy_id": pharmacy_id,
                "role": role, "exp": exp()}),
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
        .bind(format!("pq-{}@nubia.test", id))
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
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet PQ')")
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
        "INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Pharmacie PQ', true)",
    )
    .bind(pharmacy_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO pharmacy_order (id, pharmacy_id, cabinet_id, patient_account_id, \
                                     prescription_id, document_id, created_by_kind, \
                                     pharmacy_name, patient_display_name) \
         VALUES ($1, $2, $3, $4, $5, $6, 'patient', 'Pharmacie PQ', 'Jean D.')",
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
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("Authorization", format!("Bearer {}", token));
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

#[tokio::test]
async fn full_cycle_draft_sent_accepted() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharmacist = pharma_jwt(fx.pharmacy_id, "pharmacist");
    let patient = patient_jwt(fx.user_id, fx.account_id);

    // Création : total calculé côté serveur (2×450 + 1×650 = 1550).
    let (status, quote) = call(
        "POST",
        "/v1/pharmacy/quotes",
        &pharmacist,
        Some(json!({
            "order_id": fx.order_id,
            "items": [
                {"label": "Bain de bouche", "qty": 2, "unit_price_cents": 450},
                {"label": "Brossettes interdentaires", "qty": 1, "unit_price_cents": 650}
            ]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {quote}");
    assert_eq!(quote["status"], "draft");
    assert_eq!(quote["total_cents"], 1550);
    assert_eq!(quote["patient_display_name"], "Jean D.");
    let id = quote["id"].as_str().unwrap().to_string();

    // Brouillon invisible côté patient.
    let (status, list) = call("GET", "/v1/account/pharmacy-quotes", &patient, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(!list["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|q| q["id"] == quote["id"]));

    // Un préparateur ne peut pas envoyer un devis → 403.
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/quotes/{id}/send"),
        &pharma_jwt(fx.pharmacy_id, "preparator"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // Envoi → sent, visible et décidable côté patient.
    let (status, quote) = call(
        "POST",
        &format!("/v1/pharmacy/quotes/{id}/send"),
        &pharmacist,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(quote["status"], "sent");

    // Double envoi → 409.
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/quotes/{id}/send"),
        &pharmacist,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    let (status, list) = call("GET", "/v1/account/pharmacy-quotes", &patient, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(list["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|q| q["id"] == quote["id"] && q["pharmacy_name"] == "Pharmacie PQ"));

    // Notification patient créée à l'envoi (sans PII).
    let count: i64 = sqlx::Row::try_get(
        &sqlx::query(
            "SELECT count(*) AS n FROM notification \
             WHERE app_user_id = $1 AND kind = 'pharmacy_quote_sent'",
        )
        .bind(fx.user_id)
        .fetch_one(&db)
        .await
        .unwrap(),
        "n",
    )
    .unwrap();
    assert_eq!(count, 1);

    // Acceptation → accepted ; re-décision → 409.
    let (status, quote) = call(
        "POST",
        &format!("/v1/account/pharmacy-quotes/{id}/accept"),
        &patient,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(quote["status"], "accepted");
    let (status, _) = call(
        "POST",
        &format!("/v1/account/pharmacy-quotes/{id}/refuse"),
        &patient,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn remind_sent_quote_renotifies_without_changing_status() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharmacist = pharma_jwt(fx.pharmacy_id, "pharmacist");

    let (_, quote) = call(
        "POST",
        "/v1/pharmacy/quotes",
        &pharmacist,
        Some(json!({
            "order_id": fx.order_id,
            "items": [
                {"label": "Bain de bouche", "qty": 1, "unit_price_cents": 450}
            ]
        })),
    )
    .await;
    let id = quote["id"].as_str().unwrap().to_string();

    // Relancer un brouillon (jamais envoyé) → 409 : rien à relancer.
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/quotes/{id}/remind"),
        &pharmacist,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/quotes/{id}/send"),
        &pharmacist,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // Un préparateur ne peut pas relancer → 403.
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/quotes/{id}/remind"),
        &pharma_jwt(fx.pharmacy_id, "preparator"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // Relance : reste `sent`, ré-notifie le patient (pas de PII).
    let (status, quote) = call(
        "POST",
        &format!("/v1/pharmacy/quotes/{id}/remind"),
        &pharmacist,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {quote}");
    assert_eq!(quote["status"], "sent");

    let count: i64 = sqlx::Row::try_get(
        &sqlx::query(
            "SELECT count(*) AS n FROM notification \
             WHERE app_user_id = $1 AND kind = 'pharmacy_quote_reminder'",
        )
        .bind(fx.user_id)
        .fetch_one(&db)
        .await
        .unwrap(),
        "n",
    )
    .unwrap();
    assert_eq!(count, 1);

    // Relance sur un devis inconnu → 404.
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/quotes/{}/remind", Uuid::new_v4()),
        &pharmacist,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn validation_and_isolation() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharmacist = pharma_jwt(fx.pharmacy_id, "pharmacist");

    // Items vides / prix négatif → 422.
    let (status, _) = call(
        "POST",
        "/v1/pharmacy/quotes",
        &pharmacist,
        Some(json!({"order_id": fx.order_id, "items": []})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = call(
        "POST",
        "/v1/pharmacy/quotes",
        &pharmacist,
        Some(json!({"order_id": fx.order_id,
                    "items": [{"label": "X", "qty": 1, "unit_price_cents": -5}]})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Commande d'une autre pharmacie → 404 (RLS).
    let other_pharmacy = Uuid::new_v4();
    sqlx::query("INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Autre', true)")
        .bind(other_pharmacy)
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = call(
        "POST",
        "/v1/pharmacy/quotes",
        &pharma_jwt(other_pharmacy, "pharmacist"),
        Some(json!({"order_id": fx.order_id,
                    "items": [{"label": "X", "qty": 1, "unit_price_cents": 100}]})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Un autre patient ne peut pas décider (RLS → 404).
    let (_, quote) = call(
        "POST",
        "/v1/pharmacy/quotes",
        &pharmacist,
        Some(json!({"order_id": fx.order_id,
                    "items": [{"label": "X", "qty": 1, "unit_price_cents": 100}]})),
    )
    .await;
    let id = quote["id"].as_str().unwrap().to_string();
    call(
        "POST",
        &format!("/v1/pharmacy/quotes/{id}/send"),
        &pharmacist,
        None,
    )
    .await;

    let other_user = Uuid::new_v4();
    let other_account = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(other_user)
    .bind(format!("intrus-{}@nubia.test", other_user))
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Intrus', 'X')",
    )
    .bind(other_account)
    .bind(other_user)
    .execute(&db)
    .await
    .unwrap();
    let (status, _) = call(
        "POST",
        &format!("/v1/account/pharmacy-quotes/{id}/accept"),
        &patient_jwt(other_user, other_account),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

// ── Test (#4415) : commande d'ancrage terminale → 409 invalid_status ────────

#[tokio::test]
async fn create_on_terminal_order_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharmacist = pharma_jwt(fx.pharmacy_id, "pharmacist");

    for terminal_status in ["picked_up", "cancelled", "rejected"] {
        sqlx::query("UPDATE pharmacy_order SET status = $1 WHERE id = $2")
            .bind(terminal_status)
            .bind(fx.order_id)
            .execute(&db)
            .await
            .unwrap();

        let (status, body) = call(
            "POST",
            "/v1/pharmacy/quotes",
            &pharmacist,
            Some(json!({"order_id": fx.order_id,
                        "items": [{"label": "X", "qty": 1, "unit_price_cents": 100}]})),
        )
        .await;
        assert_eq!(
            status,
            StatusCode::CONFLICT,
            "order status={terminal_status} doit refuser la création: {body}"
        );
        assert_eq!(body["code"], "invalid_status");
    }
}

// ── Tests (#6588) : la commande d'ancrage devient terminale APRÈS l'envoi du
// devis → celui-ci doit sortir de `sent` (vers `expired`) au lieu de rester
// indéfiniment "à signer" alors qu'`accept`/`refuse` répondent tous deux 409
// (aucune route de sortie, ni patient ni pharmacie) ──────────────────────────

/// Crée un devis (1 ligne quelconque) sur `order_id` et l'envoie : draft → sent.
async fn send_quote(pharmacist: &str, order_id: Uuid) -> String {
    let (status, quote) = call(
        "POST",
        "/v1/pharmacy/quotes",
        pharmacist,
        Some(json!({"order_id": order_id,
                    "items": [{"label": "X", "qty": 1, "unit_price_cents": 100}]})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {quote}");
    let id = quote["id"].as_str().unwrap().to_string();
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/quotes/{id}/send"),
        pharmacist,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    id
}

#[tokio::test]
async fn picked_up_order_expires_pending_quote() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharmacist = pharma_jwt(fx.pharmacy_id, "pharmacist");
    let member = pharma_jwt(fx.pharmacy_id, "preparator");
    let patient = patient_jwt(fx.user_id, fx.account_id);

    let id = send_quote(&pharmacist, fx.order_id).await;

    // received → preparing → ready, puis retrait (parcours normal).
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/accept", fx.order_id),
        &member,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/ready", fx.order_id),
        &member,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, token_body) = call(
        "GET",
        &format!("/v1/account/orders/{}/pickup-token", fx.order_id),
        &patient,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let token = token_body["token"].as_str().unwrap().to_string();

    let (status, order) = call(
        "POST",
        "/v1/pharmacy/orders/pickup-scan",
        &member,
        Some(json!({"token": token, "expected_order_id": fx.order_id})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {order}");
    assert_eq!(order["status"], "picked_up");

    // Le devis ne doit plus rester "sent" — sinon Accepter/Refuser restent
    // peints actifs côté patient (PharmacyQuote.isDecidable) alors que les
    // deux répondent 409 à vie.
    let (status, list) = call("GET", "/v1/account/pharmacy-quotes", &patient, None).await;
    assert_eq!(status, StatusCode::OK);
    let quote = list["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|q| q["id"] == id)
        .unwrap();
    assert_eq!(quote["status"], "expired", "body: {quote}");
    assert!(quote["decided_at"].is_string());
}

#[tokio::test]
async fn rejected_order_expires_pending_quote() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharmacist = pharma_jwt(fx.pharmacy_id, "pharmacist");
    let patient = patient_jwt(fx.user_id, fx.account_id);

    let id = send_quote(&pharmacist, fx.order_id).await;

    let (status, order) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/reject", fx.order_id),
        &pharmacist,
        Some(json!({"reason": "Rupture de stock"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {order}");
    assert_eq!(order["status"], "rejected");

    let (status, list) = call("GET", "/v1/account/pharmacy-quotes", &patient, None).await;
    assert_eq!(status, StatusCode::OK);
    let quote = list["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|q| q["id"] == id)
        .unwrap();
    assert_eq!(quote["status"], "expired", "body: {quote}");
}

#[tokio::test]
async fn cancelled_order_expires_pending_quote() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharmacist = pharma_jwt(fx.pharmacy_id, "pharmacist");
    let patient = patient_jwt(fx.user_id, fx.account_id);

    let id = send_quote(&pharmacist, fx.order_id).await;

    let (status, order) = call(
        "POST",
        &format!("/v1/account/orders/{}/cancel", fx.order_id),
        &patient,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {order}");
    assert_eq!(order["status"], "cancelled");

    let (status, list) = call("GET", "/v1/account/pharmacy-quotes", &patient, None).await;
    assert_eq!(status, StatusCode::OK);
    let quote = list["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|q| q["id"] == id)
        .unwrap();
    assert_eq!(quote["status"], "expired", "body: {quote}");
}
