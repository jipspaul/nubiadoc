//! Tests d'intégration : `GET /v1/cabinet/patients/:id` expose `no_show_count`
//! (#4090).
//!
//! Couvre le critère d'acceptation de l'issue : un patient à 0 et un patient
//! à 3 lapins (`appointment.status = 'no_show'`).
//!
//! Token `role: "admin"` : bypass volontaire des gardes de scope secrétariat/
//! relation de soin de `get_cabinet_patient` — hors-sujet ici, même choix que
//! `cabinet_patient_balance.rs` (#4044).

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

const JWT_SECRET: &str = "test-secret-patient-no-show-count";

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
}

/// Insère cabinet + admin user + praticien + patient. Ne pose aucun
/// `appointment` — au caller d'en insérer selon le scénario.
async fn insert_fixture(db: &PgPool, suffix: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let admin_user_id = Uuid::new_v4();
    let practitioner_user_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

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
    .bind(format!("patient-noshow-admin-{suffix}@nubia.test"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(practitioner_user_id)
    .bind(format!("patient-noshow-prat-{suffix}@nubia.test"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet PatientNoShow {suffix}"))
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
         VALUES ($1, $2, 'Léon', 'Lapin')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        admin_user_id,
        practitioner_id,
        patient_id,
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

/// Patient sans aucun RDV `no_show` → compteur à 0.
#[tokio::test]
async fn no_show_count_is_zero_without_no_show_appointments() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixture(&seed_db, &Uuid::new_v4().to_string()).await;
    insert_appointment(&seed_db, &f, "2026-05-01T09:00:00Z", "completed").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_admin_token(Uuid::new_v4(), f.cabinet_id);
    let body = get_patient(app(state), f.patient_id, &token).await;

    assert_eq!(body["no_show_count"], 0, "body: {body}");

    cleanup(&seed_db, &f).await;
}

/// Patient avec 3 RDV `no_show` (+ 1 `completed` non compté) → compteur à 3.
#[tokio::test]
async fn no_show_count_reflects_three_no_shows() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixture(&seed_db, &Uuid::new_v4().to_string()).await;
    insert_appointment(&seed_db, &f, "2026-05-01T09:00:00Z", "no_show").await;
    insert_appointment(&seed_db, &f, "2026-05-08T09:00:00Z", "no_show").await;
    insert_appointment(&seed_db, &f, "2026-05-15T09:00:00Z", "no_show").await;
    insert_appointment(&seed_db, &f, "2026-05-22T09:00:00Z", "completed").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_admin_token(Uuid::new_v4(), f.cabinet_id);
    let body = get_patient(app(state), f.patient_id, &token).await;

    assert_eq!(body["no_show_count"], 3, "body: {body}");

    cleanup(&seed_db, &f).await;
}
