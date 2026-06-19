//! Tests d'intégration : PATCH /v1/appointments/:id

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

const JWT_SECRET: &str = "test-jwt-secret-appointments-patch";

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

/// Insère le jeu de fixtures minimal : cabinet + praticien + patient + RDV.
/// Retourne (cabinet_id, prac_id, patient_id, appt_id).
async fn insert_fixture(
    db: &PgPool,
    prac_user_id: Uuid,
    patient_account_id: Uuid,
    status: &str,
    starts_at_sql: &str,
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
        .bind(format!("Cabinet Patch {}", cabinet_id))
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
         VALUES ($1, $2, 'Test', 'Patch', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(&format!(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, {starts_at_sql}, {starts_at_sql} + INTERVAL '30 min', $5, 'original motif')"
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

async fn cleanup(db: &PgPool, cabinet_id: Uuid, patient_id: Uuid, prac_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM audit_log WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
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
    tx.commit().await.ok();
}

// ── Test 1 : happy path → 200 { appointment_id, status } ─────────────────────

#[tokio::test]
async fn patch_appointment_happy_path_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let patient_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("patch-happy+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Patch', 'Happy')",
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
    .bind(format!("patch-happy-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // starts_at dans 48 h → dans les délais (> 24 h).
    let (cabinet_id, prac_id, patient_id, appt_id) = insert_fixture(
        &db,
        prac_user_id,
        patient_account_id,
        "confirmed",
        "now() + interval '48 hours'",
    )
    .await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let new_starts_at = (chrono::Utc::now() + chrono::Duration::hours(72)).to_rfc3339();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/appointments/{}", appt_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(patient_user_id, patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_vec(
                        &json!({"starts_at": new_starts_at, "motif": "nouveau motif"}),
                    )
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(v["appointment_id"], appt_id.to_string());
    assert!(v["status"].is_string());

    cleanup(&db, cabinet_id, patient_id, prac_id).await;
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

// ── Test 2 : hors délai → 409 { "error": "too_late" } ───────────────────────

#[tokio::test]
async fn patch_appointment_too_late_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let patient_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("patch-toolate+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Patch', 'TooLate')",
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
    .bind(format!("patch-toolate-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // starts_at dans 12 h → hors délai (< 24 h).
    let (cabinet_id, prac_id, patient_id, appt_id) = insert_fixture(
        &db,
        prac_user_id,
        patient_account_id,
        "confirmed",
        "now() + interval '12 hours'",
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
                .method("PATCH")
                .uri(format!("/v1/appointments/{}", appt_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(patient_user_id, patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_vec(&json!({"motif": "nouveau motif"})).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CONFLICT);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["error"], "too_late");

    cleanup(&db, cabinet_id, patient_id, prac_id).await;
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

// ── Test : wrong patient → 404 (anti-énumération, RLS policy 0029) ──────────

#[tokio::test]
async fn patch_appointment_wrong_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let patient_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("patch-wrongpt+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Patch', 'WrongPt')",
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
    .bind(format!("patch-wrongpt-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // RDV appartenant à patient_account_id, starts dans 48 h.
    let (cabinet_id, prac_id, patient_id, appt_id) = insert_fixture(
        &db,
        prac_user_id,
        patient_account_id,
        "confirmed",
        "now() + interval '48 hours'",
    )
    .await;

    // JWT d'un autre patient — ne possède pas ce RDV.
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
                .method("PATCH")
                .uri(format!("/v1/appointments/{}", appt_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(wrong_user_id, wrong_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_vec(&json!({"motif": "intrus"})).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    // RLS policy 0029 masque le RDV → 404 (anti-énumération, pas 403).
    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    cleanup(&db, cabinet_id, patient_id, prac_id).await;
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

// ── Test : status invalide (done) → 409 { "error": "invalid_status" } ───────

#[tokio::test]
async fn patch_appointment_invalid_status_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let patient_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("patch-badstatus+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Patch', 'BadStatus')",
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
    .bind(format!("patch-badstatus-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // RDV avec status='done' — ne peut pas être modifié.
    let (cabinet_id, prac_id, patient_id, appt_id) = insert_fixture(
        &db,
        prac_user_id,
        patient_account_id,
        "done",
        "now() + interval '48 hours'",
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
                .method("PATCH")
                .uri(format!("/v1/appointments/{}", appt_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(patient_user_id, patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_vec(&json!({"motif": "modif refusée"})).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CONFLICT);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["error"], "invalid_status");

    cleanup(&db, cabinet_id, patient_id, prac_id).await;
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

// ── Test 3 : conflit créneau → 409 { "code": "slot_taken" } ─────────────────

#[tokio::test]
async fn patch_appointment_slot_taken_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let patient_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("patch-slot+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Patch', 'Slot')",
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
    .bind(format!("patch-slot-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // Appt A : starts dans 48 h (celui qu'on va PATCH).
    let (cabinet_id, prac_id, patient_id, appt_a_id) = insert_fixture(
        &db,
        prac_user_id,
        patient_account_id,
        "confirmed",
        "now() + interval '48 hours'",
    )
    .await;

    // Appt B : même praticien, starts dans 50 h (occupe le créneau cible).
    let appt_b_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, \
                 now() + interval '50 hours', \
                 now() + interval '50 hours' + INTERVAL '30 min', \
                 'confirmed', 'blocking appt')",
    )
    .bind(appt_b_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // PATCH appt A pour qu'il chevauche appt B (now + 50h + 15min → overlap).
    let conflict_starts_at =
        (chrono::Utc::now() + chrono::Duration::hours(50) + chrono::Duration::minutes(15))
            .to_rfc3339();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/appointments/{}", appt_a_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(patient_user_id, patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_vec(&json!({"starts_at": conflict_starts_at})).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CONFLICT);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "slot_taken");

    cleanup(&db, cabinet_id, patient_id, prac_id).await;
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
