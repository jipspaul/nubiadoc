//! Tests d'intégration : POST /v1/auth/mfa/verify
//!
//! Requiert un Postgres accessible via APP_DATABASE_URL / DATABASE_URL
//! (sidecar CI ou env local) et `KMS_MASTER_KEY` (posée par le test si
//! absente — le handler chiffre le secret TOTP avant de le persister).
//!
//! Le cas « `KMS_MASTER_KEY` absente/mal formée » (#6980, #7216) vit dans
//! `mfa_verify_kms_unconfigured.rs` : la variable est globale au process et
//! ce fichier-ci a besoin d'une clé valide.

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
    Argon2,
};
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use base64::{engine::general_purpose::STANDARD, Engine};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::time::{SystemTime, UNIX_EPOCH};
use totp_rs::{Algorithm, Secret, TOTP};
use tower::ServiceExt;
use uuid::Uuid;

const JWT_SECRET: &str = "test-jwt-secret-for-mfa-verify";

fn make_pro_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let claims = json!({"sub": user_id, "kind": "pro", "exp": exp});
    encode(
        &Header::default(),
        &claims,
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

/// Clé KMS de test (32 octets) si l'environnement n'en fournit pas — même
/// convention que `data_import.rs` / `hl7v2_adt.rs`.
fn ensure_kms_key() {
    if std::env::var("KMS_MASTER_KEY").is_err() {
        std::env::set_var("KMS_MASTER_KEY", STANDARD.encode([7u8; 32]));
    }
}

fn app_state(db: PgPool) -> nubia_api::AppState {
    nubia_api::AppState {
        db,
        jwt_secret: JWT_SECRET.into(),
        mailer: std::sync::Arc::new(nubia_api::StubMailer),
    }
}

fn hash_password(password: &str) -> String {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .unwrap()
        .to_string()
}

async fn json_body(response: axum::response::Response) -> serde_json::Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

fn post_json(uri: &str, bearer: Option<&str>, body: serde_json::Value) -> Request<Body> {
    let mut builder = Request::builder()
        .method("POST")
        .uri(uri)
        .header("Content-Type", "application/json");
    if let Some(token) = bearer {
        builder = builder.header("Authorization", format!("Bearer {token}"));
    }
    builder.body(Body::from(body.to_string())).unwrap()
}

/// Code TOTP courant calculé depuis le secret Base32 rendu par `/enroll`,
/// avec les paramètres annoncés par l'`otpauth_url` (SHA1, 6 chiffres, 30 s)
/// — exactement le calcul du scénario QA.
fn current_code(secret_b32: &str) -> String {
    let bytes = Secret::Encoded(secret_b32.to_string()).to_bytes().unwrap();
    TOTP::new(Algorithm::SHA1, 6, 1, 30, bytes)
        .unwrap()
        .generate_current()
        .unwrap()
}

async fn insert_test_user(pool: &PgPool) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query!(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        id,
        format!("mfa-test+{}@nubia.test", id),
    )
    .execute(pool)
    .await
    .unwrap();
    id
}

fn test_totp() -> (String, TOTP) {
    let secret = Secret::generate_secret();
    let secret_b32 = secret.to_encoded().to_string();
    let totp = TOTP::new(Algorithm::SHA1, 6, 1, 30, secret.to_bytes().unwrap()).unwrap();
    (secret_b32, totp)
}

// ── Test 1 : code valide → 200 + mfa_enabled = true en DB ─────────────────

#[tokio::test]
async fn mfa_verify_valid_totp_returns_200_and_activates_mfa() {
    // Skip when no DB is reachable (CI rust-ci.yml has no Postgres sidecar).
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    ensure_kms_key();
    let db = owner_pool().await;
    let user_id = insert_test_user(&db).await;
    let (secret_b32, totp) = test_totp();
    let code = totp.generate_current().unwrap();

    let state = nubia_api::AppState {
        db: app_pool().await,
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

    assert_eq!(response.status(), StatusCode::OK);

    let row = sqlx::query!("SELECT totp_enabled FROM app_user WHERE id = $1", user_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(row.totp_enabled);
}

// ── Test 2 : code invalide → 422 ──────────────────────────────────────────

#[tokio::test]
async fn mfa_verify_invalid_totp_returns_422() {
    // Skip when no DB is reachable (CI rust-ci.yml has no Postgres sidecar).
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    let db = owner_pool().await;
    let user_id = insert_test_user(&db).await;
    let (secret_b32, _) = test_totp();

    let state = nubia_api::AppState {
        db: app_pool().await,
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
                    json!({"totp_secret": secret_b32, "totp_code": "wrongcode"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 4 : JWT patient → 403 ────────────────────────────────────────────────
// ProClaims extractor : `kind != "pro"` → AppError::Forbidden.
// mfa/verify est pro-only ; un token patient valide doit retourner 403.

#[tokio::test]
async fn mfa_verify_patient_jwt_returns_403() {
    // Pas besoin d'un vrai DB — ProClaims extractor rejette avant d'accéder à la DB.
    let db = sqlx::PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = nubia_api::AppState {
        db,
        jwt_secret: JWT_SECRET.into(),
        mailer: std::sync::Arc::new(nubia_api::StubMailer),
    };

    let user_id = Uuid::new_v4();
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let patient_token = jsonwebtoken::encode(
        &jsonwebtoken::Header::default(),
        &serde_json::json!({"sub": user_id, "kind": "patient", "account_id": user_id, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let (secret_b32, _) = test_totp();

    let response = nubia_api::app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/verify")
                .header("Authorization", format!("Bearer {}", patient_token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::json!({"totp_secret": secret_b32, "totp_code": "123456"})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn mfa_verify_without_jwt_returns_401() {
    // Skip when no DB is reachable (CI rust-ci.yml has no Postgres sidecar).
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    let (secret_b32, _) = test_totp();

    let state = nubia_api::AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.into(),
        mailer: std::sync::Arc::new(nubia_api::StubMailer),
    };
    let response = nubia_api::app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/mfa/verify")
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"totp_secret": secret_b32, "totp_code": "123456"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Scénario QA #6980 / #7216 : enroll → verify (code calculé depuis le
//    secret rendu) → MFA active → le login exige ensuite le code ────────────

#[tokio::test]
async fn mfa_enroll_then_verify_activates_mfa_and_login_requires_code() {
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    ensure_kms_key();
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let email = format!("mfa-flow+{user_id}@nubia.test");
    let password = "password123";
    sqlx::query("INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, $3, 'pro')")
        .bind(user_id)
        .bind(&email)
        .bind(hash_password(password))
        .execute(&db)
        .await
        .unwrap();
    let jwt = make_pro_jwt(user_id);

    // 1. enroll → 200 {totp_secret, otpauth_url}
    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json("/v1/auth/mfa/enroll", Some(&jwt), json!({})))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let enroll = json_body(response).await;
    let secret_b32 = enroll["totp_secret"].as_str().unwrap().to_string();
    assert!(enroll["otpauth_url"]
        .as_str()
        .unwrap()
        .contains("algorithm=SHA1&digits=6&period=30"));

    // 2. verify avec le code VALIDE calculé depuis ce secret → 200, jamais 500
    let code = current_code(&secret_b32);
    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/mfa/verify",
            Some(&jwt),
            json!({"totp_secret": secret_b32, "totp_code": code}),
        ))
        .await
        .unwrap();
    let status = response.status();
    let body = json_body(response).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["message"], "MFA activée.");

    // 3. persistance : totp_enabled + enrôlement chiffré (jamais le secret en clair)
    let row = sqlx::query!("SELECT totp_enabled FROM app_user WHERE id = $1", user_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(row.totp_enabled);
    let enrollment = sqlx::query(
        "SELECT secret_ciphertext, secret_key_ref, verified FROM mfa_enrollment \
         WHERE app_user_id = $1 AND method = 'totp'",
    )
    .bind(user_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let ciphertext: Vec<u8> = sqlx::Row::get(&enrollment, "secret_ciphertext");
    let key_ref: String = sqlx::Row::get(&enrollment, "secret_key_ref");
    let verified: bool = sqlx::Row::get(&enrollment, "verified");
    assert!(verified);
    assert!(key_ref.starts_with("local:"));
    assert_ne!(ciphertext, secret_b32.as_bytes());

    // 4. login sans code → 401 mfa_required
    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/login",
            None,
            json!({"email": email, "password": password}),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    assert_eq!(json_body(response).await["code"], "mfa_required");

    // 5. login avec un code faux → 401 (neutre), pas 500
    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/login",
            None,
            json!({"email": email, "password": password, "mfa_code": "000000"}),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);

    // 6. login avec le code courant → 200 + access_token (déchiffrement du
    //    secret via la même clé KMS)
    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/login",
            None,
            json!({"email": email, "password": password, "mfa_code": current_code(&secret_b32)}),
        ))
        .await
        .unwrap();
    let status = response.status();
    let body = json_body(response).await;
    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert!(body["access_token"].as_str().is_some_and(|t| !t.is_empty()));
}

// ── Contre-épreuves QA : code faux (000000) → 422, secret illisible → 422 ──

#[tokio::test]
async fn mfa_verify_wrong_code_000000_returns_422_and_writes_nothing() {
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    ensure_kms_key();
    let db = owner_pool().await;
    let user_id = insert_test_user(&db).await;
    let (secret_b32, _) = test_totp();

    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/mfa/verify",
            Some(&make_pro_jwt(user_id)),
            json!({"totp_secret": secret_b32, "totp_code": "000000"}),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(json_body(response).await["code"], "validation_error");

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
}

#[tokio::test]
async fn mfa_verify_unreadable_secret_returns_422() {
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    ensure_kms_key();
    let db = owner_pool().await;
    let user_id = insert_test_user(&db).await;

    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/mfa/verify",
            Some(&make_pro_jwt(user_id)),
            json!({"totp_secret": "PAS-DU-BASE32!", "totp_code": "123456"}),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(json_body(response).await["code"], "validation_error");
}

// ── Ré-enrôlement : un second verify (nouveau secret) REMPLACE l'enrôlement
//    (une seule ligne `mfa_enrollment`), et rejouer le code du 1er secret
//    ne réactive pas l'ancien. Pas d'anti-replay par code prévu à ce jour :
//    un verify avec le même secret + un code encore dans la fenêtre est
//    idempotent (200), il n'active rien de plus. ─────────────────────────

#[tokio::test]
async fn mfa_verify_again_replaces_enrollment_with_single_row() {
    if std::env::var("APP_DATABASE_URL").is_err() || std::env::var("DATABASE_URL").is_err() {
        return;
    }
    ensure_kms_key();
    let db = owner_pool().await;
    let user_id = insert_test_user(&db).await;
    let jwt = make_pro_jwt(user_id);
    let (first_secret, _) = test_totp();
    let (second_secret, _) = test_totp();

    for secret in [&first_secret, &second_secret] {
        let response = nubia_api::app(app_state(app_pool().await))
            .oneshot(post_json(
                "/v1/auth/mfa/verify",
                Some(&jwt),
                json!({"totp_secret": secret, "totp_code": current_code(secret)}),
            ))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }

    // Rejeu du même code (même secret, même fenêtre) : idempotent, pas de 500.
    let response = nubia_api::app(app_state(app_pool().await))
        .oneshot(post_json(
            "/v1/auth/mfa/verify",
            Some(&jwt),
            json!({"totp_secret": second_secret, "totp_code": current_code(&second_secret)}),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM mfa_enrollment WHERE app_user_id = $1 AND method = 'totp'",
    )
    .bind(user_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(count, 1, "un ré-enrôlement remplace, il n'empile pas");
}
