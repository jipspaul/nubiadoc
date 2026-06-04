//! Tests d'intégration : DELETE /v1/account/dependents/{id}

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

const JWT_SECRET: &str = "test-jwt-secret-dependents-delete";

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

// ── Test 1 : happy path — 204 + proche absent de GET après révocation ─────────

#[tokio::test]
async fn dependent_delete_happy_path_returns_204_and_hides_dependent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_user_id)
    .bind(format!("guardian-del+{}@nubia.test", guardian_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Tuteur')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_user_id)
    .bind(format!("dependent-del+{}@nubia.test", dependent_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'Proche')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(&db)
    .await
    .unwrap();

    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'enfant', true)",
        )
        .bind(guardian_account_id)
        .bind(dependent_account_id)
        .execute(&rls_db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(guardian_user_id, guardian_account_id);

    // DELETE → 204
    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/account/dependents/{}", dependent_account_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    // GET /v1/account/dependents → tableau vide (proche révoqué exclu)
    let list_response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/dependents")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(list_response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(list_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(json.as_array().expect("tableau").is_empty());
}

// ── Test 2 : double DELETE → 404 ──────────────────────────────────────────────

#[tokio::test]
async fn dependent_delete_twice_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_user_id)
    .bind(format!("guardian-del2+{}@nubia.test", guardian_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Tuteur2')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_user_id)
    .bind(format!("dependent-del2+{}@nubia.test", dependent_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'Proche2')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(&db)
    .await
    .unwrap();

    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'enfant', true)",
        )
        .bind(guardian_account_id)
        .bind(dependent_account_id)
        .execute(&rls_db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(guardian_user_id, guardian_account_id);
    let uri = format!("/v1/account/dependents/{}", dependent_account_id);

    // Premier DELETE → 204
    let r1 = app(state.clone())
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(&uri)
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r1.status(), StatusCode::NO_CONTENT);

    // Second DELETE → 404
    let r2 = app(state)
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(&uri)
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r2.status(), StatusCode::NOT_FOUND);
}
