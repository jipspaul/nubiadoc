//! Tests d'intégration : PATCH /v1/cabinet/appointments/:id {status:"no_show"} (#3733)
//! + rejet `409 too_early` pour un RDV encore à venir (#4369).

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

const JWT_SECRET: &str = "test-secret-appt-noshow";

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

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid, secretariat_id: Uuid) -> String {
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
            // R10 : la secrétaire est scopée à un secrétariat actif — sans ce
            // claim, no-show renvoie 404 (cf. scheduling.rs::no_show_appointment).
            "secretariat_id": secretariat_id,
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
/// La secrétaire est scopée au secrétariat via `provider_secretariat(active)` :
/// on relie le praticien du RDV à un secrétariat, dont l'id est renvoyé pour
/// alimenter le claim `secretariat_id` du token (R10).
/// Retourne `(cabinet_id, prac_id, prac_user_id, appt_id, slot_id, secretariat_id)`.
async fn insert_fixture_at(
    db: &PgPool,
    status: &str,
    starts_at_offset: &str,
) -> (Uuid, Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();
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
    .bind(format!("noshow-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet NoShow Test', 'dentaire')",
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
         VALUES ($1, $2, $3, $4, 'Dr NoShow', true, false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec NoShow Test')",
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

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'NoShow')",
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

    (
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
        slot_id,
        secretariat_id,
    )
}

/// RDV déjà passé (`starts_at` -2h) — cas nominal des tests existants.
async fn insert_fixture(db: &PgPool, status: &str) -> (Uuid, Uuid, Uuid, Uuid, Uuid, Uuid) {
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
    // secretariat / provider_secretariat FORCE la RLS : positionner le GUC tenant
    // pour que les DELETE ci-dessous voient bien leurs lignes.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM availability_slot WHERE id = $1")
        .bind(slot_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query(
        "DELETE FROM provider_secretariat WHERE provider_id IN \
         (SELECT id FROM provider WHERE cabinet_id = $1)",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .ok();
    sqlx::query("DELETE FROM secretariat WHERE cabinet_id = $1")
        .bind(cabinet_id)
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

async fn patch_status(
    server: axum::Router,
    appt_id: Uuid,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let response = server
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/appointments/{}", appt_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(json!({"status": "no_show"}).to_string()))
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

/// Repro exacte de #3733 : un RDV `confirmed` jamais checked-in doit pouvoir
/// être clôturé no_show par le cabinet (au lieu du 409 invalid_status
/// d'avant), et le créneau doit être libéré (plus de verrou indéfini).
#[tokio::test]
async fn noshow_from_confirmed_returns_200_and_frees_slot() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, slot_id, secretariat_id) =
        insert_fixture(&seed_db, "confirmed").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id, secretariat_id);
    let (status, body) = patch_status(app(state), appt_id, &token).await;

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

/// Même repro, depuis `requested` (jamais confirmé non plus).
#[tokio::test]
async fn noshow_from_requested_returns_200() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, slot_id, secretariat_id) =
        insert_fixture(&seed_db, "requested").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id, secretariat_id);
    let (status, body) = patch_status(app(state), appt_id, &token).await;

    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["status"], "no_show");

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

/// Repro exacte de #3858 : un RDV `in_progress` (appelé via call-next, sans
/// consultation_session — le patient ne s'est jamais présenté) doit pouvoir
/// être clôturé no_show, au lieu du cul-de-sac où la seule sortie était de
/// fabriquer une consultation start→complete→done (no-show comptabilisé à
/// tort comme consultation réalisée).
#[tokio::test]
async fn noshow_from_in_progress_returns_200() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, slot_id, secretariat_id) =
        insert_fixture(&seed_db, "in_progress").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id, secretariat_id);
    let (status, body) = patch_status(app(state), appt_id, &token).await;

    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["status"], "no_show");

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
/// transition (#4369).
#[tokio::test]
async fn noshow_from_confirmed_future_appointment_returns_409_too_early() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, slot_id, secretariat_id) =
        insert_fixture_at(&seed_db, "confirmed", "+ interval '2 hours'").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id, secretariat_id);
    let (status, body) = patch_status(app(state), appt_id, &token).await;

    assert_eq!(status, StatusCode::CONFLICT, "body: {body}");
    assert_eq!(body["code"], "too_early");

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

/// Un RDV déjà terminal (`cancelled`) reste refusé — pas de réouverture.
#[tokio::test]
async fn noshow_from_cancelled_returns_409() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, slot_id, secretariat_id) =
        insert_fixture(&seed_db, "cancelled").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id, secretariat_id);
    let (status, body) = patch_status(app(state), appt_id, &token).await;

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
