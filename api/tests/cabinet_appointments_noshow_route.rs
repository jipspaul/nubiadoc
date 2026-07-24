//! Tests d'intégration : `POST /v1/cabinet/appointments/:id/no-show` (#4037).
//!
//! Couvre les critères d'acceptation de l'issue :
//! - transition `confirmed → no_show` + entrée `audit_log` associée ;
//! - rejet `409` depuis un statut déjà terminal (`cancelled`, `done`) ;
//! - rejet `409 too_early` pour un RDV encore à venir (#4369).

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

const JWT_SECRET: &str = "test-secret-appt-noshow-route";

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

/// Insère cabinet + praticien + patient + slot `booked` + RDV.
/// `status` est le statut initial du RDV inséré, `starts_at_offset` un
/// intervalle SQL relatif à `now()` (ex. `"- interval '2 hours'"` pour un
/// RDV passé, `"+ interval '2 hours'"` pour un RDV à venir — #4369).
/// Retourne `(cabinet_id, prac_id, prac_user_id, appt_id, slot_id)`.
async fn insert_fixture_at(
    db: &PgPool,
    status: &str,
    starts_at_offset: &str,
) -> (Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let slot_id = Uuid::new_v4();

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
    .bind(format!("noshow-route-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet NoShow Route Test', 'dentaire')",
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
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, 'Dr NoShow Route', true, false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'NoShowRoute')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(&format!(
        "INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, now() {starts_at_offset}, now() {starts_at_offset} + interval '30 minutes', 'booked')",
    ))
    .bind(slot_id)
    .bind(provider_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(&format!(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, slot_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, $5, now() {starts_at_offset}, now() {starts_at_offset} + interval '30 minutes', $6, 'détartrage')",
    ))
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .bind(slot_id)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (cabinet_id, prac_id, prac_user_id, appt_id, slot_id)
}

/// RDV déjà passé (`starts_at` -2h) — cas nominal des tests existants.
async fn insert_fixture(db: &PgPool, status: &str) -> (Uuid, Uuid, Uuid, Uuid, Uuid) {
    insert_fixture_at(db, status, "- interval '2 hours'").await
}

async fn cleanup_fixture(
    seed_db: &PgPool,
    app_db: &PgPool,
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    appt_id: Uuid,
    slot_id: Uuid,
) {
    let mut tx = app_db.begin().await.unwrap();
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
    tx.commit().await.ok();

    let mut tx = seed_db.begin().await.unwrap();
    sqlx::query("DELETE FROM availability_slot WHERE id = $1")
        .bind(slot_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
        .bind(cabinet_id)
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

async fn post_no_show(
    server: axum::Router,
    appt_id: Uuid,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/appointments/{}/no-show", appt_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(json!({}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    (status, body)
}

/// `confirmed → no_show` : 200, créneau libéré, entrée `audit_log` posée.
#[tokio::test]
async fn no_show_from_confirmed_returns_200_frees_slot_and_audits() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, slot_id) =
        insert_fixture(&seed_db, "confirmed").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id);
    let (status, body) = post_no_show(app(state), appt_id, &token).await;

    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["status"], "no_show");

    let slot_status: String =
        sqlx::query_scalar("SELECT status FROM availability_slot WHERE id = $1")
            .bind(slot_id)
            .fetch_one(&seed_db)
            .await
            .unwrap();
    assert_eq!(
        slot_status, "open",
        "le créneau doit être libéré, pas verrouillé indéfiniment"
    );

    let mut tx = app_db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let audit_action: String = sqlx::query(
        "SELECT action FROM audit_log WHERE entity_id = $1 AND entity = 'appointment' \
         ORDER BY occurred_at DESC LIMIT 1",
    )
    .bind(appt_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap()
    .try_get("action")
    .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(audit_action, "no_show_appointment");

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
        slot_id,
    )
    .await;
}

/// Un RDV déjà `cancelled` reste refusé — pas de réouverture.
#[tokio::test]
async fn no_show_from_cancelled_returns_409() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, slot_id) =
        insert_fixture(&seed_db, "cancelled").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id);
    let (status, body) = post_no_show(app(state), appt_id, &token).await;

    assert_eq!(status, StatusCode::CONFLICT, "body: {body}");
    assert_eq!(body["code"], "invalid_status");

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
        slot_id,
    )
    .await;
}

/// RDV `confirmed` encore à venir (`starts_at` +2h) → `409 too_early`, pas de
/// transition (#4369 : un no-show désigne un patient absent à un RDV dû, pas
/// un rendez-vous futur).
#[tokio::test]
async fn no_show_from_confirmed_future_appointment_returns_409_too_early() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, slot_id) =
        insert_fixture_at(&seed_db, "confirmed", "+ interval '2 hours'").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id);
    let (status, body) = post_no_show(app(state), appt_id, &token).await;

    assert_eq!(status, StatusCode::CONFLICT, "body: {body}");
    assert_eq!(body["code"], "too_early");

    let mut tx = app_db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let appt_status: String = sqlx::query_scalar("SELECT status FROM appointment WHERE id = $1")
        .bind(appt_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(
        appt_status, "confirmed",
        "aucune transition ne doit avoir eu lieu"
    );

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
        slot_id,
    )
    .await;
}

/// Un RDV déjà `done` reste refusé — pas de réouverture après consultation réalisée.
#[tokio::test]
async fn no_show_from_done_returns_409() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, slot_id) =
        insert_fixture(&seed_db, "done").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id);
    let (status, body) = post_no_show(app(state), appt_id, &token).await;

    assert_eq!(status, StatusCode::CONFLICT, "body: {body}");
    assert_eq!(body["code"], "invalid_status");

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
        slot_id,
    )
    .await;
}
