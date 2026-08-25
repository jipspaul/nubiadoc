//! Tests d'intégration : `GET /v1/cabinet/patients` (liste paginée) expose
//! `balance_due_cents` et `no_show_count` par ligne (#5112).
//!
//! Avant #5112, ces champs n'étaient présents que sur `GET
//! /cabinet/patients/:id` (#4044/#4090) — le client devait faire un fetch
//! détail par ligne pour les afficher (N+1 réseau). Ce test couvre le
//! critère d'acceptation : la liste seule suffit.
//!
//! Token `role: "admin"` : bypass volontaire des gardes de scope
//! secrétariat — même choix que `cabinet_patient_balance.rs` (#4044) /
//! `cabinet_patient_no_show_count.rs` (#4090), hors-sujet ici.

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

const JWT_SECRET: &str = "test-secret-patient-list-enrichment";

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

struct Fixture {
    cabinet_id: Uuid,
    admin_user_id: Uuid,
    practitioner_id: Uuid,
    patient_id: Uuid,
    quote_id: Uuid,
}

/// Cabinet + admin + praticien + patient + un devis SIGNÉ de 500,00 € sans
/// paiement (solde plein) — au caller d'ajouter paiements/RDV selon le
/// scénario.
async fn insert_fixture(db: &PgPool, suffix: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let admin_user_id = Uuid::new_v4();
    let practitioner_user_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
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
    .bind(format!("patient-list-enrich-admin-{suffix}@nubia.test"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(practitioner_user_id)
    .bind(format!("patient-list-enrich-prat-{suffix}@nubia.test"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet PatientListEnrich {suffix}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(practitioner_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Marc', 'Liste')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount) \
         VALUES ($1, $2, $3, 'signed', 500.00)",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        admin_user_id,
        practitioner_id,
        patient_id,
        quote_id,
    }
}

async fn insert_appointment(db: &PgPool, f: &Fixture, starts_at: &str, status: &str) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO appointment \
         (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4::timestamptz, $4::timestamptz + interval '30 minutes', $5)",
    )
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .bind(f.practitioner_id)
    .bind(starts_at)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE patient_id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE patient_id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(f.practitioner_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
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
        .bind(f.admin_user_id)
        .execute(db)
        .await
        .ok();
}

async fn list_patients(server: axum::Router, token: &str) -> serde_json::Value {
    let response = server
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/patients")
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

fn find_row(body: &serde_json::Value, patient_id: Uuid) -> &serde_json::Value {
    body["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|row| row["id"] == patient_id.to_string())
        .unwrap_or_else(|| panic!("patient {patient_id} absent de la liste : {body}"))
}

/// Devis signé de 500,00 € sans paiement, 2 RDV `no_show` → la ligne liste
/// porte le solde plein et le compteur, sans fetch détail supplémentaire.
#[tokio::test]
async fn list_row_exposes_balance_and_no_show_count() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixture(&seed_db, &Uuid::new_v4().to_string()).await;
    insert_appointment(&seed_db, &f, "2026-05-01T09:00:00Z", "no_show").await;
    insert_appointment(&seed_db, &f, "2026-05-08T09:00:00Z", "no_show").await;
    insert_appointment(&seed_db, &f, "2026-05-15T09:00:00Z", "done").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_admin_token(Uuid::new_v4(), f.cabinet_id);
    let body = list_patients(app(state), &token).await;
    let row = find_row(&body, f.patient_id);

    assert_eq!(row["balance_due_cents"], 50000, "row: {row}");
    assert_eq!(row["no_show_count"], 2, "row: {row}");

    cleanup(&seed_db, &f).await;
}

/// Paiement intégral du devis signé → solde à 0 sur la ligne liste, pas
/// seulement sur le détail.
#[tokio::test]
async fn list_row_balance_reflects_full_payment() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixture(&seed_db, &Uuid::new_v4().to_string()).await;

    let mut tx = seed_db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO payment \
         (cabinet_id, patient_id, quote_id, amount, currency, kind, provider, status) \
         VALUES ($1, $2, $3, 500.00, 'EUR', 'full', 'stripe', 'paid')",
    )
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .bind(f.quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_admin_token(Uuid::new_v4(), f.cabinet_id);
    let body = list_patients(app(state), &token).await;
    let row = find_row(&body, f.patient_id);

    assert_eq!(row["balance_due_cents"], 0, "row: {row}");
    assert_eq!(row["no_show_count"], 0, "row: {row}");

    cleanup(&seed_db, &f).await;
}
