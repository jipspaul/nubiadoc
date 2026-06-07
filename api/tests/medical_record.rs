//! Tests d'intégration : GET + PATCH /v1/cabinet/patients/:id/medical-record (§14)
//!
//! Tests requis par l'issue #781 :
//! 1. GET avec token secretary → 403 (R.4127-72)
//! 2. GET avec token praticien autre cabinet → 403 (RLS, patient introuvable → 404)
//! 3. GET avec token praticien → 200 + entrée audit_log(action='read_record')

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

const JWT_SECRET: &str = "test-secret-medical-record";

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

fn make_state(db: PgPool) -> AppState {
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
        + 900
}

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "practitioner".into(),
            exp: exp(),
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "secretary".into(),
            exp: exp(),
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère les fixtures minimales : cabinet + app_user + patient.
/// Retourne `(cabinet_id, user_id, patient_id)`.
async fn insert_fixtures(db: &PgPool) -> (Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("mr-prac+{}@nubia.test", user_id))
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
         VALUES ($1, 'Cabinet MR Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Dupont')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (cabinet_id, user_id, patient_id)
}

async fn cleanup_fixtures(db: &PgPool, cabinet_id: Uuid, user_id: Uuid, patient_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM medical_record WHERE patient_id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : secretary → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn get_medical_record_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/medical-record", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 2 : praticien d'un autre cabinet → patient introuvable → 404 ─────────

#[tokio::test]
async fn get_medical_record_other_cabinet_practitioner_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    // JWT signé pour un cabinet différent → RLS filtre le patient → 404.
    let other_cabinet_id = Uuid::new_v4();
    let other_user_id = Uuid::new_v4();
    let token = make_practitioner_token(other_user_id, other_cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/medical-record", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 3 : praticien → 200 + entrée audit_log ───────────────────────────────

#[tokio::test]
async fn get_medical_record_practitioner_returns_200_and_audit() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/medical-record", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["allergies"].is_array(), "allergies doit être un tableau");
    assert!(v["treatments"].is_array(), "treatments doit être un tableau");

    // Vérifie l'entrée audit_log (rôle owner, bypass RLS).
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let audit_row = sqlx::query(
        "SELECT action FROM audit_log \
         WHERE cabinet_id = $1 AND actor_id = $2 AND entity_id = $3 AND action = 'read_record' \
         LIMIT 1",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .bind(patient_id)
    .fetch_optional(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    assert!(
        audit_row.is_some(),
        "une entrée audit_log read_record doit exister"
    );

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}
