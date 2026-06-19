use std::sync::Arc;

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::{PgPool, Row};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

async fn owner_pool() -> Option<PgPool> {
    let url = std::env::var("DATABASE_URL").ok()?;
    PgPool::connect(&url).await.ok()
}

async fn test_state() -> Option<AppState> {
    let url = std::env::var("APP_DATABASE_URL").ok()?;
    let pool = PgPool::connect(&url).await.ok()?;
    Some(AppState {
        db: pool,
        jwt_secret: String::new(),
        mailer: Arc::new(StubMailer),
    })
}

/// Happy path : email connu → 204 + token stocké en DB.
#[tokio::test]
async fn forgot_known_email_returns_204_and_stores_token() {
    let Some(state) = test_state().await else {
        return;
    };
    let Some(owner_db) = owner_pool().await else {
        return;
    };
    let email = format!("forgot_ok_{}@test.local", Uuid::new_v4());

    sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind) \
         VALUES ($1, 'placeholder', 'patient')",
    )
    .bind(&email)
    .execute(&owner_db)
    .await
    .expect("insert test user");

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/forgot")
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"email":"{}"}}"#, email)))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    let row = sqlx::query(
        "SELECT password_reset_token, password_reset_expires_at \
         FROM app_user WHERE email = $1",
    )
    .bind(&email)
    .fetch_one(&owner_db)
    .await
    .expect("fetch user after forgot");

    let token: Option<String> = row.try_get("password_reset_token").unwrap();
    assert!(
        token.is_some(),
        "password_reset_token should be set for a known email"
    );

    let expires_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("password_reset_expires_at").unwrap();
    assert!(
        expires_at.is_some(),
        "password_reset_expires_at should be set"
    );
    assert!(
        expires_at.unwrap() > chrono::Utc::now(),
        "expiry should be in the future"
    );

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_db)
        .await
        .unwrap();
}

/// Anti-énumération §1.8 : email inconnu → 204 silencieux, aucune ligne modifiée.
#[tokio::test]
async fn forgot_unknown_email_returns_204_silently() {
    let Some(state) = test_state().await else {
        return;
    };

    let fake_email = format!("nobody_{}@test.local", Uuid::new_v4());

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/forgot")
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"email":"{}"}}"#, fake_email)))
                .unwrap(),
        )
        .await
        .unwrap();

    // Anti-énumération : même réponse que pour un email connu.
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
}

/// Validation input : body JSON manquant → 422 Unprocessable Entity.
#[tokio::test]
async fn forgot_missing_body_returns_422() {
    let Some(state) = test_state().await else {
        return;
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/forgot")
                .header("content-type", "application/json")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

/// Validation input : body JSON invalide (champ `email` absent) → 422.
#[tokio::test]
async fn forgot_invalid_json_returns_422() {
    let Some(state) = test_state().await else {
        return;
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/forgot")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"not_email":"foo@bar.com"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

/// Edge case idempotence : deux appels successifs pour le même email → 204 les deux fois,
/// et le token en DB est mis à jour (le second écrase le premier).
#[tokio::test]
async fn forgot_idempotent_overwrites_previous_token() {
    let Some(state) = test_state().await else {
        return;
    };
    let Some(owner_db) = owner_pool().await else {
        return;
    };
    let email = format!("forgot_idem_{}@test.local", Uuid::new_v4());

    sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind) \
         VALUES ($1, 'placeholder', 'patient')",
    )
    .bind(&email)
    .execute(&owner_db)
    .await
    .expect("insert test user");

    // Premier appel.
    let r1 = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/forgot")
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"email":"{}"}}"#, email)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r1.status(), StatusCode::NO_CONTENT);

    let row1 = sqlx::query("SELECT password_reset_token FROM app_user WHERE email = $1")
        .bind(&email)
        .fetch_one(&owner_db)
        .await
        .unwrap();
    let token1: Option<String> = row1.try_get("password_reset_token").unwrap();

    // Second appel.
    let r2 = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/forgot")
                .header("content-type", "application/json")
                .body(Body::from(format!(r#"{{"email":"{}"}}"#, email)))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r2.status(), StatusCode::NO_CONTENT);

    let row2 = sqlx::query("SELECT password_reset_token FROM app_user WHERE email = $1")
        .bind(&email)
        .fetch_one(&owner_db)
        .await
        .unwrap();
    let token2: Option<String> = row2.try_get("password_reset_token").unwrap();

    // Les deux tokens doivent être présents mais distincts (chaque appel génère un nouvel UUID).
    assert!(token1.is_some(), "first token must be set");
    assert!(token2.is_some(), "second token must be set");
    assert_ne!(
        token1, token2,
        "second call must overwrite the token with a fresh value"
    );

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_db)
        .await
        .unwrap();
}
