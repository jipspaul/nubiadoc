//! Tests d'intégration : PATCH /v1/cabinet/appointments/:id (#6548)
//!
//! Un body sans aucun champ reconnu (vide ou avec un champ inconnu comme
//! `slot_id`/`nawak`) ne doit ni notifier le patient d'un changement de motif
//! fantôme, ni modifier le RDV. Un champ inconnu doit être rejeté en 422
//! (`deny_unknown_fields`), même garde-fou que `PatchNotificationPreferencesBody`/
//! `PatchMeNotificationPreferencesBody`.

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

const JWT_SECRET: &str = "test-secret-appt-patch-no-notify";

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
            "secretariat_id": secretariat_id,
            "exp": exp,
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère cabinet + praticien + patient (avec `app_user_id`, pour que la
/// notification passe par `notify_user`) + slot `booked` + RDV `confirmed`,
/// `starts_at` dans le passé (2h) et un `motif` initial non vide.
/// Retourne `(cabinet_id, prac_id, prac_user_id, patient_user_id, appt_id, slot_id, secretariat_id)`.
async fn insert_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
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
    .bind(format!("patch-no-notify-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!(
        "patch-no-notify-patient+{}@nubia.test",
        patient_user_id
    ))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet Patch NoNotify Test', 'dentaire')",
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
         VALUES ($1, $2, $3, $4, 'Dr PatchNoNotify', true, false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec PatchNoNotify Test')",
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
        "INSERT INTO patient (id, cabinet_id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, $3, 'Patient', 'PatchNoNotify')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO availability_slot (id, provider_id, cabinet_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, now() - interval '2 hours', now() - interval '2 hours' + interval '30 minutes', 'booked')",
    )
    .bind(slot_id)
    .bind(provider_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, slot_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, $5, now() - interval '2 hours', now() - interval '2 hours' + interval '30 minutes', 'confirmed', 'détartrage')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .bind(slot_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_user_id,
        appt_id,
        slot_id,
        secretariat_id,
    )
}

async fn cleanup_fixture(
    seed_db: &PgPool,
    app_db: &PgPool,
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    patient_user_id: Uuid,
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

    sqlx::query("DELETE FROM notification WHERE app_user_id = $1")
        .bind(patient_user_id)
        .execute(seed_db)
        .await
        .ok();

    let mut tx = seed_db.begin().await.unwrap();
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(patient_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

async fn patch_body(
    server: axum::Router,
    appt_id: Uuid,
    token: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let response = server
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/appointments/{}", appt_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null)
    };
    (status, body)
}

/// Repro exacte de #6548 : un body vide (aucun champ reconnu porté) est un
/// no-op — 200, RDV inchangé, et surtout AUCUNE notification
/// `appointment_motif_changed` envoyée au patient.
#[tokio::test]
async fn patch_empty_body_is_noop_and_does_not_notify() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_user_id, appt_id, slot_id, secretariat_id) =
        insert_fixture(&seed_db).await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id, secretariat_id);
    let (status, body) = patch_body(app(state), appt_id, &token, json!({})).await;

    assert_eq!(status, StatusCode::OK, "body: {body}");

    let motif: String = sqlx::query_scalar("SELECT motif FROM appointment WHERE id = $1")
        .bind(appt_id)
        .fetch_one(&seed_db)
        .await
        .unwrap();
    assert_eq!(motif, "détartrage", "le motif ne doit pas avoir bougé");

    let notif_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM notification WHERE app_user_id = $1 AND kind = 'appointment_motif_changed'",
    )
    .bind(patient_user_id)
    .fetch_one(&seed_db)
    .await
    .unwrap();
    assert_eq!(
        notif_count, 0,
        "un PATCH sans aucun champ reconnu ne doit jamais notifier un changement de motif fantôme"
    );

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_user_id,
        appt_id,
        slot_id,
    )
    .await;
}

/// Un champ inconnu (ex. `slot_id`, qui n'existe que sur la création) doit
/// être refusé en 422 — `deny_unknown_fields` — plutôt que silencieusement
/// ignoré par serde comme avant #6548.
#[tokio::test]
async fn patch_unknown_field_is_rejected_422() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_user_id, appt_id, slot_id, secretariat_id) =
        insert_fixture(&seed_db).await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id, secretariat_id);
    let (status, body) = patch_body(
        app(state),
        appt_id,
        &token,
        json!({"slot_id": Uuid::new_v4()}),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "body: {body}");

    let notif_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM notification WHERE app_user_id = $1 AND kind = 'appointment_motif_changed'",
    )
    .bind(patient_user_id)
    .fetch_one(&seed_db)
    .await
    .unwrap();
    assert_eq!(notif_count, 0);

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_user_id,
        appt_id,
        slot_id,
    )
    .await;
}

/// Contrôle positif : un vrai changement de motif doit toujours notifier
/// (non-régression du comportement voulu par #6133).
#[tokio::test]
async fn patch_real_motif_change_still_notifies() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_user_id, appt_id, slot_id, secretariat_id) =
        insert_fixture(&seed_db).await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id, secretariat_id);
    let (status, body) = patch_body(
        app(state),
        appt_id,
        &token,
        json!({"motif": "consultation de contrôle"}),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "body: {body}");

    let notif_row = sqlx::query(
        "SELECT title FROM notification WHERE app_user_id = $1 AND kind = 'appointment_motif_changed'",
    )
    .bind(patient_user_id)
    .fetch_one(&seed_db)
    .await
    .unwrap();
    let title: String = notif_row.try_get("title").unwrap();
    assert_eq!(title, "Motif du rendez-vous modifié");

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_user_id,
        appt_id,
        slot_id,
    )
    .await;
}
