use std::sync::Arc;

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::PgPool;
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

/// Validation : mot de passe trop court (< 8 chars) → 422 password_policy.
#[tokio::test]
async fn reset_password_too_short_returns_422_password_policy() {
    let Some(state) = test_state().await else {
        return;
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/reset")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"token":"some-token","new_password":"Ab1"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "password_policy");
}

/// Validation : mot de passe sans chiffre → 422 password_policy.
#[tokio::test]
async fn reset_password_no_digit_returns_422_password_policy() {
    let Some(state) = test_state().await else {
        return;
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/reset")
                .header("content-type", "application/json")
                .body(Body::from(
                    r#"{"token":"some-token","new_password":"NoDigitPass"}"#,
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "password_policy");
}

/// Body JSON invalide (champ manquant) → 422 (rejet Axum avant le handler).
#[tokio::test]
async fn reset_missing_new_password_field_returns_422() {
    let Some(state) = test_state().await else {
        return;
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/reset")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"token":"some-token"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

/// Edge case idempotence : utiliser le token une 2ème fois après un reset réussi → 404.
/// Le handler nullifie le token après usage ; une 2ème tentative doit échouer.
#[tokio::test]
async fn reset_token_used_twice_second_call_returns_404() {
    let Some(owner_db) = owner_pool().await else {
        return;
    };
    let email = format!("reset_idem_{}@test.local", Uuid::new_v4());
    let token = Uuid::new_v4().to_string();

    sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind, \
         password_reset_token, password_reset_expires_at) \
         VALUES ($1, 'placeholder', 'patient', \
                 encode(digest($2, 'sha256'), 'hex'), now() + interval '1 hour')",
    )
    .bind(&email)
    .bind(&token)
    .execute(&owner_db)
    .await
    .expect("insert test user");

    // Premier appel — doit réussir.
    let Some(state1) = test_state().await else {
        return;
    };
    let resp1 = app(state1)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/reset")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"token":"{}","new_password":"NewPass1"}}"#,
                    token
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp1.status(), StatusCode::NO_CONTENT);

    // Deuxième appel avec le même token — token est NULLifié, doit renvoyer 404.
    let Some(state2) = test_state().await else {
        return;
    };
    let resp2 = app(state2)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/password/reset")
                .header("content-type", "application/json")
                .body(Body::from(format!(
                    r#"{{"token":"{}","new_password":"NewPass2"}}"#,
                    token
                )))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp2.status(), StatusCode::NOT_FOUND);

    let body = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "not_found");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_db)
        .await
        .unwrap();
}
