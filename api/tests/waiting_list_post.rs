//! Tests d'intégration : POST /v1/waiting-list (US-P12, issue #1670, #1821)
//!
//! Couvre :
//! - 201 happy path (patient s'inscrit pour un provider valide).
//! - 409 already_on_waiting_list (même patient + même provider, entrée active).
//! - 401 sans token Authorization.
//! - 403 token pro utilisé à la place d'un token patient.
//! - 404 provider_id inconnu.

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

const JWT_SECRET: &str = "test-jwt-secret-waiting-list-post";

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

/// Fixture : cabinet + praticien + provider + patient (dossier).
struct Fixture {
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    provider_id: Uuid,
    patient_user_id: Uuid,
    patient_account_id: Uuid,
    patient_id: Uuid,
}

async fn setup_fixture(db: &PgPool, tag: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    // app_user patient
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("wl-pat-{}+{}@nubia.test", tag, patient_user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Test')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
    .execute(db)
    .await
    .unwrap();

    // app_user pro
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("wl-prac-{}+{}@nubia.test", tag, prac_user_id))
    .execute(db)
    .await
    .unwrap();

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet WL {} {}", tag, cabinet_id))
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
             VALUES ($1, $2, $3, $4, 'Dr. WL', true, true)",
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
             VALUES ($1, $2, 'Alice', 'Test', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(patient_account_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    Fixture {
        cabinet_id,
        prac_user_id,
        provider_id,
        patient_user_id,
        patient_account_id,
        patient_id,
    }
}

async fn cleanup_fixture(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM waiting_list_entry WHERE patient_id = $1")
        .bind(f.patient_id)
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
    sqlx::query("DELETE FROM practitioner WHERE user_id = $1")
        .bind(f.prac_user_id)
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

// ── Test 1 : happy path → 201 { id, status: "active" } ───────────────────────

#[tokio::test]
async fn post_waiting_list_happy_path_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup_fixture(&db, "happy").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/waiting-list")
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
                        "motif": "Détartrage",
                        "start_date": "2026-09-01",
                        "end_date": "2026-09-30"
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
    assert_eq!(v["status"], "active", "status initial doit être active");

    cleanup_fixture(&db, &f).await;
}

// ── Test 2 : déjà en file (même patient + même provider) → 409 ───────────────

#[tokio::test]
async fn post_waiting_list_duplicate_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup_fixture(&db, "dup").await;

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
        "provider_id": f.provider_id
    }))
    .unwrap();

    // Premier appel → 201.
    let r1 = app(make_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/waiting-list")
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
        "premier appel doit être 201"
    );

    // Deuxième appel avec le même provider → 409.
    let r2 = app(make_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/waiting-list")
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
    assert_eq!(r2.status(), StatusCode::CONFLICT, "doublon → 409");

    let body2 = axum::body::to_bytes(r2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body2).unwrap();
    assert_eq!(v["code"], "already_on_waiting_list");

    cleanup_fixture(&db, &f).await;
}

// ── Test 3 : 401 sans header Authorization ────────────────────────────────────

#[tokio::test]
async fn post_waiting_list_no_token_returns_401() {
    let state = AppState {
        db: PgPool::connect_lazy("postgres://nubia_app@localhost:5432/nubia").unwrap(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/waiting-list")
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({ "provider_id": Uuid::new_v4() })).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 4 : 403 token pro (kind:"pro") utilisé sur un endpoint patient ───────

#[tokio::test]
async fn post_waiting_list_pro_token_returns_403() {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let pro_token = jsonwebtoken::encode(
        &jsonwebtoken::Header::default(),
        &json!({
            "sub": Uuid::new_v4(),
            "kind": "pro",
            "cabinet_id": Uuid::new_v4(),
            "role": "admin",
            "exp": exp
        }),
        &jsonwebtoken::EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let state = AppState {
        db: PgPool::connect_lazy("postgres://nubia_app@localhost:5432/nubia").unwrap(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/waiting-list")
                .header("Authorization", format!("Bearer {pro_token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({ "provider_id": Uuid::new_v4() })).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 5 : 404 provider_id inconnu ─────────────────────────────────────────

#[tokio::test]
async fn post_waiting_list_unknown_provider_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup_fixture(&db, "404prov").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Provider UUID inexistant en base.
    let unknown_provider_id = Uuid::new_v4();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/waiting-list")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(f.patient_user_id, f.patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({ "provider_id": unknown_provider_id })).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    cleanup_fixture(&db, &f).await;
}
