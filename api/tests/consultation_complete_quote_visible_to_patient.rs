//! Test d'intégration : le devis généré à la clôture de consultation est
//! visible côté patient (#4260). `POST /v1/cabinet/consultations/:id/complete`
//! crée le devis en `status='sent'` (pas `'draft'`) — la policy RLS
//! `quote_patient_read` (migrations 0134/0175) exige `status <> 'draft'`.
//! Vérifie aussi (#6573) que ce devis porte `practitioner_id`, comme le
//! devis créé via `POST /v1/cabinet/quotes` — ce chemin, pourtant le plus
//! fréquent, restait anonyme (`practitioner_name` null) malgré #6570.

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

const JWT_SECRET: &str = "test-secret-complete-quote-visible";

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
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_patient_token(sub: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "patient",
            "account_id": account_id,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    patient_id: Uuid,
    patient_user_id: Uuid,
    patient_account_id: Uuid,
    appt_id: Uuid,
    session_id: Uuid,
    provider_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("complete-quote-prac+{prac_user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!(
        "complete-quote-patient+{patient_user_id}@nubia.test"
    ))
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'CompleteQuote')",
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
         VALUES ($1, 'Cabinet CompleteQuote Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO provider (id, practitioner_id, cabinet_id, user_id, display_name) \
         VALUES ($1, $2, $3, $4, 'Dr Hugo Marin')",
    )
    .bind(provider_id)
    .bind(prac_id)
    .bind(cabinet_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Patient', 'CompleteQuote', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', now(), 'in_progress', 'détartrage')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO consultation_session \
         (id, cabinet_id, appointment_id, practitioner_id, status) \
         VALUES ($1, $2, $3, $4, 'in_progress')",
    )
    .bind(session_id)
    .bind(cabinet_id)
    .bind(appt_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO consultation_act \
         (cabinet_id, appointment_id, patient_id, practitioner_id, \
          ccam_code, label, amount_cents) \
         VALUES ($1, $2, $3, $4, 'HBGD036', 'Détartrage', 2864)",
    )
    .bind(cabinet_id)
    .bind(appt_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        patient_user_id,
        patient_account_id,
        appt_id,
        session_id,
        provider_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
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
    sqlx::query("DELETE FROM consultation_act WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_session WHERE id = $1")
        .bind(f.session_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(f.appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(f.provider_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(f.prac_id)
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.patient_user_id)
        .execute(db)
        .await
        .ok();
}

#[tokio::test]
async fn completed_consultation_quote_is_sent_and_visible_to_patient() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let complete_response = app(AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        Request::builder()
            .method("POST")
            .uri(format!(
                "/v1/cabinet/consultations/{}/complete",
                f.session_id
            ))
            .header("Authorization", format!("Bearer {prac_token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();
    assert_eq!(complete_response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(complete_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let invoice_id: Uuid = body["invoice_id"].as_str().unwrap().parse().unwrap();

    // Le devis est créé en 'sent', pas 'draft' (#4260).
    let quote_row = sqlx::query("SELECT status FROM quote WHERE id = $1")
        .bind(invoice_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let quote_status: String = quote_row.try_get("status").unwrap();
    assert_eq!(quote_status, "sent");

    // Le patient le retrouve via GET /v1/quotes (RLS quote_patient_read).
    let patient_token = make_patient_token(f.patient_user_id, f.patient_account_id);
    let list_response = app(AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        Request::builder()
            .method("GET")
            .uri("/v1/quotes")
            .header("Authorization", format!("Bearer {patient_token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();
    assert_eq!(list_response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(list_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let list_body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let quotes = list_body["data"].as_array().unwrap();
    let quote = quotes
        .iter()
        .find(|q| q["id"] == invoice_id.to_string())
        .unwrap_or_else(|| {
            panic!("le devis {invoice_id} doit apparaître dans GET /v1/quotes côté patient : {quotes:?}")
        });
    // #6573 : le devis de clôture de consultation doit porter son émetteur,
    // comme n'importe quel autre devis visible du patient.
    assert_eq!(
        quote["practitioner_name"], "Dr Hugo Marin",
        "le devis {invoice_id} doit exposer practitioner_name : {quote:?}"
    );

    cleanup(&db, &f).await;
}
