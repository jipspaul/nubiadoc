//! Tests d'intégration : découpage automatique en séances + créneaux + RDV
//! (#7173, DP-F16.b).
//!
//! - `POST /v1/cabinet/treatment-plans/:id/sessions/propose` :
//!   1. actes du plan répartis en séances persistées (durée par défaut).
//!   2. `cabinet_session_rules.max_duration_min` scinde en plusieurs séances.
//!   3. aucun acte à répartir → 422.
//! - `POST /v1/cabinet/treatment-plans/:id/sessions/:sessionId/slots` :
//!   4. créneaux ouverts assez longs du praticien du plan, trop courts exclus.
//! - `POST /v1/cabinet/treatment-plans/:id/sessions/:sessionId/schedule` :
//!   5. RDV créé et lié à la séance (`appointment_id` + statut `scheduled`).
//!   6. séance déjà planifiée → 409.
//!   7. créneau plus court que la séance → 422.

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

const JWT_SECRET: &str = "test-secret-treatment-sessions-propose";

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

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
    patient_id: Uuid,
    practitioner_id: Uuid,
    plan_id: Uuid,
}

/// Cabinet + app_user + practitioner + patient + treatment_plan (practitioner
/// résolu, requis par `slots`/`schedule`) + un appointment passé (garde §14).
async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let plan_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("tsp-prac+{}@nubia.test", user_id))
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
         VALUES ($1, 'Cabinet Session Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Marie', 'Durand')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO treatment_plan (id, cabinet_id, patient_id, practitioner_id, title, status) \
         VALUES ($1, $2, $3, $4, 'Plan test', 'draft')",
    )
    .bind(plan_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Appointment passé : le praticien a consulté ce patient (garde §14, #4400).
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', now() - interval '30 minutes', 'done', 'contrôle')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        user_id,
        patient_id,
        practitioner_id,
        plan_id,
    }
}

/// Insère une phase + un devis + `n` `quote_item` (30 min chacun par défaut
/// côté algorithme) rattachés à cette phase. Retourne leurs ids.
async fn insert_quote_items(db: &PgPool, f: &Fixtures, n: usize) -> Vec<Uuid> {
    let phase_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO treatment_phase (id, cabinet_id, plan_id, position, title, status) \
         VALUES ($1, $2, $3, 1, 'Phase 1', 'requested')",
    )
    .bind(phase_id)
    .bind(f.cabinet_id)
    .bind(f.plan_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status) VALUES ($1, $2, $3, 'draft')",
    )
    .bind(quote_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    let mut ids = Vec::with_capacity(n);
    for i in 0..n {
        let item_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO quote_item (id, cabinet_id, quote_id, phase_id, label, unit_amount) \
             VALUES ($1, $2, $3, $4, $5, 10000)",
        )
        .bind(item_id)
        .bind(f.cabinet_id)
        .bind(quote_id)
        .bind(phase_id)
        .bind(format!("Acte {}", i))
        .execute(&mut *tx)
        .await
        .unwrap();
        ids.push(item_id);
    }

    tx.commit().await.unwrap();
    ids
}

/// Séance `planned` insérée directement (sans passer par `propose`), pour
/// tester `slots`/`schedule` isolément.
async fn insert_session(db: &PgPool, f: &Fixtures, position: i32, duration_min: i32) -> Uuid {
    let session_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO treatment_session (id, cabinet_id, plan_id, position, duration_min, status) \
         VALUES ($1, $2, $3, $4, $5, 'planned')",
    )
    .bind(session_id)
    .bind(f.cabinet_id)
    .bind(f.plan_id)
    .bind(position)
    .bind(duration_min)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    session_id
}

/// Créneau `open` du praticien du cabinet, `minutes_from_now` dans le futur,
/// de durée `duration_min`.
async fn insert_availability_slot(
    db: &PgPool,
    f: &Fixtures,
    minutes_from_now: i64,
    duration_min: i64,
) -> Uuid {
    let slot_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO availability_slot \
         (id, cabinet_id, practitioner_id, starts_at, ends_at, status, online_booking) \
         VALUES ($1, $2, $3, \
                 now() + ($4 * interval '1 minute'), \
                 now() + ($4 * interval '1 minute') + ($5 * interval '1 minute'), \
                 'open', false)",
    )
    .bind(slot_id)
    .bind(f.cabinet_id)
    .bind(f.practitioner_id)
    .bind(minutes_from_now as f64)
    .bind(duration_min as f64)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    slot_id
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM availability_slot WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_session_act WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_session WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM treatment_phase WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_session_rules WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_plan WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : propose → séance(s) persistées avec durée par défaut ───────────

#[tokio::test]
async fn propose_sessions_returns_201_and_persists() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let item_ids = insert_quote_items(&db, &f, 2).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/treatment-plans/{}/sessions/propose",
                    f.plan_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let sessions = v["sessions"].as_array().unwrap();
    assert_eq!(sessions.len(), 1);
    assert_eq!(sessions[0]["duration_min"], 60);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let acts_count: i64 = sqlx::query(
        "SELECT count(*) AS n FROM treatment_session_act WHERE quote_item_id = ANY($1)",
    )
    .bind(&item_ids)
    .fetch_one(&mut *tx)
    .await
    .unwrap()
    .try_get("n")
    .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(acts_count, 2);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : max_duration_min scinde en plusieurs séances ────────────────────

#[tokio::test]
async fn propose_sessions_respects_max_duration_rule() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    insert_quote_items(&db, &f, 2).await;

    sqlx::query("INSERT INTO cabinet_session_rules (cabinet_id, max_duration_min) VALUES ($1, 30)")
        .bind(f.cabinet_id)
        .execute(&db)
        .await
        .unwrap();

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/treatment-plans/{}/sessions/propose",
                    f.plan_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let sessions = v["sessions"].as_array().unwrap();
    assert_eq!(sessions.len(), 2);
    assert_eq!(sessions[0]["duration_min"], 30);
    assert_eq!(sessions[1]["duration_min"], 30);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : aucun acte à répartir → 422 ─────────────────────────────────────

#[tokio::test]
async fn propose_sessions_no_acts_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/treatment-plans/{}/sessions/propose",
                    f.plan_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 4 : slots proposés — trop courts exclus ──────────────────────────────

#[tokio::test]
async fn propose_session_slots_filters_by_duration() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let session_id = insert_session(&db, &f, 1, 30).await;
    let long_enough = insert_availability_slot(&db, &f, 60, 45).await;
    insert_availability_slot(&db, &f, 120, 20).await; // trop court, exclu

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/treatment-plans/{}/sessions/{}/slots",
                    f.plan_id, session_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let slots = v["slots"].as_array().unwrap();
    assert_eq!(slots.len(), 1);
    assert_eq!(
        slots[0]["slot_id"].as_str().unwrap(),
        long_enough.to_string()
    );

    cleanup_fixtures(&db, &f).await;
}

// ── Test 5 : schedule → RDV créé et lié à la séance ──────────────────────────

#[tokio::test]
async fn schedule_session_creates_and_links_appointment() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let session_id = insert_session(&db, &f, 1, 30).await;
    let slot_id = insert_availability_slot(&db, &f, 60, 30).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/treatment-plans/{}/sessions/{}/schedule",
                    f.plan_id, session_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({ "slot_id": slot_id }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let appointment_id: Uuid = v["appointment_id"].as_str().unwrap().parse().unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    let appt =
        sqlx::query("SELECT patient_id, practitioner_id, status FROM appointment WHERE id = $1")
            .bind(appointment_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    let appt_patient_id: Uuid = appt.try_get("patient_id").unwrap();
    let appt_practitioner_id: Uuid = appt.try_get("practitioner_id").unwrap();
    let appt_status: String = appt.try_get("status").unwrap();
    assert_eq!(appt_patient_id, f.patient_id);
    assert_eq!(appt_practitioner_id, f.practitioner_id);
    assert_eq!(appt_status, "requested");

    let session_row =
        sqlx::query("SELECT appointment_id, status FROM treatment_session WHERE id = $1")
            .bind(session_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    let session_appointment_id: Option<Uuid> = session_row.try_get("appointment_id").unwrap();
    let session_status: String = session_row.try_get("status").unwrap();
    tx.commit().await.unwrap();

    assert_eq!(session_appointment_id, Some(appointment_id));
    assert_eq!(session_status, "scheduled");

    cleanup_fixtures(&db, &f).await;
}

// ── Test 6 : séance déjà planifiée → 409 ─────────────────────────────────────

#[tokio::test]
async fn schedule_session_already_scheduled_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let session_id = insert_session(&db, &f, 1, 30).await;
    let slot_id = insert_availability_slot(&db, &f, 60, 30).await;
    let second_slot_id = insert_availability_slot(&db, &f, 180, 30).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let first = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/treatment-plans/{}/sessions/{}/schedule",
                    f.plan_id, session_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({ "slot_id": slot_id }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::CREATED);

    let second = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/treatment-plans/{}/sessions/{}/schedule",
                    f.plan_id, session_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({ "slot_id": second_slot_id }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::CONFLICT);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 7 : créneau plus court que la séance → 422 ──────────────────────────

#[tokio::test]
async fn schedule_session_slot_too_short_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let session_id = insert_session(&db, &f, 1, 60).await;
    let slot_id = insert_availability_slot(&db, &f, 60, 30).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/treatment-plans/{}/sessions/{}/schedule",
                    f.plan_id, session_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({ "slot_id": slot_id }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, &f).await;
}
