//! Tests d'intégration : POST /v1/cabinet/prescriptions/{id}/send (lot B2, issue #3307)

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

const JWT_SECRET: &str = "test-jwt-secret-prescriptions-send";

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

fn pro_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "role": role, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    pro_user_id: Uuid,
    cabinet_id: Uuid,
    prescription_id: Uuid,
    pharmacy_id: Uuid,
    patient_id: Uuid,
}

/// Fixture : cabinet + praticien + patient (compte lié sauf `with_account=false`)
/// + ordonnance signée + pharmacie listée.
async fn seed(db: &PgPool, with_account: bool) -> Fixture {
    let pro_user_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let document_id = Uuid::new_v4();
    let prescription_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();

    for (id, kind) in [(pro_user_id, "pro"), (patient_user_id, "patient")] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(id)
        .bind(format!("ps-{}@nubia.test", id))
        .bind(kind)
        .execute(db)
        .await
        .unwrap();
    }
    let account: Option<Uuid> = if with_account {
        sqlx::query(
            "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
             VALUES ($1, $2, 'Alice', 'Martin')",
        )
        .bind(account_id)
        .bind(patient_user_id)
        .execute(db)
        .await
        .unwrap();
        Some(account_id)
    } else {
        None
    };
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet PS')")
        .bind(cabinet_id)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Alice', 'Martin', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account)
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
        "INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Pharmacie PS', true)",
    )
    .bind(pharmacy_id)
    .execute(db)
    .await
    .unwrap();

    Fixture {
        pro_user_id,
        cabinet_id,
        prescription_id,
        pharmacy_id,
        patient_id,
    }
}

async fn send(
    token: &str,
    prescription_id: Uuid,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let response = app(AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        Request::builder()
            .method("POST")
            .uri(format!("/v1/cabinet/prescriptions/{prescription_id}/send"))
            .header("content-type", "application/json")
            .header("Authorization", format!("Bearer {}", token))
            .body(Body::from(body.to_string()))
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
async fn send_happy_path_creates_order_and_consent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db, true).await;
    let token = pro_jwt(fx.pro_user_id, fx.cabinet_id, "practitioner");

    let (status, order) = send(
        &token,
        fx.prescription_id,
        json!({"pharmacy_id": fx.pharmacy_id}),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED, "body: {order}");
    assert_eq!(order["status"], "received");
    assert_eq!(order["patient_display_name"], "Alice M.");

    let presc_status: String = sqlx::query("SELECT status FROM prescription WHERE id = $1")
        .bind(fx.prescription_id)
        .fetch_one(&db)
        .await
        .unwrap()
        .try_get("status")
        .unwrap();
    assert_eq!(presc_status, "sent");

    // Consentement tracé avec le canal de recueil au cabinet.
    let evidence: serde_json::Value = sqlx::query(
        "SELECT evidence FROM consent_record \
         WHERE patient_account_id = (SELECT patient_account_id FROM patient WHERE id = $1) \
           AND purpose = 'partage_pharmacie'",
    )
    .bind(fx.patient_id)
    .fetch_one(&db)
    .await
    .unwrap()
    .try_get("evidence")
    .unwrap();
    assert_eq!(evidence["channel"], "verbal_in_office");

    // Doublon actif → 409.
    let (status, _) = send(
        &token,
        fx.prescription_id,
        json!({"pharmacy_id": fx.pharmacy_id}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn send_draft_prescription_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db, true).await;
    sqlx::query("UPDATE prescription SET status = 'draft', document_id = NULL WHERE id = $1")
        .bind(fx.prescription_id)
        .execute(&db)
        .await
        .unwrap();

    let (status, _) = send(
        &pro_jwt(fx.pro_user_id, fx.cabinet_id, "practitioner"),
        fx.prescription_id,
        json!({"pharmacy_id": fx.pharmacy_id}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn send_by_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db, true).await;

    let (status, _) = send(
        &pro_jwt(fx.pro_user_id, fx.cabinet_id, "secretary"),
        fx.prescription_id,
        json!({"pharmacy_id": fx.pharmacy_id}),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn send_to_unknown_pharmacy_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db, true).await;

    let (status, _) = send(
        &pro_jwt(fx.pro_user_id, fx.cabinet_id, "practitioner"),
        fx.prescription_id,
        json!({"pharmacy_id": Uuid::new_v4()}),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn send_cross_tenant_prescription_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db, true).await;
    let other_cabinet = Uuid::new_v4();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Autre')")
        .bind(other_cabinet)
        .execute(&db)
        .await
        .unwrap();

    let (status, _) = send(
        &pro_jwt(fx.pro_user_id, other_cabinet, "practitioner"),
        fx.prescription_id,
        json!({"pharmacy_id": fx.pharmacy_id}),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

/// Ordonnance déjà délivrée (une commande `picked_up` existante) → 409
/// `already_ordered`, même garde que le chemin patient (#3736) — sans elle
/// un re-`send` praticien créait une 2e commande pour la même ordonnance
/// signée (double-dispensation, #4402).
#[tokio::test]
async fn send_already_dispensed_prescription_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db, true).await;

    let document_id: Uuid = sqlx::query("SELECT document_id FROM prescription WHERE id = $1")
        .bind(fx.prescription_id)
        .fetch_one(&db)
        .await
        .unwrap()
        .try_get("document_id")
        .unwrap();
    let patient_account_id: Uuid =
        sqlx::query("SELECT patient_account_id FROM patient WHERE id = $1")
            .bind(fx.patient_id)
            .fetch_one(&db)
            .await
            .unwrap()
            .try_get("patient_account_id")
            .unwrap();

    sqlx::query(
        "INSERT INTO pharmacy_order \
         (pharmacy_id, cabinet_id, patient_account_id, prescription_id, document_id, \
          created_by_kind, status, pharmacy_name, patient_display_name, picked_up_at) \
         VALUES ($1, $2, $3, $4, $5, 'patient', 'picked_up', 'Pharmacie PS', 'Alice M.', now())",
    )
    .bind(fx.pharmacy_id)
    .bind(fx.cabinet_id)
    .bind(patient_account_id)
    .bind(fx.prescription_id)
    .bind(document_id)
    .execute(&db)
    .await
    .unwrap();

    let (status, body) = send(
        &pro_jwt(fx.pro_user_id, fx.cabinet_id, "practitioner"),
        fx.prescription_id,
        json!({"pharmacy_id": fx.pharmacy_id}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "body: {body}");
    assert_eq!(body["code"], "already_ordered");

    let order_count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM pharmacy_order WHERE prescription_id = $1")
            .bind(fx.prescription_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(order_count, 1, "aucune 2e commande ne doit être créée");
}

#[tokio::test]
async fn send_patient_without_account_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db, false).await;

    let (status, _) = send(
        &pro_jwt(fx.pro_user_id, fx.cabinet_id, "practitioner"),
        fx.prescription_id,
        json!({"pharmacy_id": fx.pharmacy_id}),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}
