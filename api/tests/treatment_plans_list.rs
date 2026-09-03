//! Tests d'intégration : GET /v1/cabinet/patients/:id/treatment-plans (#4051)
//!
//! 1. Praticien + patient du cabinet, plans avec phases → 200, structure imbriquée
//!    correcte (phases triées par position).
//! 2. Patient sans plan → 200 { data: [] }.
//! 3. Patient hors cabinet (autre tenant) → 404.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-treatment-plans-list";

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
}

/// Insère cabinet + app_user + practitioner + patient.
async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("tpl-prac+{}@nubia.test", user_id))
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
         VALUES ($1, 'Cabinet List Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
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

    // Appointment passé : le praticien a consulté ce patient (garde §14, #4400).
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', now(), 'done', 'contrôle')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        user_id,
        patient_id,
    }
}

/// Ajoute un second praticien au cabinet, SANS aucun `appointment` avec le
/// patient (pour tester la garde §14, #4400). Retourne son `user_id`.
async fn insert_practitioner_without_care_relationship(db: &PgPool, cabinet_id: Uuid) -> Uuid {
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("tpl-prac-norel+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    user_id
}

/// Insère un plan avec deux phases (position 2 puis 1, pour vérifier le tri).
async fn insert_plan_with_phases(db: &PgPool, cabinet_id: Uuid, patient_id: Uuid) -> Uuid {
    let plan_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO treatment_plan (id, cabinet_id, patient_id, title, status) \
         VALUES ($1, $2, $3, 'Plan implant', 'draft')",
    )
    .bind(plan_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO treatment_phase (id, cabinet_id, plan_id, position, title, status) \
         VALUES ($1, $2, $3, 2, 'Phase 2 · Prothèse', 'requested')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(plan_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO treatment_phase (id, cabinet_id, plan_id, position, title, status) \
         VALUES ($1, $2, $3, 1, 'Phase 1 · Chirurgie', 'requested')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(plan_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    plan_id
}

/// Insère un plan avec une phase, un devis et un `quote_item` rattaché à
/// cette phase (montant 100,00 €) — pour vérifier que la liste praticien
/// (#6347) sert bien les actes/montants. Retourne `(plan_id, phase_id)`.
async fn insert_plan_with_phase_and_quote_item(
    db: &PgPool,
    cabinet_id: Uuid,
    patient_id: Uuid,
) -> (Uuid, Uuid) {
    let plan_id = Uuid::new_v4();
    let phase_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO treatment_plan (id, cabinet_id, patient_id, title, status) \
         VALUES ($1, $2, $3, 'Plan couronne', 'in_progress')",
    )
    .bind(plan_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO treatment_phase (id, cabinet_id, plan_id, position, title, status) \
         VALUES ($1, $2, $3, 1, 'Phase 1 · Couronne', 'confirmed')",
    )
    .bind(phase_id)
    .bind(cabinet_id)
    .bind(plan_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount) \
         VALUES ($1, $2, $3, 'draft', 100.00)",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote_item \
         (id, cabinet_id, quote_id, phase_id, label, ccam_code, tooth, unit_amount) \
         VALUES ($1, $2, $3, $4, 'Couronne céramo-métallique', 'HBLD038', '26', 100.00)",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(quote_id)
    .bind(phase_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    (plan_id, phase_id)
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_phase WHERE cabinet_id = $1")
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

// ── Test 1 : plans + phases → 200, structure imbriquée triée ─────────────────

#[tokio::test]
async fn list_cabinet_treatment_plans_returns_nested_phases_sorted() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let plan_id = insert_plan_with_phases(&db, f.cabinet_id, f.patient_id).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/treatment-plans",
                    f.patient_id
                ))
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
    let data = v["data"].as_array().unwrap();
    assert_eq!(data.len(), 1);
    assert_eq!(data[0]["id"], plan_id.to_string());
    assert_eq!(data[0]["title"], "Plan implant");

    let phases = data[0]["phases"].as_array().unwrap();
    assert_eq!(phases.len(), 2);
    assert_eq!(phases[0]["position"], 1);
    assert_eq!(phases[0]["title"], "Phase 1 · Chirurgie");
    assert_eq!(phases[1]["position"], 2);
    assert_eq!(phases[1]["title"], "Phase 2 · Prothèse");

    // Aucun quote_item rattaché à ces phases → acts vide (pas d'erreur de
    // parsing, montant nul légitime).
    assert_eq!(phases[0]["acts"].as_array().unwrap().len(), 0);
    assert_eq!(phases[1]["acts"].as_array().unwrap().len(), 0);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 1bis : quote_item rattaché à une phase → montant servi (#6347) ──────

#[tokio::test]
async fn list_cabinet_treatment_plans_includes_phase_acts_and_amounts() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let (plan_id, phase_id) =
        insert_plan_with_phase_and_quote_item(&db, f.cabinet_id, f.patient_id).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/treatment-plans",
                    f.patient_id
                ))
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
    let data = v["data"].as_array().unwrap();
    assert_eq!(data.len(), 1);
    assert_eq!(data[0]["id"], plan_id.to_string());

    let phases = data[0]["phases"].as_array().unwrap();
    assert_eq!(phases.len(), 1);
    assert_eq!(phases[0]["id"], phase_id.to_string());

    let acts = phases[0]["acts"].as_array().unwrap();
    assert_eq!(acts.len(), 1);
    assert_eq!(acts[0]["label"], "Couronne céramo-métallique");
    assert_eq!(acts[0]["ccam_code"], "HBLD038");
    assert_eq!(acts[0]["tooth"], "26");
    assert_eq!(acts[0]["amount_cents"], 10000);

    // Nettoyage explicite quote_item/quote avant `cleanup_fixtures` (FK
    // quote_item.phase_id -> treatment_phase, pas de ON DELETE CASCADE).
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
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
    tx.commit().await.ok();

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : patient sans plan → 200 { data: [] } ─────────────────────────────

#[tokio::test]
async fn list_cabinet_treatment_plans_empty_returns_empty_array() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/treatment-plans",
                    f.patient_id
                ))
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
    assert_eq!(v["data"].as_array().unwrap().len(), 0);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : patient hors cabinet → 404 ───────────────────────────────────────

#[tokio::test]
async fn list_cabinet_treatment_plans_foreign_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let other = insert_fixtures(&db).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/treatment-plans",
                    other.patient_id
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, &f).await;
    cleanup_fixtures(&db, &other).await;
}

// ── Test 4 : praticien sans relation de soin avec le patient → 403 (#4400) ───

#[tokio::test]
async fn list_cabinet_treatment_plans_no_care_relationship_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let other_user_id = insert_practitioner_without_care_relationship(&db, f.cabinet_id).await;

    let token = make_practitioner_token(other_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/treatment-plans",
                    f.patient_id
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, &f).await;
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_user_id)
        .execute(&db)
        .await
        .ok();
}
