//! Tests d'intégration : POST /v1/cabinet/quotes

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-quotes";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": user_id,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": role,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": user_id,
            "kind": "patient",
            "account_id": account_id,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── Test 1 : happy path — praticien crée un devis avec 2 items ───────────────

#[tokio::test]
async fn cabinet_quotes_post_happy_path() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    // Fixtures
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("cq-prac+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("cq-patient+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Patient')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
    .execute(&db)
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
        .bind(format!("Cabinet CQ Test {}", cabinet_id))
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
            "INSERT INTO patient \
             (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Test', 'Patient', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(patient_account_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = json!({
        "patient_id": patient_id,
        "items": [
            { "label": "Consultation", "amount_cents": 5000 },
            { "label": "Détartrage", "amount_cents": 8000 }
        ],
        "deposit_pct": 30.0
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/quotes")
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(user_id, cabinet_id, "practitioner")
                    ),
                )
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    assert!(v["quote_id"].is_string(), "quote_id doit être un UUID");
    assert_eq!(
        v["total_amount_cents"], 13000,
        "5000 + 8000 = 13000 centimes"
    );

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM quote_item WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(patient_user_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(patient_account_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : token patient → 403 ─────────────────────────────────────────────

#[tokio::test]
async fn cabinet_quotes_post_patient_token_returns_403() {
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

    let body = json!({
        "patient_id": Uuid::new_v4(),
        "items": [{ "label": "Soin", "amount_cents": 1000 }]
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/quotes")
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(Uuid::new_v4(), Uuid::new_v4())
                    ),
                )
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 3 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn cabinet_quotes_post_no_jwt_returns_401() {
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

    let body = json!({
        "patient_id": Uuid::new_v4(),
        "items": [{ "label": "Soin", "amount_cents": 1000 }]
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/quotes")
                .header("Content-Type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 4 : rôle secretary → 403 ────────────────────────────────────────────

#[tokio::test]
async fn cabinet_quotes_post_secretary_returns_403() {
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

    let body = json!({
        "patient_id": Uuid::new_v4(),
        "items": [{ "label": "Soin", "amount_cents": 1000 }]
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/quotes")
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "secretary")
                    ),
                )
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 5 : items vide → 422 ────────────────────────────────────────────────

#[tokio::test]
async fn cabinet_quotes_post_empty_items_returns_422() {
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

    let body = json!({
        "patient_id": Uuid::new_v4(),
        "items": []
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/quotes")
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "practitioner")
                    ),
                )
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 6 : deposit_pct hors borne → 422 ────────────────────────────────────

#[tokio::test]
async fn cabinet_quotes_post_invalid_deposit_pct_returns_422() {
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

    let body = json!({
        "patient_id": Uuid::new_v4(),
        "items": [{ "label": "Soin", "amount_cents": 1000 }],
        "deposit_pct": 150.0
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/quotes")
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "practitioner")
                    ),
                )
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}
