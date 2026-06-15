//! Tests d'intégration : GET /v1/appointments/:id

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

const JWT_SECRET: &str = "test-jwt-secret-appt-get-by-id";

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

/// Insère le jeu de fixtures minimal pour un RDV : cabinet + praticien + provider + patient.
/// Retourne (cabinet_id, prac_id, patient_id, appt_id).
async fn insert_appointment_fixture(
    db: &PgPool,
    prac_user_id: Uuid,
    patient_account_id: Uuid,
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
        .bind(format!("Cabinet Detail Test {}", cabinet_id))
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
        "INSERT INTO provider (cabinet_id, practitioner_id, user_id, display_name, specialite, is_listed, rpps_verified) \
         VALUES ($1, $2, $3, 'Dr. Detail', 'dentaire', true, true)",
    )
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

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, \
                 now() + interval '3 days', now() + interval '3 days 1 hour', \
                 'confirmed', 'détartrage')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    (cabinet_id, prac_id, patient_id, appt_id)
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
    appt_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE practitioner_id = $1")
        .bind(prac_id)
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

// ── Test 1 : happy path — propriétaire du RDV → 200 avec tous les champs ────────

#[tokio::test]
async fn appointment_get_by_id_owner_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("appt-detail+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Detail', 'Patient')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("appt-detail-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    let (cabinet_id, prac_id, patient_id, appt_id) =
        insert_appointment_fixture(&db, prac_user_id, account_id).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}", appt_id))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
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

    assert_eq!(v["id"], appt_id.to_string(), "id doit correspondre");
    assert!(v["starts_at"].is_string(), "starts_at doit être une chaîne");
    assert!(v["ends_at"].is_string(), "ends_at doit être une chaîne");
    assert_eq!(v["status"], "confirmed");
    assert_eq!(v["motif"], "détartrage");
    assert_eq!(v["provider"]["display_name"], "Dr. Detail");
    assert_eq!(v["provider"]["specialty"], "dentaire");
    assert!(
        v["provider"]["id"].is_string(),
        "provider.id doit être présent"
    );
    assert!(
        v["cabinet"]["name"].is_string(),
        "cabinet.name doit être présent"
    );

    // Cleanup
    cleanup_fixture(&db, cabinet_id, prac_id, patient_id, appt_id).await;
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : RDV inexistant → 404 ────────────────────────────────────────────────

#[tokio::test]
async fn appointment_get_by_id_unknown_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("appt-notfound+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Solo', 'Patient')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}", Uuid::new_v4()))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test auth scope : sans JWT → 401 ─────────────────────────────────────────────

#[tokio::test]
async fn appointment_get_by_id_no_jwt_returns_401() {
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
                .uri(format!("/v1/appointments/{}", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test auth scope : token pro → 403 ────────────────────────────────────────────

fn make_pro_jwt_getbyid(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    jsonwebtoken::encode(
        &jsonwebtoken::Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "role": "admin",
                "account_id": Uuid::nil(), "exp": exp}),
        &jsonwebtoken::EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

#[tokio::test]
async fn appointment_get_by_id_pro_token_returns_403() {
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
                .uri(format!("/v1/appointments/{}", Uuid::new_v4()))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt_getbyid(Uuid::new_v4(), Uuid::new_v4())
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 3 : RDV d'un autre patient → 404 (anti-énumération) ─────────────────────

#[tokio::test]
async fn appointment_get_by_id_other_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    // Patient A (le requérant)
    let user_a_id = Uuid::new_v4();
    let account_a_id = Uuid::new_v4();

    // Patient B (propriétaire du RDV)
    let user_b_id = Uuid::new_v4();
    let account_b_id = Uuid::new_v4();

    let prac_user_id = Uuid::new_v4();

    for (uid, email, kind) in [
        (
            user_a_id,
            format!("appt-a+{}@nubia.test", user_a_id),
            "patient",
        ),
        (
            user_b_id,
            format!("appt-b+{}@nubia.test", user_b_id),
            "patient",
        ),
        (
            prac_user_id,
            format!("appt-prac2+{}@nubia.test", prac_user_id),
            "pro",
        ),
    ] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(uid)
        .bind(&email)
        .bind(kind)
        .execute(&db)
        .await
        .unwrap();
    }

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'A')",
    )
    .bind(account_a_id)
    .bind(user_a_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'B')",
    )
    .bind(account_b_id)
    .bind(user_b_id)
    .execute(&db)
    .await
    .unwrap();

    // Crée le RDV de Patient B
    let (cabinet_id, prac_id, patient_id, appt_b_id) =
        insert_appointment_fixture(&db, prac_user_id, account_b_id).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Patient A essaie d'accéder au RDV de Patient B → 404
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}", appt_b_id))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_a_id, account_a_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "RDV d'un autre patient doit retourner 404 (anti-énumération)"
    );

    // Cleanup
    cleanup_fixture(&db, cabinet_id, prac_id, patient_id, appt_b_id).await;
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2 OR id = $3")
        .bind(user_a_id)
        .bind(user_b_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}
