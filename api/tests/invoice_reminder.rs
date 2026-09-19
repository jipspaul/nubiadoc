//! Test d'intégration : `POST /v1/invoices/:id/reminder` (#7206).

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

const JWT_SECRET: &str = "test-secret-invoice-reminder";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
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
            "role": "practitioner",
            "secretariat_id": null,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

struct Fixture {
    cabinet_id: Uuid,
    staff_user_id: Uuid,
    patient_user_id: Uuid,
    patient_account_id: Uuid,
    quote_id: Uuid,
    draft_quote_id: Uuid,
}

/// Devis signé, un item à 500.00€, aucun paiement -> `balance_due_cents = 50000`.
async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let staff_user_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();
    let draft_quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(staff_user_id)
    .bind(format!("invoicereminder-staff+{staff_user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!(
        "invoicereminder-patient+{patient_user_id}@nubia.test"
    ))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Relance', 'Facture')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
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
         VALUES ($1, 'Cabinet Invoice Reminder Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Patient', 'Impaye', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, signed_at) \
         VALUES ($1, $2, $3, 'signed', 500.00, 'EUR', now())",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, qty, unit_amount) \
         VALUES ($1, $2, 'Item test', 1, 500.00)",
    )
    .bind(cabinet_id)
    .bind(quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    // Devis NON signé : ne doit jamais être traité comme une facture.
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'draft', 100.00, 'EUR')",
    )
    .bind(draft_quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        staff_user_id,
        patient_user_id,
        patient_account_id,
        quote_id,
        draft_quote_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM invoice_reminder WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_item WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = ANY($1)")
        .bind(vec![f.staff_user_id, f.patient_user_id])
        .execute(db)
        .await
        .ok();
}

#[tokio::test]
async fn reminder_sent_and_traced_then_cooldown_blocks_retry() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = seed(&owner_db).await;
    let token = make_practitioner_token(f.staff_user_id, f.cabinet_id);

    // Premier appel : envoyé sur les deux canaux (patient avec compte + e-mail).
    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/invoices/{}/reminder", f.quote_id))
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
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["sent"], json!(true));
    assert_eq!(body["balance_due_cents"], json!(50000));
    let channels: Vec<&str> = body["channels"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c.as_str().unwrap())
        .collect();
    assert!(channels.contains(&"push"), "channels={channels:?}");
    assert!(channels.contains(&"email"), "channels={channels:?}");

    // Tracé : 2 lignes invoice_reminder (push + email), sent_by = l'appelant.
    let mut tx = owner_db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let rows = sqlx::query(
        "SELECT channel, sent_by FROM invoice_reminder WHERE invoice_id = $1 ORDER BY channel",
    )
    .bind(f.quote_id)
    .fetch_all(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(rows.len(), 2);
    for row in &rows {
        let sent_by: Uuid = row.try_get("sent_by").unwrap();
        assert_eq!(sent_by, f.staff_user_id);
    }

    // Deuxième appel immédiat : bloqué par le garde-fou 7 jours (#7206).
    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/invoices/{}/reminder", f.quote_id))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CONFLICT);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["code"], json!("invoice_reminder_cooldown"));

    cleanup(&owner_db, &f).await;
}

#[tokio::test]
async fn reminder_on_unsigned_quote_returns_not_found() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = seed(&owner_db).await;
    let token = make_practitioner_token(f.staff_user_id, f.cabinet_id);

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/invoices/{}/reminder", f.draft_quote_id))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    cleanup(&owner_db, &f).await;
}

#[tokio::test]
async fn list_reminders_returns_history_after_send() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = seed(&owner_db).await;
    let token = make_practitioner_token(f.staff_user_id, f.cabinet_id);

    // Aucune relance encore envoyée -> historique vide (#7205).
    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/invoices/{}/reminders", f.quote_id))
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
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["data"], json!([]));

    app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/invoices/{}/reminder", f.quote_id))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Une relance envoyée sur 2 canaux (push + email) -> 2 entrées.
    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/invoices/{}/reminders", f.quote_id))
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
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let data = body["data"].as_array().unwrap();
    assert_eq!(data.len(), 2);
    let channels: Vec<&str> = data.iter().map(|r| r["channel"].as_str().unwrap()).collect();
    assert!(channels.contains(&"push"), "channels={channels:?}");
    assert!(channels.contains(&"email"), "channels={channels:?}");

    cleanup(&owner_db, &f).await;
}

#[tokio::test]
async fn list_reminders_on_unknown_invoice_returns_not_found() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = seed(&owner_db).await;
    let token = make_practitioner_token(f.staff_user_id, f.cabinet_id);

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/invoices/{}/reminders", Uuid::new_v4()))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    cleanup(&owner_db, &f).await;
}

#[tokio::test]
async fn reminder_on_unknown_invoice_returns_not_found() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = seed(&owner_db).await;
    let token = make_practitioner_token(f.staff_user_id, f.cabinet_id);

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/invoices/{}/reminder", Uuid::new_v4()))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    cleanup(&owner_db, &f).await;
}
