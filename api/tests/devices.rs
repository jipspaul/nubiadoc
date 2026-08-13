//! Tests d'intégration : POST /v1/devices

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

const JWT_SECRET: &str = "test-jwt-secret-devices";

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

fn make_patient_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── Test 1 : happy path patient → 201 { id } ─────────────────────────────────

#[tokio::test]
async fn devices_post_happy_path_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("device-201+{}@nubia.test", user_id))
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
                .method("POST")
                .uri("/v1/devices")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id)),
                )
                .body(Body::from(
                    json!({"fcm_token": "tok_abc123", "platform": "android"}).to_string(),
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

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn devices_post_no_jwt_returns_401() {
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
                .uri("/v1/devices")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"fcm_token": "tok_abc", "platform": "ios"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 3 : platform invalide → 422 ─────────────────────────────────────────

#[tokio::test]
async fn devices_post_invalid_platform_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("device-422+{}@nubia.test", user_id))
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
                .method("POST")
                .uri("/v1/devices")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id)),
                )
                .body(Body::from(
                    json!({"fcm_token": "tok_abc", "platform": "windows"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 4bis : même fcm_token réenregistré par le MÊME user → id stable (#4850) ──────

#[tokio::test]
async fn devices_post_same_token_same_user_returns_same_id() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let token = format!("tok_stable_{}", Uuid::new_v4());

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("device-4850+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    async fn register(state: AppState, user_id: Uuid, token: &str) -> Uuid {
        let response = app(state)
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/devices")
                    .header("content-type", "application/json")
                    .header(
                        "Authorization",
                        format!("Bearer {}", make_patient_jwt(user_id)),
                    )
                    .body(Body::from(
                        json!({"fcm_token": token, "platform": "android"}).to_string(),
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
        v["id"].as_str().unwrap().parse().unwrap()
    }

    let id_1 = register(state.clone(), user_id, &token).await;
    let id_2 = register(state.clone(), user_id, &token).await;

    assert_eq!(
        id_1, id_2,
        "un ré-enregistrement du même fcm_token doit renvoyer le même id"
    );

    let row_count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM device WHERE app_user_id = $1")
            .bind(user_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(
        row_count, 1,
        "un ré-enregistrement identique ne doit pas créer de nouvelle ligne"
    );

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 4 : même fcm_token réenregistré par un AUTRE user → invalide l'ancien (#3789) ──

#[tokio::test]
async fn devices_post_same_token_other_user_deactivates_previous_owner() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_a = Uuid::new_v4();
    let user_b = Uuid::new_v4();
    let token = format!("tok_shared_{}", Uuid::new_v4());

    for u in [user_a, user_b] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
        )
        .bind(u)
        .bind(format!("device-3789+{}@nubia.test", u))
        .execute(&db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // A enregistre le token.
    let resp_a = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/devices")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_a)),
                )
                .body(Body::from(
                    json!({"fcm_token": token, "platform": "ios"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp_a.status(), StatusCode::CREATED);

    // B enregistre le MÊME token (terminal réattribué).
    let resp_b = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/devices")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_b)),
                )
                .body(Body::from(
                    json!({"fcm_token": token, "platform": "ios"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp_b.status(), StatusCode::CREATED);

    // La ligne de A pour ce token doit être invalidée (deleted_at IS NOT NULL).
    let a_deleted_at: Option<chrono::DateTime<chrono::Utc>> = sqlx::query_scalar(
        "SELECT deleted_at FROM device WHERE app_user_id = $1 AND fcm_token = $2",
    )
    .bind(user_a)
    .bind(&token)
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(
        a_deleted_at.is_some(),
        "le device de l'ancien propriétaire (A) doit être invalidé quand B réenregistre le même token"
    );

    // La ligne de B pour ce token doit rester active.
    let b_deleted_at: Option<chrono::DateTime<chrono::Utc>> = sqlx::query_scalar(
        "SELECT deleted_at FROM device WHERE app_user_id = $1 AND fcm_token = $2",
    )
    .bind(user_b)
    .bind(&token)
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(
        b_deleted_at.is_none(),
        "le device du nouveau propriétaire (B) doit rester actif"
    );

    sqlx::query("DELETE FROM app_user WHERE id = ANY($1)")
        .bind([user_a, user_b].as_slice())
        .execute(&db)
        .await
        .ok();
}
