//! Tests d'intégration : décompte des séances programmées à la clôture
//! d'une consultation (#4120) — POST /v1/cabinet/consultations/:id/complete
//! incrémente treatment_phase.completed_sessions quand un acte de la séance
//! est rattaché (consultation_act.phase_id, migration 0203).
//!
//! Fichier dédié plutôt qu'un ajout à `cabinet_consultations_complete.rs`
//! (déjà 985 lignes, largement au-dessus du plafond absolu CLAUDE.md).

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

const JWT_SECRET: &str = "test-secret-consult-session-decrement";

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
    encode(
        &Header::default(),
        &json!({
            "sub": sub, "kind": "pro", "cabinet_id": cabinet_id,
            "role": "practitioner", "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
    practitioner_id: Uuid,
    patient_id: Uuid,
    appointment_id: Uuid,
    session_id: Uuid,
    plan_id: Uuid,
    phase_id: Uuid,
}

/// `planned` : `Some(n)` pose `planned_sessions = n` sur la phase (mécanisme
/// actif), `None` laisse la colonne NULL (mécanisme non utilisé — cas
/// régression du comportement historique).
async fn insert_fixtures(db: &PgPool, planned: Option<i32>) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appointment_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();
    let plan_id = Uuid::new_v4();
    let phase_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("session-decr-prac+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Session Decrement Test', 'dentaire')",
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
         VALUES ($1, $2, 'Serge', 'Ortho')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', now(), 'in_progress', 'suivi ortho')",
    )
    .bind(appointment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO consultation_session \
         (id, cabinet_id, appointment_id, practitioner_id, status) \
         VALUES ($1, $2, $3, $4, 'in_progress')",
    )
    .bind(session_id)
    .bind(cabinet_id)
    .bind(appointment_id)
    .bind(practitioner_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO treatment_plan (id, cabinet_id, patient_id, title, status) \
         VALUES ($1, $2, $3, 'Suivi ortho', 'in_progress')",
    )
    .bind(plan_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO treatment_phase \
         (id, cabinet_id, plan_id, position, title, status, planned_sessions, completed_sessions) \
         VALUES ($1, $2, $3, 1, 'Suivi mensuel', 'in_progress', $4, 0)",
    )
    .bind(phase_id)
    .bind(cabinet_id)
    .bind(plan_id)
    .bind(planned)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        user_id,
        practitioner_id,
        patient_id,
        appointment_id,
        session_id,
        plan_id,
        phase_id,
    }
}

async fn insert_act(db: &PgPool, f: &Fixtures, phase_id: Option<Uuid>) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO consultation_act \
         (cabinet_id, appointment_id, patient_id, practitioner_id, ccam_code, label, amount_cents, phase_id) \
         VALUES ($1, $2, $3, $4, 'HBLD001', 'Suivi', 2500, $5)",
    )
    .bind(f.cabinet_id)
    .bind(f.appointment_id)
    .bind(f.patient_id)
    .bind(f.practitioner_id)
    .bind(phase_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_session WHERE id = $1")
        .bind(f.session_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query(
        "DELETE FROM quote_item WHERE quote_id IN (SELECT id FROM quote WHERE cabinet_id = $1)",
    )
    .bind(f.cabinet_id)
    .execute(&mut *tx)
    .await
    .ok();
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_act WHERE appointment_id = $1")
        .bind(f.appointment_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_phase WHERE id = $1")
        .bind(f.phase_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_plan WHERE id = $1")
        .bind(f.plan_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(f.appointment_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(f.practitioner_id)
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

async fn complete_consultation(state: AppState, f: &Fixtures) -> (StatusCode, serde_json::Value) {
    let token = make_practitioner_token(f.user_id, f.cabinet_id);
    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/consultations/{}/complete",
                    f.session_id
                ))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap_or_default();
    (status, body)
}

#[tokio::test]
async fn complete_with_phase_linked_act_increments_completed_sessions() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, Some(10)).await;
    insert_act(&db, &f, Some(f.phase_id)).await;

    let (status, body) = complete_consultation(make_state(app_pool().await), &f).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body["sessions_remaining"].as_i64(),
        Some(9),
        "#4120 : 1 seance sur 10 -> 9 restantes"
    );

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query(
        "SELECT completed_sessions, planned_sessions FROM treatment_phase WHERE id = $1",
    )
    .bind(f.phase_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    let completed: i32 = row.try_get("completed_sessions").unwrap();
    let planned: i32 = row.try_get("planned_sessions").unwrap();
    assert_eq!(completed, 1);
    assert_eq!(planned, 10);

    cleanup_fixtures(&db, &f).await;
}

#[tokio::test]
async fn complete_without_phase_link_is_unaffected() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, Some(10)).await;
    insert_act(&db, &f, None).await;

    let (status, body) = complete_consultation(make_state(app_pool().await), &f).await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        body.get("sessions_remaining").is_none() || body["sessions_remaining"].is_null(),
        "#4120 : acte non rattache a une phase -> pas de decompte, comportement historique"
    );

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT completed_sessions FROM treatment_phase WHERE id = $1")
        .bind(f.phase_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let completed: i32 = row.try_get("completed_sessions").unwrap();
    assert_eq!(completed, 0, "phase non touchee reste a 0");

    cleanup_fixtures(&db, &f).await;
}

/// #4120 : phase sans `planned_sessions` (mécanisme non utilisé, valeur NULL
/// par défaut de toutes les phases existantes) — l'UPDATE ne doit matcher
/// aucune ligne (WHERE planned_sessions IS NOT NULL), pas planter sur la
/// contrainte `completed_not_over_planned`.
#[tokio::test]
async fn complete_with_phase_link_but_no_planned_sessions_is_noop() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, None).await;
    insert_act(&db, &f, Some(f.phase_id)).await;

    let (status, body) = complete_consultation(make_state(app_pool().await), &f).await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        body.get("sessions_remaining").is_none() || body["sessions_remaining"].is_null(),
        "planned_sessions NULL -> mecanisme non utilise, pas de decompte"
    );

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT completed_sessions FROM treatment_phase WHERE id = $1")
        .bind(f.phase_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let completed: i32 = row.try_get("completed_sessions").unwrap();
    assert_eq!(completed, 0);

    cleanup_fixtures(&db, &f).await;
}

/// #4120 : POST .../acts avec un `phase_id` d'un AUTRE patient → 404 (garde
/// tenant/patient, ajoutée dans `consultation_act_create.rs`).
#[tokio::test]
async fn add_act_with_foreign_patient_phase_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, Some(5)).await;

    // Deuxième patient + plan + phase, même cabinet.
    let other_patient_id = Uuid::new_v4();
    let other_plan_id = Uuid::new_v4();
    let other_phase_id = Uuid::new_v4();
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
             VALUES ($1, $2, 'Autre', 'Patient')",
        )
        .bind(other_patient_id)
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO treatment_plan (id, cabinet_id, patient_id, title, status) \
             VALUES ($1, $2, $3, 'Autre plan', 'in_progress')",
        )
        .bind(other_plan_id)
        .bind(f.cabinet_id)
        .bind(other_patient_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO treatment_phase \
             (id, cabinet_id, plan_id, position, title, status, planned_sessions) \
             VALUES ($1, $2, $3, 1, 'Autre phase', 'in_progress', 5)",
        )
        .bind(other_phase_id)
        .bind(f.cabinet_id)
        .bind(other_plan_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let token = make_practitioner_token(f.user_id, f.cabinet_id);
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", f.session_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::from(
                    json!({
                        "ccam_code": "HBLD001",
                        "label": "Suivi",
                        "amount_cents": 2500,
                        "phase_id": other_phase_id
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_phase WHERE id = $1")
        .bind(other_phase_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_plan WHERE id = $1")
        .bind(other_plan_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(other_patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();

    cleanup_fixtures(&db, &f).await;
}
