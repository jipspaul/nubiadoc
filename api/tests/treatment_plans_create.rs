//! Tests d'intégration : POST /v1/cabinet/treatment-plans (#4049)
//!
//! 1. Praticien + patient du cabinet → 201 { plan_id }, ligne persistée en base
//!    (cabinet_id, patient_id, practitioner_id, status = 'draft').
//! 2. Patient hors cabinet (autre tenant) → 404.
//! 3. title vide → 422, aucune ligne créée.

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

const JWT_SECRET: &str = "test-secret-treatment-plans-create";

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

/// Insère les fixtures minimales : cabinet + app_user + practitioner + patient.
/// Retourne `(cabinet_id, user_id, patient_id)`.
async fn insert_fixtures(db: &PgPool) -> (Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("tp-prac+{}@nubia.test", user_id))
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
         VALUES ($1, 'Cabinet Plan Test', 'dentaire')",
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

    (cabinet_id, user_id, patient_id)
}

/// Ajoute un second praticien au cabinet, SANS aucun `appointment` avec
/// `patient_id` (pour tester la garde §14, #4400). Retourne son `user_id`.
async fn insert_practitioner_without_care_relationship(db: &PgPool, cabinet_id: Uuid) -> Uuid {
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("tp-prac-norel+{}@nubia.test", user_id))
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

async fn cleanup_fixtures(db: &PgPool, cabinet_id: Uuid, user_id: Uuid, patient_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_plan WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : praticien + patient du cabinet → 201, ligne persistée ───────────

#[tokio::test]
async fn create_treatment_plan_returns_201_and_persists() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/treatment-plans")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({ "patient_id": patient_id, "title": "Plan implant + couronne" })
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let plan_id: Uuid = v["plan_id"].as_str().unwrap().parse().unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query(
        "SELECT cabinet_id, patient_id, practitioner_id, title, status \
         FROM treatment_plan WHERE id = $1",
    )
    .bind(plan_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let row_cabinet_id: Uuid = row.try_get("cabinet_id").unwrap();
    let row_patient_id: Uuid = row.try_get("patient_id").unwrap();
    let row_title: String = row.try_get("title").unwrap();
    let row_status: String = row.try_get("status").unwrap();
    assert_eq!(row_cabinet_id, cabinet_id);
    assert_eq!(row_patient_id, patient_id);
    assert_eq!(row_title, "Plan implant + couronne");
    assert_eq!(row_status, "draft");

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 2 : patient hors cabinet → 404 ───────────────────────────────────────

#[tokio::test]
async fn create_treatment_plan_foreign_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;
    let (other_cabinet_id, other_user_id, other_patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/treatment-plans")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({ "patient_id": other_patient_id, "title": "Plan" }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
    cleanup_fixtures(&db, other_cabinet_id, other_user_id, other_patient_id).await;
}

// ── Test 3 : title vide → 422, aucune ligne créée ─────────────────────────────

#[tokio::test]
async fn create_treatment_plan_empty_title_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/treatment-plans")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({ "patient_id": patient_id, "title": "   " }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let count: i64 = sqlx::query("SELECT count(*) AS n FROM treatment_plan WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap()
        .try_get("n")
        .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(count, 0);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 4 : praticien sans relation de soin avec le patient → 403 (#4400) ───

#[tokio::test]
async fn create_treatment_plan_no_care_relationship_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;
    let other_user_id = insert_practitioner_without_care_relationship(&db, cabinet_id).await;

    let token = make_practitioner_token(other_user_id, cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/treatment-plans")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({ "patient_id": patient_id, "title": "Plan" }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_user_id)
        .execute(&db)
        .await
        .ok();
}
