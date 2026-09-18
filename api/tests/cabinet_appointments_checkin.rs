//! Tests d'intégration : POST /v1/cabinet/appointments/:id/checkin (#6411)
//!
//! Route cabinet (secretary+) qui manque d'équivalent : jusqu'ici seul
//! `POST /v1/appointments/:id/checkin` (token patient) existait, cf.
//! tests/appointments_checkin.rs.

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

const JWT_SECRET: &str = "test-secret-appt-cabinet-checkin";

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
            // claim, checkin renvoie 404 (cf. appointments_checkin.rs::cabinet_checkin_appointment).
            "secretariat_id": secretariat_id,
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

/// Insère les fixtures minimales : cabinet, praticien, provider, secretariat,
/// provider_secretariat(active), patient et RDV.
/// `status` est le statut initial du RDV inséré.
/// Retourne `(cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id)`.
async fn insert_fixture(db: &PgPool, status: &str) -> (Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    // Positionne le GUC tenant avant les INSERTs (tenant_isolation est sur {public}).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("cabinet-checkin-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet Checkin Test', 'dentaire')",
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
         VALUES ($1, $2, $3, $4, 'Dr Checkin', true, false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec Checkin Test')",
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
         VALUES ($1, $2, 'Patient', 'Checkin')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() + interval '1 hour', now() + interval '90 minutes', $5, 'détartrage')",
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

    (cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id)
}

/// Variante de `insert_fixture` avec un `starts_at` décalé de
/// `minutes_from_now` minutes par rapport à `now()` (créneau de 30 min) —
/// #7248/#6770/#6912 : reproduit un RDV hors de la fenêtre de check-in
/// cabinet `[starts_at − 2 h, ends_at + 1 h]` (demain, la semaine prochaine,
/// dans 15 mois) ou aux bords de celle-ci.
async fn insert_fixture_at(
    db: &PgPool,
    status: &str,
    minutes_from_now: i64,
) -> (Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let starts_at = chrono::Utc::now() + chrono::Duration::minutes(minutes_from_now);
    let ends_at = starts_at + chrono::Duration::minutes(30);

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
    .bind(format!("cabinet-checkin-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet Checkin Test', 'dentaire')",
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
         VALUES ($1, $2, $3, $4, 'Dr Checkin', true, false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec Checkin Test')",
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
         VALUES ($1, $2, 'Patient', 'Checkin')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'détartrage')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id)
}

async fn cleanup_fixture(
    seed_db: &PgPool,
    app_db: &PgPool,
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    appt_id: Uuid,
) {
    // audit_log, checkin_event et appointment sont sous RLS nubia_app avec cabinet GUC.
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
    sqlx::query("DELETE FROM checkin_event WHERE appointment_id = $1")
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

    // Les autres tables fixtures sont accessibles via nubia_seed.
    let mut tx = seed_db.begin().await.unwrap();
    // secretariat / provider_secretariat FORCE la RLS : positionner le GUC tenant
    // pour que les DELETE ci-dessous voient bien leurs lignes.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
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

// ── Test 1 : secrétaire, RDV confirmed → 200 + status checked_in ────────────

#[tokio::test]
async fn cabinet_checkin_secretary_confirmed_returns_200() {
    if !db_available() {
        return;
    }

    let seed_db = seed_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id) =
        insert_fixture(&seed_db, "confirmed").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id, secretariat_id);
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/appointments/{}/checkin", appt_id))
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
    assert_eq!(body["status"], "checked_in");
    assert_eq!(body["appointment_id"], appt_id.to_string());

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
    )
    .await;
}

// ── Test 2 : RDV encore requested (pas confirmed) → 409 invalid_status ──────

#[tokio::test]
async fn cabinet_checkin_not_confirmed_returns_409() {
    if !db_available() {
        return;
    }

    let seed_db = seed_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id) =
        insert_fixture(&seed_db, "requested").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id, secretariat_id);
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/appointments/{}/checkin", appt_id))
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
    assert_eq!(body["code"], "invalid_status");

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
    )
    .await;
}

// ── Test 3 : token patient → 403 (route cabinet réservée au pro secretary+) ─

#[tokio::test]
async fn cabinet_checkin_patient_token_returns_403() {
    if !db_available() {
        return;
    }

    let seed_db = seed_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id) =
        insert_fixture(&seed_db, "confirmed").await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    // `secretariat_id` non pertinent ici : le token patient est rejeté (403)
    // par l'extracteur avant toute requête scopée au secrétariat.
    let _ = secretariat_id;
    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let token = make_patient_token(patient_user_id, patient_account_id);
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/appointments/{}/checkin", appt_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
    )
    .await;
}

// ── Test 4 : RDV confirmed dans 4 jours (hors fenêtre ±1 jour) → 409 too_early (#7248) ─

#[tokio::test]
async fn cabinet_checkin_confirmed_next_week_returns_409_too_early() {
    if !db_available() {
        return;
    }

    let seed_db = seed_pool().await;
    let app_db = app_pool().await;

    // J+4 : hors de la fenêtre glissante now() ± 1 jour partagée par
    // get_waiting_room/call_next_patient/la queue patient — un check-in ici
    // produirait un RDV `checked_in` invisible des trois vues de la file.
    let (cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id) =
        insert_fixture_at(&seed_db, "confirmed", 96 * 60).await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id, secretariat_id);
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/appointments/{}/checkin", appt_id))
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
    assert_eq!(body["code"], "too_early");

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
    )
    .await;
}

/// Helper : POST /v1/cabinet/appointments/:id/checkin avec un token secrétaire,
/// renvoie `(status HTTP, body JSON)`.
async fn cabinet_checkin(
    app_db: &PgPool,
    cabinet_id: Uuid,
    secretariat_id: Uuid,
    appt_id: Uuid,
) -> (StatusCode, serde_json::Value) {
    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);
    let token = make_secretary_token(Uuid::new_v4(), cabinet_id, secretariat_id);
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/appointments/{}/checkin", appt_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, body)
}

// ── Test 5 : RDV confirmed dans 15 mois → 409 too_early (#6770) ─────────────
//
// Repro QA-20260908-26 : le RDV du 2027-12-09 passait `checked_in` au
// comptoir, puis `start` lui faisait confiance → `done` en 2027, « dernière
// visite » dans le futur et patient qui ne peut plus annuler.

#[tokio::test]
async fn cabinet_checkin_confirmed_in_15_months_returns_409_too_early() {
    if !db_available() {
        return;
    }

    let seed_db = seed_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id) =
        insert_fixture_at(&seed_db, "confirmed", 15 * 30 * 24 * 60).await;

    let (status, body) = cabinet_checkin(&app_db, cabinet_id, secretariat_id, appt_id).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "too_early");

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
    )
    .await;
}

// ── Test 6 : RDV confirmed demain (+20 h) → 409 too_early (#6912) ───────────
//
// Repro QA-20260913-1 : un RDV de demain matin, enregistré « arrivé » ce soir,
// passait `checked_in` (la fenêtre glissante ±1 jour de #7248 l'acceptait)
// alors que le check-in patient le refusait (`too_early`).

#[tokio::test]
async fn cabinet_checkin_confirmed_tomorrow_returns_409_too_early() {
    if !db_available() {
        return;
    }

    let seed_db = seed_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id) =
        insert_fixture_at(&seed_db, "confirmed", 20 * 60).await;

    let (status, body) = cabinet_checkin(&app_db, cabinet_id, secretariat_id, appt_id).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "too_early");

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
    )
    .await;
}

// ── Test 7 : arrivée en avance (créneau dans 90 min) → 200 ─────────────────
//
// Le comptoir a plus de latitude que le patient (±60 min) : jusqu'à 2 h
// avant le créneau.

#[tokio::test]
async fn cabinet_checkin_early_arrival_within_2h_returns_200() {
    if !db_available() {
        return;
    }

    let seed_db = seed_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id) =
        insert_fixture_at(&seed_db, "confirmed", 90).await;

    let (status, body) = cabinet_checkin(&app_db, cabinet_id, secretariat_id, appt_id).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "checked_in");

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
    )
    .await;
}

// ── Test 8 : retardataire (créneau fini depuis 20 min) → 200 ────────────────
//
// starts_at − 80 min / ends_at − 50 min : hors fenêtre patient (±60 min), mais
// dans la fenêtre cabinet (jusqu'à ends_at + 1 h).

#[tokio::test]
async fn cabinet_checkin_late_arrival_within_1h_after_slot_returns_200() {
    if !db_available() {
        return;
    }

    let seed_db = seed_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id) =
        insert_fixture_at(&seed_db, "confirmed", -80).await;

    let (status, body) = cabinet_checkin(&app_db, cabinet_id, secretariat_id, appt_id).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "checked_in");

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
    )
    .await;
}

// ── Test 9 : créneau fini depuis 3 h → 409 out_of_window ────────────────────

#[tokio::test]
async fn cabinet_checkin_long_past_returns_409_out_of_window() {
    if !db_available() {
        return;
    }

    let seed_db = seed_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_id, prac_user_id, appt_id, secretariat_id) =
        insert_fixture_at(&seed_db, "confirmed", -(3 * 60 + 30)).await;

    let (status, body) = cabinet_checkin(&app_db, cabinet_id, secretariat_id, appt_id).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "out_of_window");

    cleanup_fixture(
        &seed_db,
        &app_db,
        cabinet_id,
        prac_id,
        prac_user_id,
        appt_id,
    )
    .await;
}
