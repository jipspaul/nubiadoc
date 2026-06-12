//! Tests d'intégration : POST /v1/cabinet/appointments/:id/confirm

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

const JWT_SECRET: &str = "test-secret-appt-confirm";

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

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
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
            "exp": exp,
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
            "exp": exp,
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère les fixtures minimales : cabinet + praticien + patient + RDV.
/// `status` est le statut initial du RDV inséré.
/// Retourne `(cabinet_id, prac_id, prac_user_id, appt_id)`.
async fn insert_fixture(db: &PgPool, status: &str) -> (Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("confirm-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet Confirm Test', 'dentaire')",
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'Confirm')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() + interval '2 hours', now() + interval '3 hours', $5, 'détartrage')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (cabinet_id, prac_id, prac_user_id, appt_id)
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    appt_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM audit_log WHERE entity_id = $1")
        .bind(appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

// ── Test 1 : secrétaire, RDV pending_confirmation → 200 + status confirmed ────

#[tokio::test]
async fn confirm_appointment_secretary_requested_returns_200() {
    if !db_available() {
        return;
    }

    let owner_db = owner_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_id, prac_user_id, appt_id) = insert_fixture(&owner_db, "requested").await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id);
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/appointments/{}/confirm", appt_id))
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
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["status"], "confirmed");
    assert_eq!(body["appointment_id"], appt_id.to_string());

    cleanup_fixture(&owner_db, cabinet_id, prac_id, prac_user_id, appt_id).await;
}

// ── Test 2 : RDV déjà confirmed → 409 invalid_status ─────────────────────────

#[tokio::test]
async fn confirm_appointment_already_confirmed_returns_409() {
    if !db_available() {
        return;
    }

    let owner_db = owner_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_id, prac_user_id, appt_id) = insert_fixture(&owner_db, "confirmed").await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id);
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/appointments/{}/confirm", appt_id))
                .header("Authorization", format!("Bearer {}", token))
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
    assert_eq!(body["error"], "invalid_status");

    cleanup_fixture(&owner_db, cabinet_id, prac_id, prac_user_id, appt_id).await;
}

// ── Test 3 : token patient → 403 ─────────────────────────────────────────────

#[tokio::test]
async fn confirm_appointment_patient_token_returns_403() {
    if !db_available() {
        return;
    }

    let owner_db = owner_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_id, prac_user_id, appt_id) = insert_fixture(&owner_db, "requested").await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let token = make_patient_token(patient_user_id, patient_account_id);
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/appointments/{}/confirm", appt_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup_fixture(&owner_db, cabinet_id, prac_id, prac_user_id, appt_id).await;
}
