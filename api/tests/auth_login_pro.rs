//! Tests d'intégration : R3 — login pro → cabinet/agenda (garde régression R1 PR #1093)
//!
//! Vérifie que le login `practitioner` et `secretary` émet un token portant `cabinet_id`
//! (issu d'un membership unique) et que ce token donne accès à `GET /v1/cabinet/agenda`.
//! Vérifie aussi le cloisonnement clinique et le cas pro sans membership.

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
    Argon2,
};
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{decode, DecodingKey, Validation};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-login-pro";

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

fn hash_password(password: &str) -> String {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .unwrap()
        .to_string()
}

async fn make_state() -> AppState {
    AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

/// Crée un pro avec membership dans un cabinet. Retourne `(user_id, cabinet_id, email)`.
async fn create_pro_with_membership(db: &PgPool, role: &str) -> (Uuid, Uuid, String, String) {
    let user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let email = format!("login-pro-{}-{}@test.local", role, user_id);
    let password = "password123";
    let hash = hash_password(password);

    sqlx::query("INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, $3, 'pro')")
        .bind(user_id)
        .bind(&email)
        .bind(&hash)
        .execute(db)
        .await
        .expect("insert app_user");

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentiste')")
        .bind(cabinet_id)
        .bind(format!("Cabinet {}", role))
        .execute(db)
        .await
        .expect("insert cabinet");

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) \
         VALUES ($1, $2, $3, true)",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .bind(role)
    .execute(db)
    .await
    .expect("insert cabinet_membership");

    (user_id, cabinet_id, email, password.to_string())
}

/// Supprime les fixtures créées par `create_pro_with_membership`.
async fn cleanup_pro(db: &PgPool, user_id: Uuid, cabinet_id: Uuid) {
    sqlx::query("DELETE FROM cabinet_membership WHERE user_id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : practitioner — login → token avec cabinet_id → agenda 200 ────────

#[tokio::test]
async fn login_practitioner_then_agenda_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, cabinet_id, email, password) =
        create_pro_with_membership(&db, "practitioner").await;

    let state = make_state().await;

    // 1. Login
    let login_resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email": email, "password": password}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        login_resp.status(),
        StatusCode::OK,
        "login practitioner doit retourner 200"
    );

    let body = axum::body::to_bytes(login_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let token = v["access_token"].as_str().expect("access_token absent");

    // 2. Le token doit porter cabinet_id (ProRegisterClaims — membership unique).
    let key = DecodingKey::from_secret(JWT_SECRET.as_bytes());
    let mut validation = Validation::default();
    validation.validate_exp = false; // pas besoin de vérifier l'exp dans le test
    let claims: serde_json::Value = decode::<serde_json::Value>(token, &key, &validation)
        .expect("JWT invalide")
        .claims;
    assert_eq!(
        claims["cabinet_id"]
            .as_str()
            .and_then(|s| s.parse::<Uuid>().ok()),
        Some(cabinet_id),
        "token practitioner doit porter cabinet_id du membership"
    );
    assert_eq!(claims["role"], "practitioner");

    // 3. GET /v1/cabinet/agenda avec ce token → 200
    let agenda_resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/agenda")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        agenda_resp.status(),
        StatusCode::OK,
        "GET /v1/cabinet/agenda pour practitioner doit retourner 200"
    );

    cleanup_pro(&db, user_id, cabinet_id).await;
}

// ── Test 2 : secretary — login → token avec cabinet_id → agenda 200 ───────────

#[tokio::test]
async fn login_secretary_then_agenda_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, cabinet_id, email, password) = create_pro_with_membership(&db, "secretary").await;

    let state = make_state().await;

    // 1. Login
    let login_resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email": email, "password": password}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        login_resp.status(),
        StatusCode::OK,
        "login secretary doit retourner 200"
    );

    let body = axum::body::to_bytes(login_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let token = v["access_token"].as_str().expect("access_token absent");

    // 2. Le token doit porter cabinet_id.
    let key = DecodingKey::from_secret(JWT_SECRET.as_bytes());
    let mut validation = Validation::default();
    validation.validate_exp = false;
    let claims: serde_json::Value = decode::<serde_json::Value>(token, &key, &validation)
        .expect("JWT invalide")
        .claims;
    assert_eq!(
        claims["cabinet_id"]
            .as_str()
            .and_then(|s| s.parse::<Uuid>().ok()),
        Some(cabinet_id),
        "token secretary doit porter cabinet_id du membership"
    );
    assert_eq!(claims["role"], "secretary");

    // 3. GET /v1/cabinet/agenda avec ce token → 200
    let agenda_resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/agenda")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        agenda_resp.status(),
        StatusCode::OK,
        "GET /v1/cabinet/agenda pour secretary doit retourner 200"
    );

    cleanup_pro(&db, user_id, cabinet_id).await;
}

// ── Test 3 : secretary + scope=clinical → 403 (champ clinique cloisonné) ───────

#[tokio::test]
async fn login_secretary_clinical_scope_conversations_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, cabinet_id, email, password) = create_pro_with_membership(&db, "secretary").await;

    let state = make_state().await;

    // Login
    let login_resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email": email, "password": password}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(login_resp.status(), StatusCode::OK);

    let body = axum::body::to_bytes(login_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let token = v["access_token"].as_str().expect("access_token absent");

    // GET /v1/cabinet/conversations?scope=clinical → 403 (cloisonnement §07 §4.1)
    let conv_resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/conversations?scope=clinical")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        conv_resp.status(),
        StatusCode::FORBIDDEN,
        "secretary ne doit pas accéder aux conversations scope=clinical"
    );

    cleanup_pro(&db, user_id, cabinet_id).await;
}

// ── Test 4 : pro sans membership → token nu (pas de cabinet_id) ───────────────

#[tokio::test]
async fn login_pro_without_membership_emits_naked_token() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let email = format!("login-pro-nomembership-{}@test.local", user_id);
    let password = "password123";
    let hash = hash_password(password);

    sqlx::query("INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, $3, 'pro')")
        .bind(user_id)
        .bind(&email)
        .bind(&hash)
        .execute(&db)
        .await
        .expect("insert app_user sans membership");

    let state = make_state().await;

    let login_resp = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"email": email, "password": password}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        login_resp.status(),
        StatusCode::OK,
        "pro sans membership doit quand même retourner 200"
    );

    let body = axum::body::to_bytes(login_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let token = v["access_token"].as_str().expect("access_token absent");

    // Le token doit être un ProClaims nu : pas de cabinet_id.
    let key = DecodingKey::from_secret(JWT_SECRET.as_bytes());
    let mut validation = Validation::default();
    validation.validate_exp = false;
    let claims: serde_json::Value = decode::<serde_json::Value>(token, &key, &validation)
        .expect("JWT invalide")
        .claims;

    assert!(
        claims["cabinet_id"].is_null(),
        "pro sans membership : cabinet_id doit être absent du token (token nu)"
    );
    assert_eq!(claims["kind"], "pro");

    // context_required absent (0 memberships → pas de multi-appartenance)
    assert!(
        v["context_required"].is_null(),
        "0 membership → context_required ne doit pas être présent"
    );

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}
