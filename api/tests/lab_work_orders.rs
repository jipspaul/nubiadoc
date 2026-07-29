//! Tests d'intégration : bons de travaux prothétiques (#4148)
//! - GET/POST /v1/cabinet/lab-work-orders
//! - PATCH /v1/cabinet/lab-work-orders/{id}

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

const JWT_SECRET: &str = "test-secret-lab-work-orders";

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
    user_id: Uuid,
    patient_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("labwork+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet LabWork Test', 'dentaire')",
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
         VALUES ($1, $2, 'Patient', 'LabWork')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    // Appointment passé : le praticien a consulté ce patient (garde §14, #4414).
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
        user_id,
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
    sqlx::query("DELETE FROM lab_work_order WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
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

// ── Test 1 : sent → returned (saute try_in) réussit ──────────────────────────

#[tokio::test]
async fn transition_sent_to_returned_succeeds() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/lab-work-orders",
        &token,
        Some(json!({
            "patient_id": f.patient_id,
            "lab_name": "Labo Dentaire Alpha",
            "purchase_price_cents": 15000
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let order_id = created["order_id"].as_str().unwrap().to_string();

    let (status, resp) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/lab-work-orders/{order_id}"),
        &token,
        Some(json!({"status": "returned"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(resp["status"], "returned");

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/lab-work-orders",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let orders = list.as_array().unwrap();
    assert_eq!(orders.len(), 1);
    assert_eq!(orders[0]["status"], "returned");

    cleanup(&db, &f).await;
}

// ── Test 2 : fitted → sent (retour arrière) → 409 invalid_status ────────────

#[tokio::test]
async fn backward_transition_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/lab-work-orders",
        &token,
        Some(json!({
            "patient_id": f.patient_id,
            "lab_name": "Labo Dentaire Beta",
            "purchase_price_cents": 20000
        })),
    )
    .await;
    let order_id = created["order_id"].as_str().unwrap().to_string();

    let (status, _) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/lab-work-orders/{order_id}"),
        &token,
        Some(json!({"status": "fitted"})),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::OK,
        "sent → fitted (saut direct) doit réussir"
    );

    let (status, resp) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/lab-work-orders/{order_id}"),
        &token,
        Some(json!({"status": "sent"})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(resp["code"], "invalid_status");

    cleanup(&db, &f).await;
}

// ── Test 3 : prix d'achat manquant → 422 ─────────────────────────────────────

#[tokio::test]
async fn missing_purchase_price_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/lab-work-orders",
        &token,
        Some(json!({
            "patient_id": f.patient_id,
            "lab_name": "Labo sans prix"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test : appointment_id d'un AUTRE patient du cabinet → 404 (#4353) ───────

#[tokio::test]
async fn create_with_appointment_of_another_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let other_patient_id = Uuid::new_v4();
    let other_appointment_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("labwork-prac+{prac_user_id}@nubia.test"))
    .execute(&db)
    .await
    .unwrap();
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
        sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
            .bind(prac_id)
            .bind(f.cabinet_id)
            .bind(prac_user_id)
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO appointment \
             (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
             VALUES ($1, $2, $3, $4, now() + interval '1 day', \
                      now() + interval '1 day 30 minutes', 'confirmed')",
        )
        .bind(other_appointment_id)
        .bind(f.cabinet_id)
        .bind(other_patient_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/lab-work-orders",
        &token,
        Some(json!({
            "patient_id": f.patient_id,
            "appointment_id": other_appointment_id,
            "lab_name": "QA Lab CrossPatient",
            "purchase_price_cents": 12000
        })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM lab_work_order WHERE cabinet_id = $1")
            .bind(f.cabinet_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(count, 0, "aucun bon créé");

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query("DELETE FROM appointment WHERE id = $1")
            .bind(other_appointment_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM practitioner WHERE id = $1")
            .bind(prac_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM patient WHERE id = $1")
            .bind(other_patient_id)
            .execute(&mut *tx)
            .await
            .ok();
        tx.commit().await.unwrap();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();

    cleanup(&db, &f).await;
}

/// Ajoute un second praticien au cabinet, SANS aucun `appointment` avec le
/// patient (pour tester la garde §14, #4414). Retourne son `user_id`.
async fn insert_practitioner_without_care_relationship(db: &PgPool, cabinet_id: Uuid) -> Uuid {
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("labwork-norel+{user_id}@nubia.test"))
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

// ── Test (#4414) : praticien sans relation de soin avec le patient → 403 ────

#[tokio::test]
async fn create_no_care_relationship_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let other_user_id = insert_practitioner_without_care_relationship(&db, f.cabinet_id).await;
    let token = make_practitioner_token(other_user_id, f.cabinet_id);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/lab-work-orders",
        &token,
        Some(json!({
            "patient_id": f.patient_id,
            "lab_name": "Labo sans relation",
            "purchase_price_cents": 5000
        })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    cleanup(&db, &f).await;
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_user_id)
        .execute(&db)
        .await
        .ok();
}
