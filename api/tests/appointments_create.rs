//! Tests d'intégration : POST /v1/appointments — réponse complète + 409 EXCLUDE (issue #2499)

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

const JWT_SECRET: &str = "test-jwt-secret-appointments-create";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "role": "admin", "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

struct Fixtures {
    cabinet_id: Uuid,
    patient_user_id: Uuid,
    prac_user_id: Uuid,
    patient_account_id: Uuid,
    provider_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
}

async fn setup(db: &PgPool, prefix: &str) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!(
        "create-{}-pat+{}@nubia.test",
        prefix, patient_user_id
    ))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES ($1, $2, 'Test', 'Patient')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!(
        "create-{}-prac+{}@nubia.test",
        prefix, prac_user_id
    ))
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
        "INSERT INTO cabinet (id, raison_sociale, specialite, settings) \
         VALUES ($1, $2, 'dentaire', '{\"address\": \"12 rue de la Paix, Paris\"}'::jsonb)",
    )
    .bind(cabinet_id)
    .bind(format!("Cabinet {} {}", prefix, cabinet_id))
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
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, is_listed, rpps_verified) \
         VALUES ($1, $2, $3, $4, 'Dr. Test', true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Test', 'Patient', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        patient_user_id,
        prac_user_id,
        patient_account_id,
        provider_id,
        prac_id,
        patient_id,
    }
}

/// Insère un availability_slot 'open' — requis depuis #3722 pour qu'une
/// réservation via `starts_at` direct (sans `slot_id`) résolve un créneau réel.
async fn insert_open_slot(db: &PgPool, f: &Fixtures, starts_at: &str, ends_at: &str) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, $5, $6, 'open')",
    )
    .bind(Uuid::new_v4())
    .bind(f.provider_id)
    .bind(f.cabinet_id)
    .bind(f.prac_id)
    .bind(starts_at.parse::<chrono::DateTime<chrono::Utc>>().unwrap())
    .bind(ends_at.parse::<chrono::DateTime<chrono::Utc>>().unwrap())
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
}

async fn teardown(db: &PgPool, f: &Fixtures) {
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
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(f.provider_id)
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
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(f.patient_user_id)
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : 201 avec shape complète { id, starts_at, ends_at, status, provider, cabinet } ──

#[tokio::test]
async fn create_appointment_returns_201_with_full_detail() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "detail").await;
    insert_open_slot(&db, &f, "2032-07-10T09:00:00Z", "2032-07-10T09:30:00Z").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/appointments")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(f.patient_user_id, f.patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "provider_id": f.provider_id,
                        "starts_at": "2032-07-10T09:00:00Z",
                        "motif": "bilan annuel"
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert!(v["id"].is_string(), "id doit être présent");
    assert!(v["starts_at"].is_string(), "starts_at doit être présent");
    assert!(v["ends_at"].is_string(), "ends_at doit être présent");
    assert_eq!(v["status"], "requested");
    assert_eq!(v["motif"], "bilan annuel");
    assert!(!v["provider"].is_null(), "provider doit être présent");
    assert_eq!(
        v["provider"]["display_name"], "Dr. Test",
        "provider.display_name doit correspondre"
    );
    assert!(!v["cabinet"].is_null(), "cabinet doit être présent");
    assert!(
        v["cabinet"]["name"].is_string(),
        "cabinet.name doit être présent"
    );
    assert_eq!(
        v["cabinet"]["address"], "12 rue de la Paix, Paris",
        "cabinet.address doit correspondre"
    );

    teardown(&db, &f).await;
}

// ── Test 2 : motif optionnel — body sans motif → 201 ─────────────────────────

#[tokio::test]
async fn create_appointment_without_motif_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "nomotif").await;
    insert_open_slot(&db, &f, "2032-08-10T10:00:00Z", "2032-08-10T10:30:00Z").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/appointments")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(f.patient_user_id, f.patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "provider_id": f.provider_id,
                        "starts_at": "2032-08-10T10:00:00Z"
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    teardown(&db, &f).await;
}

// ── Test 3 : EXCLUDE violation → 409 { "code": "slot_taken" } ────────────────

#[tokio::test]
async fn create_appointment_overlap_returns_409_slot_taken() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "overlap").await;
    insert_open_slot(&db, &f, "2032-09-15T14:00:00Z", "2032-09-15T14:30:00Z").await;

    let make_state = || AppState {
        db: PgPool::connect_lazy(
            &std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
        )
        .unwrap(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body_json = serde_json::to_string(&json!({
        "provider_id": f.provider_id,
        "starts_at": "2032-09-15T14:00:00Z",
        "motif": "détartrage"
    }))
    .unwrap();

    // Premier appel → 201.
    let r1 = app(make_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/appointments")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(f.patient_user_id, f.patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(body_json.clone()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        r1.status(),
        StatusCode::CREATED,
        "premier RDV doit être 201"
    );

    // Second appel, même créneau, même praticien → EXCLUDE violation → 409.
    let r2 = app(make_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/appointments")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(f.patient_user_id, f.patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(body_json))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        r2.status(),
        StatusCode::CONFLICT,
        "chevauchement doit retourner 409"
    );

    let b2 = axum::body::to_bytes(r2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&b2).unwrap();
    assert_eq!(
        v2["code"], "slot_taken",
        "code d'erreur doit être slot_taken (23P01)"
    );

    teardown(&db, &f).await;
}

// ── Test 4 : sans token → 401 ─────────────────────────────────────────────────

#[tokio::test]
async fn create_appointment_no_token_returns_401() {
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
                .method("POST")
                .uri("/v1/appointments")
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "provider_id": Uuid::new_v4(),
                        "starts_at": "2032-01-01T09:00:00Z"
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 5 : token pro → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn create_appointment_pro_token_returns_403() {
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
                .method("POST")
                .uri("/v1/appointments")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(Uuid::new_v4(), Uuid::new_v4())),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "provider_id": Uuid::new_v4(),
                        "starts_at": "2032-01-01T09:00:00Z"
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}
