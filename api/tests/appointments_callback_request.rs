//! Tests d'intégration : POST /v1/appointments/:id/callback-request

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

const JWT_SECRET: &str = "test-jwt-secret-appointments-callback";

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
        .bind(format!("Cabinet Callback {}", cabinet_id))
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
         VALUES ($1, $2, 'Test', 'Callback', $3)",
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
                 now() + INTERVAL '2 days', now() + INTERVAL '2 days 30 min', $5, 'test')",
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

    (cabinet_id, prac_id, patient_id, appt_id)
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, patient_id: Uuid, prac_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
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

fn make_pro_jwt_callback(user_id: Uuid, cabinet_id: Uuid) -> String {
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

// ── Test auth scope : sans JWT → 401 ────────────────────────────────────────

#[tokio::test]
async fn post_callback_request_no_jwt_returns_401() {
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
                .uri(format!(
                    "/v1/appointments/{}/callback-request",
                    Uuid::new_v4()
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test auth scope : token pro → 403 ───────────────────────────────────────

#[tokio::test]
async fn post_callback_request_pro_token_returns_403() {
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
                .uri(format!(
                    "/v1/appointments/{}/callback-request",
                    Uuid::new_v4()
                ))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt_callback(Uuid::new_v4(), Uuid::new_v4())
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 1 : happy path → 200 {"appointment_id","callback_requested_at"} ─────

#[tokio::test]
async fn post_callback_request_happy_path_returns_200() {
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
    .bind(format!("callback-happy+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Callback', 'Happy')",
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
    .bind(format!("callback-happy-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    let (cabinet_id, prac_id, patient_id, appt_id) =
        insert_fixture(&db, prac_user_id, patient_account_id, "confirmed").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/appointments/{}/callback-request", appt_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(patient_user_id, patient_account_id)
                    ),
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

    assert_eq!(v["appointment_id"], appt_id.to_string());
    assert!(
        v["callback_requested_at"].is_string(),
        "callback_requested_at doit être présent"
    );

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

// ── Test 2 : statut invalide → 409 {"error":"invalid_status"} ─────────────

#[tokio::test]
async fn post_callback_request_invalid_status_returns_409() {
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
    .bind(format!("callback-badstatus+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Callback', 'BadStatus')",
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
    .bind(format!(
        "callback-badstatus-prac+{}@nubia.test",
        prac_user_id
    ))
    .execute(&db)
    .await
    .unwrap();

    // RDV annulé → invalid_status.
    let (cabinet_id, prac_id, patient_id, appt_id) =
        insert_fixture(&db, prac_user_id, patient_account_id, "cancelled").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/appointments/{}/callback-request", appt_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(patient_user_id, patient_account_id)
                    ),
                )
                .body(Body::empty())
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

// ── Test 3 : wrong patient → 404 (anti-énumération RLS, policy 0029) ─────────

#[tokio::test]
async fn post_callback_request_wrong_patient_returns_404() {
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
    .bind(format!("callback-wrongpt+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Callback', 'WrongPt')",
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
    .bind(format!("callback-wrongpt-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // RDV appartient à patient_account_id.
    let (cabinet_id, prac_id, patient_id, appt_id) =
        insert_fixture(&db, prac_user_id, patient_account_id, "confirmed").await;

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
                .method("POST")
                .uri(format!("/v1/appointments/{}/callback-request", appt_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(wrong_user_id, wrong_account_id)
                    ),
                )
                .body(Body::empty())
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

// ── Test 4 : deuxième demande → 200 idempotent (même timestamp) ─────────────

#[tokio::test]
async fn post_callback_request_idempotent_returns_200() {
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
    .bind(format!(
        "callback-idempotent+{}@nubia.test",
        patient_user_id
    ))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Callback', 'Idempotent')",
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
    .bind(format!(
        "callback-idempotent-prac+{}@nubia.test",
        prac_user_id
    ))
    .execute(&db)
    .await
    .unwrap();

    let (cabinet_id, prac_id, patient_id, appt_id) =
        insert_fixture(&db, prac_user_id, patient_account_id, "confirmed").await;

    let make_state = || AppState {
        db: {
            let url = std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
            PgPool::connect_lazy(&url).unwrap()
        },
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Première demande.
    let resp1 = app(make_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/appointments/{}/callback-request", appt_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(patient_user_id, patient_account_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp1.status(), StatusCode::OK);
    let b1 = axum::body::to_bytes(resp1.into_body(), usize::MAX)
        .await
        .unwrap();
    let v1: serde_json::Value = serde_json::from_slice(&b1).unwrap();
    let ts1 = v1["callback_requested_at"].as_str().unwrap().to_string();

    // Deuxième demande → même 200, même timestamp (idempotent).
    let resp2 = app(make_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/appointments/{}/callback-request", appt_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(patient_user_id, patient_account_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp2.status(), StatusCode::OK);
    let b2 = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&b2).unwrap();
    let ts2 = v2["callback_requested_at"].as_str().unwrap().to_string();

    assert_eq!(
        ts1, ts2,
        "timestamp idempotent: les deux appels doivent renvoyer le même"
    );

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
