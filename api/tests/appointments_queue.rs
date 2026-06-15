//! Tests d'intégration : GET /v1/appointments/:id/queue

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

const JWT_SECRET: &str = "test-jwt-secret-appointments-queue";

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("SEED_DATABASE_URL").is_ok()
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

fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Crée cabinet + praticien + patient + RDV avec checkin_at optionnel.
/// Retourne (cabinet_id, prac_id, patient_id, appt_id).
async fn insert_fixture(
    db: &PgPool,
    prac_user_id: Uuid,
    patient_account_id: Uuid,
    status: &str,
    checkin_at_sql: Option<&str>,
) -> (Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Queue {}", cabinet_id))
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Test', 'Queue', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    let checkin_sql = checkin_at_sql.unwrap_or("NULL");
    sqlx::query(&format!(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif, checkin_at) \
         VALUES ($1, $2, $3, $4, now(), now() + INTERVAL '30 min', $5, 'test', {checkin_sql})"
    ))
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (cabinet_id, prac_id, patient_id, appt_id)
}

/// Insère un RDV supplémentaire (autre patient) avec checkin_at passé pour simuler file d'attente.
async fn insert_extra_appt(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_id: Uuid,
    slot_offset_min: i64,
    checkin_offset_min: i64,
) -> Uuid {
    let extra_patient_id = Uuid::new_v4();
    let extra_appt_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Extra', 'Patient')",
    )
    .bind(extra_patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(&format!(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif, checkin_at) \
         VALUES ($1, $2, $3, $4, \
           now() + INTERVAL '{slot_offset_min} min', \
           now() + INTERVAL '{slot_offset_min} min' + INTERVAL '30 min', \
           'checked_in', 'extra', \
           now() - INTERVAL '{checkin_offset_min} min')"
    ))
    .bind(extra_appt_id)
    .bind(cabinet_id)
    .bind(extra_patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    extra_appt_id
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM checkin_event WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

// ── Test auth scope : sans JWT → 401 ─────────────────────────────────────────

#[tokio::test]
async fn get_queue_no_jwt_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}/queue", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test auth scope : wrong patient → 404 (anti-énumération) ─────────────────

#[tokio::test]
async fn get_queue_wrong_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = seed_pool().await;
    let patient_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("queue-wrongpt+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Queue', 'WrongPt')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("queue-wrongpt-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // RDV appartenant à patient_account_id (checkin_at = now).
    let (cabinet_id, _prac_id, _patient_id, appt_id) = insert_fixture(
        &db,
        prac_user_id,
        patient_account_id,
        "checked_in",
        Some("now()"),
    )
    .await;

    // JWT d'un autre patient.
    let wrong_user_id = Uuid::new_v4();
    let wrong_account_id = Uuid::new_v4();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}/queue", appt_id))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(wrong_user_id, wrong_account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // RLS policy 0029 → 404 (anti-énumération).
    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    cleanup(&db, cabinet_id).await;
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(patient_account_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(patient_user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 1 : patient en tête de file → position = 1 ─────────────────────────

#[tokio::test]
async fn get_queue_position_1_when_no_prior_checkins() {
    if !db_available() {
        return;
    }
    let db = seed_pool().await;
    let patient_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("queue-pos1+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Queue', 'Pos1')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("queue-pos1-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // Patient checké maintenant, aucun autre avant lui → position 1.
    let (cabinet_id, _prac_id, _patient_id, appt_id) = insert_fixture(
        &db,
        prac_user_id,
        patient_account_id,
        "checked_in",
        Some("now()"),
    )
    .await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}/queue", appt_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(patient_user_id, patient_account_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(v["position"], 1_i64, "aucun patient avant → position 1");
    assert!(
        v["est_wait_min"].is_null(),
        "est_wait_min doit être null en MVP"
    );
    assert_eq!(v["status"], "waiting");

    cleanup(&db, cabinet_id).await;
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(patient_account_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(patient_user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : patient avec 2 checkins antérieurs → position = 3 ──────────────

#[tokio::test]
async fn get_queue_position_3_when_two_prior_checkins() {
    if !db_available() {
        return;
    }
    let db = seed_pool().await;
    let patient_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("queue-pos3+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Queue', 'Pos3')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("queue-pos3-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // Patient checké maintenant (dernier dans la file).
    let (cabinet_id, prac_id, _patient_id, appt_id) = insert_fixture(
        &db,
        prac_user_id,
        patient_account_id,
        "checked_in",
        Some("now()"),
    )
    .await;

    // 2 patients checkés AVANT lui (2 et 5 minutes avant).
    insert_extra_appt(&db, cabinet_id, prac_id, 35, 5).await;
    insert_extra_appt(&db, cabinet_id, prac_id, 65, 2).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}/queue", appt_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(patient_user_id, patient_account_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(v["position"], 3_i64, "2 patients avant → position 3");
    assert!(
        v["est_wait_min"].is_null(),
        "est_wait_min doit être null en MVP"
    );
    assert_eq!(v["status"], "waiting");

    cleanup(&db, cabinet_id).await;
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(patient_account_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(patient_user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}
