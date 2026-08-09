//! Test d'intégration : GET /v1/cabinet/patients/{id}/alerts (#4093)

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

const JWT_SECRET: &str = "test-secret-patient-alerts";

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

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid, secretariat_id: Option<Uuid>) -> String {
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
            "role": "secretary",
            "secretariat_id": secretariat_id,
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
    user_id: Uuid,
    patient_overdue_id: Uuid,
    patient_up_to_date_id: Uuid,
    secretariat_id: Uuid,
    prac_user_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_overdue_id = Uuid::new_v4();
    let patient_up_to_date_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();
    let overdue_quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("patientalerts+{user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();
    // Praticien porteur du scope secrétariat (app_user global, hors tx cabinet).
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("patientalerts-prac+{prac_user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Alerts Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'Impaye')",
    )
    .bind(patient_overdue_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'AJour')",
    )
    .bind(patient_up_to_date_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Patient en retard : devis signé il y a 45 jours, aucun paiement.
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, signed_at) \
         VALUES ($1, $2, $3, 'signed', 500.00, now() - interval '45 days')",
    )
    .bind(overdue_quote_id)
    .bind(cabinet_id)
    .bind(patient_overdue_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    // balance_due_cents (#4794) est dérivé des lignes quote_item (part patient
    // nette), pas de quote.total_amount — sans ligne, le solde serait 0 et
    // l'alerte unpaid_invoice ne se déclencherait jamais (même piège que #4433).
    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, qty, unit_amount) \
         VALUES ($1, $2, 'Item test', 1, 500.00)",
    )
    .bind(cabinet_id)
    .bind(overdue_quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Patient à jour : devis signé il y a 45 jours, mais intégralement payé.
    sqlx::query(
        "INSERT INTO quote (cabinet_id, patient_id, status, total_amount, signed_at) \
         VALUES ($1, $2, 'signed', 300.00, now() - interval '45 days')",
    )
    .bind(cabinet_id)
    .bind(patient_up_to_date_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO payment (cabinet_id, patient_id, amount, kind, provider, status) \
         VALUES ($1, $2, 300.00, 'full', 'stripe', 'paid')",
    )
    .bind(cabinet_id)
    .bind(patient_up_to_date_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Carte mutuelle scannée pour le patient à jour uniquement.
    sqlx::query(
        "INSERT INTO document (cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256) \
         VALUES ($1, $2, 'carte_mutuelle', 'stub-key', 'carte.pdf', 'application/pdf', repeat('a', 64))",
    )
    .bind(cabinet_id)
    .bind(patient_up_to_date_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Scope secrétariat (R10) : sans practitioner + provider +
    // provider_secretariat(active) + appointment liant CHAQUE patient au
    // praticien, `ensure_secretary_scope` masque le patient en 404.
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, is_listed, rpps_verified) \
         VALUES ($1, $2, $3, $4, 'Dr. Alerts Test', true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec Alerts Test')",
    )
    .bind(secretariat_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO provider_secretariat (provider_id, secretariat_id, active) \
         VALUES ($1, $2, true)",
    )
    .bind(provider_id)
    .bind(secretariat_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    // Un RDV confirmé par patient pour matérialiser le scope secrétariat. Créneaux
    // DÉCALÉS par index (patient 0 → J+1, patient 1 → J+2) : même praticien au même
    // créneau violerait la contrainte d'exclusion appointment_no_overlap.
    for (i, patient_id) in [patient_overdue_id, patient_up_to_date_id]
        .into_iter()
        .enumerate()
    {
        let offset = format!("{} day", i + 1);
        sqlx::query(
            "INSERT INTO appointment \
             (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
             VALUES ($1, $2, $3, $4, now() + $5::interval, now() + $5::interval + interval '1 hour', 'confirmed')",
        )
        .bind(Uuid::new_v4())
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(prac_id)
        .bind(offset)
        .execute(&mut *tx)
        .await
        .unwrap();
    }

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
        patient_overdue_id,
        patient_up_to_date_id,
        secretariat_id,
        prac_user_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM document WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM payment WHERE cabinet_id = $1")
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
    // Scope secrétariat, ordre FK avant patient/cabinet.
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query(
        "DELETE FROM provider_secretariat WHERE provider_id IN \
         (SELECT id FROM provider WHERE cabinet_id = $1)",
    )
    .bind(f.cabinet_id)
    .execute(&mut *tx)
    .await
    .ok();
    sqlx::query("DELETE FROM secretariat WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM app_user WHERE id = ANY($1)")
        .bind(vec![f.user_id, f.prac_user_id])
        .execute(db)
        .await
        .ok();
}

#[tokio::test]
async fn overdue_patient_gets_unpaid_and_missing_document_alerts() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id, Some(f.secretariat_id));

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/alerts",
                    f.patient_overdue_id
                ))
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
    let alerts = body["alerts"].as_array().unwrap();
    let kinds: Vec<&str> = alerts.iter().map(|a| a["kind"].as_str().unwrap()).collect();
    assert!(kinds.contains(&"unpaid_invoice"), "kinds={kinds:?}");
    assert!(kinds.contains(&"missing_document"), "kinds={kinds:?}");

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn up_to_date_patient_gets_no_alerts() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id, Some(f.secretariat_id));

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/alerts",
                    f.patient_up_to_date_id
                ))
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
    let alerts = body["alerts"].as_array().unwrap();
    assert!(alerts.is_empty(), "alerts={alerts:?}");

    cleanup(&db, &f).await;
}
