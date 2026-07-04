//! Tests d'intégration : commandes click-and-collect (lot B2, issue #3307)
//! POST /v1/account/prescriptions/{id}/order · GET /v1/account/orders[/{id}]
//! GET /v1/pharmacy/orders[/{id}] · GET /v1/pharmacy/orders/{id}/document
//! GET|PUT /v1/account/pharmacy · GET /v1/cabinet/patients/{id}/pharmacy

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

const JWT_SECRET: &str = "test-jwt-secret-pharmacy-orders";

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

fn test_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
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

fn pharma_jwt(user_id: Uuid, pharmacy_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pharma", "pharmacy_id": pharmacy_id,
                "role": "pharmacist", "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn pro_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id,
                "role": role, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Fixture complète : cabinet + patient (compte lié) + ordonnance signée avec
/// PDF + pharmacie listée. Retourne les ids utiles.
struct Fixture {
    user_id: Uuid,
    account_id: Uuid,
    patient_id: Uuid,
    cabinet_id: Uuid,
    prescription_id: Uuid,
    pharmacy_id: Uuid,
}

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

    for (id, kind) in [(user_id, "patient"), (pro_user_id, "pro")] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(id)
        .bind(format!("po-{}@nubia.test", id))
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
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet PO')")
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
         VALUES ($1, $2, $3, $4, 'signed', $5, now())",
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
        "INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Pharmacie PO', true)",
    )
    .bind(pharmacy_id)
    .execute(db)
    .await
    .unwrap();

    Fixture {
        user_id,
        account_id,
        patient_id,
        cabinet_id,
        prescription_id,
        pharmacy_id,
    }
}

async fn request(
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
    let response = app(test_state(app_pool().await))
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

// ── Création par le patient ───────────────────────────────────────────────────

#[tokio::test]
async fn patient_creates_order_and_prescription_becomes_sent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let token = patient_jwt(fx.user_id, fx.account_id);

    let (status, order) = request(
        "POST",
        &format!("/v1/account/prescriptions/{}/order", fx.prescription_id),
        &token,
        Some(json!({"pharmacy_id": fx.pharmacy_id})),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED, "body: {order}");
    assert_eq!(order["status"], "received");
    assert_eq!(order["pharmacy_name"], "Pharmacie PO");
    assert_eq!(order["patient_display_name"], "Jean D.");

    // La prescription passe à `sent` et le consentement est tracé.
    let presc_status: String = sqlx::query("SELECT status FROM prescription WHERE id = $1")
        .bind(fx.prescription_id)
        .fetch_one(&db)
        .await
        .unwrap()
        .try_get("status")
        .unwrap();
    assert_eq!(presc_status, "sent");

    let consent_count: i64 = sqlx::query(
        "SELECT count(*) AS n FROM consent_record \
         WHERE patient_account_id = $1 AND purpose = 'partage_pharmacie' AND granted",
    )
    .bind(fx.account_id)
    .fetch_one(&db)
    .await
    .unwrap()
    .try_get("n")
    .unwrap();
    assert_eq!(consent_count, 1);

    // Doublon actif → 409.
    let (status, _) = request(
        "POST",
        &format!("/v1/account/prescriptions/{}/order", fx.prescription_id),
        &token,
        Some(json!({"pharmacy_id": fx.pharmacy_id})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn patient_cannot_order_draft_prescription() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    sqlx::query("UPDATE prescription SET status = 'draft', document_id = NULL WHERE id = $1")
        .bind(fx.prescription_id)
        .execute(&db)
        .await
        .unwrap();

    let (status, _) = request(
        "POST",
        &format!("/v1/account/prescriptions/{}/order", fx.prescription_id),
        &patient_jwt(fx.user_id, fx.account_id),
        Some(json!({"pharmacy_id": fx.pharmacy_id})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn patient_cannot_order_to_unlisted_pharmacy() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    sqlx::query("UPDATE pharmacy SET is_listed = false WHERE id = $1")
        .bind(fx.pharmacy_id)
        .execute(&db)
        .await
        .unwrap();

    let (status, _) = request(
        "POST",
        &format!("/v1/account/prescriptions/{}/order", fx.prescription_id),
        &patient_jwt(fx.user_id, fx.account_id),
        Some(json!({"pharmacy_id": fx.pharmacy_id})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn patient_cannot_order_someone_elses_prescription() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    // Autre compte patient, sans lien avec l'ordonnance.
    let other_user = Uuid::new_v4();
    let other_account = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(other_user)
    .bind(format!("other-{}@nubia.test", other_user))
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

    let (status, _) = request(
        "POST",
        &format!("/v1/account/prescriptions/{}/order", fx.prescription_id),
        &patient_jwt(other_user, other_account),
        Some(json!({"pharmacy_id": fx.pharmacy_id})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "anti-énumération RLS");
}

// ── Lecture des deux bords ────────────────────────────────────────────────────

#[tokio::test]
async fn pharmacy_and_patient_see_the_order_other_pharmacy_does_not() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let patient_token = patient_jwt(fx.user_id, fx.account_id);
    let (status, order) = request(
        "POST",
        &format!("/v1/account/prescriptions/{}/order", fx.prescription_id),
        &patient_token,
        Some(json!({"pharmacy_id": fx.pharmacy_id})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let order_id = order["id"].as_str().unwrap().to_string();

    // Vue patient : liste + détail.
    let (status, list) = request("GET", "/v1/account/orders", &patient_token, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(list["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|o| o["id"] == order["id"]));

    // Vue pharmacie : liste (+ filtre statut) et détail.
    let pharma_token = pharma_jwt(Uuid::new_v4(), fx.pharmacy_id);
    let (status, list) = request(
        "GET",
        "/v1/pharmacy/orders?status=received",
        &pharma_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(list["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|o| o["id"] == order["id"]));

    let (status, detail) = request(
        "GET",
        &format!("/v1/pharmacy/orders/{order_id}"),
        &pharma_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(detail["patient_display_name"], "Jean D.");

    // Une autre pharmacie → 404 (RLS).
    let other_pharmacy = Uuid::new_v4();
    sqlx::query("INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Autre', true)")
        .bind(other_pharmacy)
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = request(
        "GET",
        &format!("/v1/pharmacy/orders/{order_id}"),
        &pharma_jwt(Uuid::new_v4(), other_pharmacy),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Un token pro n'ouvre jamais l'espace pharmacie → 403.
    let (status, _) = request(
        "GET",
        "/v1/pharmacy/orders",
        &pro_jwt(Uuid::new_v4(), fx.cabinet_id, "practitioner"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn pharmacy_gets_signed_document_url() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let (_, order) = request(
        "POST",
        &format!("/v1/account/prescriptions/{}/order", fx.prescription_id),
        &patient_jwt(fx.user_id, fx.account_id),
        Some(json!({"pharmacy_id": fx.pharmacy_id})),
    )
    .await;
    let order_id = order["id"].as_str().unwrap();

    let (status, doc) = request(
        "GET",
        &format!("/v1/pharmacy/orders/{order_id}/document"),
        &pharma_jwt(Uuid::new_v4(), fx.pharmacy_id),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {doc}");
    assert!(
        doc["url"].as_str().unwrap().contains("storage.example.com"),
        "URL signée du stub attendue"
    );
}

// ── Pharmacie déclarée ────────────────────────────────────────────────────────

#[tokio::test]
async fn declared_pharmacy_roundtrip_patient_and_cabinet_views() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let patient_token = patient_jwt(fx.user_id, fx.account_id);

    // Aucune pharmacie déclarée → 204.
    let (status, _) = request("GET", "/v1/account/pharmacy", &patient_token, None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    // Déclaration → 200 avec la pharmacie.
    let (status, pharmacy) = request(
        "PUT",
        "/v1/account/pharmacy",
        &patient_token,
        Some(json!({"pharmacy_id": fx.pharmacy_id})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(pharmacy["raison_sociale"], "Pharmacie PO");

    let (status, pharmacy) = request("GET", "/v1/account/pharmacy", &patient_token, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(pharmacy["id"], json!(fx.pharmacy_id));

    // Vue praticien : présélection à l'envoi d'ordonnance.
    let pro_token = pro_jwt(Uuid::new_v4(), fx.cabinet_id, "practitioner");
    let (status, pharmacy) = request(
        "GET",
        &format!("/v1/cabinet/patients/{}/pharmacy", fx.patient_id),
        &pro_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(pharmacy["id"], json!(fx.pharmacy_id));

    // Patient d'un autre cabinet → 404 (anti-probing avant SECURITY DEFINER).
    let other_cabinet = Uuid::new_v4();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Autre cabinet')")
        .bind(other_cabinet)
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = request(
        "GET",
        &format!("/v1/cabinet/patients/{}/pharmacy", fx.patient_id),
        &pro_jwt(Uuid::new_v4(), other_cabinet, "practitioner"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Pharmacie inconnue à la déclaration → 404.
    let (status, _) = request(
        "PUT",
        "/v1/account/pharmacy",
        &patient_token,
        Some(json!({"pharmacy_id": Uuid::new_v4()})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
