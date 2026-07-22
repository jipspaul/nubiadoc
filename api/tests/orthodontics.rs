//! Tests d'intégration : suivi orthodontique (#4135)
//! - POST/GET /v1/cabinet/patients/{id}/orthodontics
//! - POST /v1/cabinet/orthodontics/{id}/steps

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

const JWT_SECRET: &str = "test-secret-orthodontics";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
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
            "role": "practitioner",
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("ortho+{prac_user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Ortho Test', 'dentaire')",
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'Ortho')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

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

    Fixture {
        cabinet_id,
        prac_user_id,
        prac_id,
        patient_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM orthodontic_step WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM orthodontic_treatment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(f.prac_id)
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
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn call(
    state: AppState,
    method: &str,
    uri: &str,
    token: &str,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("Authorization", format!("Bearer {token}"));
    let body = match body {
        Some(v) => {
            builder = builder.header("Content-Type", "application/json");
            Body::from(v.to_string())
        }
        None => Body::empty(),
    };
    let response = app(state)
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

// ── Test 1 : créer un traitement + 2 étapes → liste ordonnée par step_number ──

#[tokio::test]
async fn create_treatment_then_two_steps_returns_ordered_list() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/patients/{}/orthodontics", f.patient_id),
        &token,
        Some(json!({"type": "multi-attache", "semester_count": 4})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let treatment_id = created["treatment_id"].as_str().unwrap().to_string();

    // Ajoute les étapes dans le désordre (2 puis 1) — la liste doit rester
    // ordonnée par step_number, pas par ordre d'insertion.
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/orthodontics/{treatment_id}/steps"),
        &token,
        Some(json!({"step_number": 2, "kind": "contention"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/orthodontics/{treatment_id}/steps"),
        &token,
        Some(json!({"step_number": 1, "kind": "bague"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/patients/{}/orthodontics", f.patient_id),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let treatments = list.as_array().unwrap();
    assert_eq!(treatments.len(), 1);
    let steps = treatments[0]["steps"].as_array().unwrap();
    assert_eq!(steps.len(), 2);
    assert_eq!(steps[0]["step_number"], 1);
    assert_eq!(steps[0]["kind"], "bague");
    assert_eq!(steps[1]["step_number"], 2);
    assert_eq!(steps[1]["kind"], "contention");

    cleanup(&db, &f).await;
}

// ── Test 2 : accès hors tenant → 404 ─────────────────────────────────────────

#[tokio::test]
async fn access_from_other_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/patients/{}/orthodontics", f.patient_id),
        &token,
        Some(json!({"type": "gouttières", "semester_count": 2})),
    )
    .await;
    let treatment_id = created["treatment_id"].as_str().unwrap().to_string();

    let other_cabinet_id = Uuid::new_v4();
    let other_prac_user_id = Uuid::new_v4();
    let other_prac_id = Uuid::new_v4();
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(other_cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(other_prac_user_id)
        .bind(format!("ortho-other+{other_prac_user_id}@nubia.test"))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) \
             VALUES ($1, 'Cabinet Ortho Other', 'dentaire')",
        )
        .bind(other_cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
            .bind(other_prac_id)
            .bind(other_cabinet_id)
            .bind(other_prac_user_id)
            .execute(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
    }

    let other_token = make_practitioner_token(other_prac_user_id, other_cabinet_id);

    let (status, _) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/patients/{}/orthodontics", f.patient_id),
        &other_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/orthodontics/{treatment_id}/steps"),
        &other_token,
        Some(json!({"step_number": 1, "kind": "bague"})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(other_cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
            .bind(other_cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM cabinet WHERE id = $1")
            .bind(other_cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_prac_user_id)
        .execute(&db)
        .await
        .ok();

    cleanup(&db, &f).await;
}

// ── Test 3 : step_number déjà utilisé → 409 ──────────────────────────────────

#[tokio::test]
async fn duplicate_step_number_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/patients/{}/orthodontics", f.patient_id),
        &token,
        Some(json!({"type": "linguale", "semester_count": 3})),
    )
    .await;
    let treatment_id = created["treatment_id"].as_str().unwrap().to_string();

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/orthodontics/{treatment_id}/steps"),
        &token,
        Some(json!({"step_number": 1, "kind": "bague"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/orthodontics/{treatment_id}/steps"),
        &token,
        Some(json!({"step_number": 1, "kind": "contention"})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(resp["code"], "step_number_taken");

    cleanup(&db, &f).await;
}
