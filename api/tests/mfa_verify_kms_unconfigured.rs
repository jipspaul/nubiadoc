//! Tests d'intégration : POST /v1/auth/mfa/verify sans clé KMS exploitable
//! (#6980 / #7216).
//!
//! Fichier séparé de `mfa_verify.rs` : `KMS_MASTER_KEY` est une variable
//! d'environnement globale au process de test, on ne peut pas la casser
//! dans le même binaire que les tests qui en ont besoin.
//!
//! Scénario QA : sur le LXC, `KMS_MASTER_KEY` n'était jamais transmise au
//! conteneur → un code TOTP VALIDE répondait `500 internal_error` (un code
//! faux, lui, `422`), la MFA était inactivable. Attendu désormais : `503
//! kms_not_configured` explicite, rien n'est persisté (fail-closed), et un
//! code faux reste `422` (validé avant toute persistance).
//!
//! Requiert un Postgres accessible via APP_DATABASE_URL / DATABASE_URL.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::time::{SystemTime, UNIX_EPOCH};
use totp_rs::{Algorithm, Secret, TOTP};
use tower::ServiceExt;
use uuid::Uuid;

const JWT_SECRET: &str = "test-jwt-secret-for-mfa-verify-kms";

fn make_pro_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
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

async fn verify(
    db: PgPool,
    user_id: Uuid,
    secret_b32: &str,
    code: &str,
) -> (StatusCode, serde_json::Value) {
    let state = nubia_api::AppState {
        db,
        jwt_secret: JWT_SECRET.into(),
        mailer: std::sync::Arc::new(nubia_api::StubMailer),
    };
    let response = nubia_api::app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/verify")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"totp_secret": secret_b32, "totp_code": code}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (status, serde_json::from_slice(&bytes).unwrap())
}

#[tokio::test]
async fn mfa_verify_valid_code_without_kms_key_returns_503_not_500_and_persists_nothing() {
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    // Reproduit l'environnement du LXC : la variable n'est pas exploitable
    // (ici mal formée ; absente donne le même contrat, cf. `kms_env`).
    std::env::set_var("KMS_MASTER_KEY", "pas-du-base64!");

    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    sqlx::query!(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        user_id,
        format!("mfa-kms+{}@nubia.test", user_id),
    )
    .execute(&db)
    .await
    .unwrap();

    let secret = Secret::generate_secret();
    let secret_b32 = secret.to_encoded().to_string();
    let totp = TOTP::new(Algorithm::SHA1, 6, 1, 30, secret.to_bytes().unwrap()).unwrap();

    // Code VALIDE : erreur explicite, jamais 500.
    let (status, body) = verify(
        app_pool().await,
        user_id,
        &secret_b32,
        &totp.generate_current().unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE, "body: {body}");
    assert_eq!(body["code"], "kms_not_configured");

    // Fail-closed : rien n'est écrit.
    let row = sqlx::query!("SELECT totp_enabled FROM app_user WHERE id = $1", user_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(!row.totp_enabled);
    let count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM mfa_enrollment WHERE app_user_id = $1")
            .bind(user_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(count, 0);

    // Code FAUX : toujours 422 (validé avant la clé KMS), comme observé par la QA.
    let (status, body) = verify(app_pool().await, user_id, &secret_b32, "000000").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "body: {body}");
    assert_eq!(body["code"], "validation_error");
}
