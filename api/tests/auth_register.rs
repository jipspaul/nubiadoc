//! Tests d'intégration : POST /v1/auth/register

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

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

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

// ── Test 1 : happy path → 201 + { account_id, access_token, refresh_token } ──

#[tokio::test]
async fn register_happy_path_returns_201_with_tokens() {
    if !db_available() {
        return;
    }
    let email = format!("reg_{}@test.local", Uuid::new_v4());
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": email,
                        "password": "password1",
                        "accept_cgu": true,
                        "cgu_version": "v1"
                    })
                    .to_string(),
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
    assert!(v["account_id"].is_string(), "account_id doit être présent");
    assert!(
        v["access_token"].is_string(),
        "access_token doit être présent"
    );
    assert!(
        v["refresh_token"].is_string(),
        "refresh_token doit être présent"
    );

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 2 : email déjà existant → 201 leurre (anti-énumération, #4436) ─────
// Parité avec login/forgot (§1.8) : un email déjà pris renvoie la même forme
// de réponse (201, account_id/access_token/refresh_token) qu'une création
// réussie, sans créer de second compte ni exposer de token exploitable pour
// le compte existant.

#[tokio::test]
async fn register_duplicate_email_returns_decoy_201() {
    if !db_available() {
        return;
    }
    let email = format!("dup_{}@test.local", Uuid::new_v4());
    let db = owner_pool().await;

    sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind) VALUES ($1, 'placeholder', 'patient')",
    )
    .bind(&email)
    .execute(&db)
    .await
    .expect("insert test user");

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": email,
                        "password": "password1",
                        "accept_cgu": true,
                        "cgu_version": "v1"
                    })
                    .to_string(),
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
    assert!(v["account_id"].is_string());
    assert!(v["access_token"].is_string());
    assert!(v["refresh_token"].is_string());

    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM app_user WHERE email = $1")
        .bind(&email)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(count, 1, "aucun second compte ne doit être créé");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3b : mot de passe trop court → 422 password_policy ─────────────────
// Handler check : `body.password.len() < 8` → AppError::PasswordPolicy
// Pas besoin de DB (vérif avant toute requête SQLx).

#[tokio::test]
async fn register_password_too_short_returns_422_password_policy() {
    let db = sqlx::PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": format!("pw_short_{}@test.local", Uuid::new_v4()),
                        "password": "Ab1",
                        "accept_cgu": true,
                        "cgu_version": "v1"
                    })
                    .to_string(),
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

// ── Test 3c : mot de passe sans chiffre → 422 password_policy ────────────────
// Handler check : `!body.password.chars().any(|c| c.is_ascii_digit())` → AppError::PasswordPolicy

#[tokio::test]
async fn register_password_no_digit_returns_422_password_policy() {
    let db = sqlx::PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": format!("pw_nodigit_{}@test.local", Uuid::new_v4()),
                        "password": "NoDigitPass",
                        "accept_cgu": true,
                        "cgu_version": "v1"
                    })
                    .to_string(),
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

// ── Test 4 : invitation_token valide → 201 + JWT pro ─────────────────────────

#[tokio::test]
async fn register_with_valid_invite_token_returns_201() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let email = format!("invite_{}@test.local", Uuid::new_v4());
    let raw_token = Uuid::new_v4().to_string();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Test Cabinet Invite', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&owner_db)
    .await
    .expect("insert cabinet");

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind, \
         password_reset_token, password_reset_expires_at) \
         VALUES ($1, $2, NULL, 'pro', \
                 encode(digest($3, 'sha256'), 'hex'), now() + interval '72 hours')",
    )
    .bind(user_id)
    .bind(&email)
    .bind(&raw_token)
    .execute(&owner_db)
    .await
    .expect("insert invited user");

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES ($1, $2, 'secretary')",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .execute(&owner_db)
    .await
    .expect("insert membership");

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": email,
                        "password": "password1",
                        "accept_cgu": true,
                        "cgu_version": "v1",
                        "invitation_token": raw_token
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let body_bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body_bytes).unwrap();
    assert!(v["account_id"].is_string(), "account_id doit être présent");
    assert!(
        v["access_token"].is_string(),
        "access_token doit être présent"
    );
    assert!(
        v["refresh_token"].is_string(),
        "refresh_token doit être présent"
    );

    sqlx::query("DELETE FROM cabinet_membership WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&owner_db)
        .await
        .ok();
    sqlx::query("DELETE FROM refresh_token WHERE app_user_id = $1")
        .bind(user_id)
        .execute(&owner_db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&owner_db)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&owner_db)
        .await
        .ok();
}

// ── Test 5 : invitation_token invalide → 400 invitation_invalid ───────────────

#[tokio::test]
async fn register_with_invalid_invite_token_returns_400() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": format!("invalid_invite_{}@test.local", Uuid::new_v4()),
                        "password": "password1",
                        "accept_cgu": true,
                        "cgu_version": "v1",
                        "invitation_token": "totally-invalid-token-that-does-not-exist"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

    let body_bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(v["code"], "invitation_invalid");
}

// ── Test 3 : accept_cgu: false → 422 cgu_required ────────────────────────────

#[tokio::test]
async fn register_cgu_not_accepted_returns_422() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": "cgu@test.local",
                        "password": "password1",
                        "accept_cgu": false,
                        "cgu_version": "v1"
                    })
                    .to_string(),
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
    assert_eq!(v["code"], "cgu_required");
}

// ── Tests invitation_token ────────────────────────────────────────────────────

/// Crée un utilisateur invité (password_hash=NULL) avec membership dans un cabinet.
/// Retourne (user_id, cabinet_id, raw_invite_token).
async fn create_invited_secretary(db: &PgPool) -> (Uuid, Uuid, String) {
    let user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let raw_token = uuid::Uuid::new_v4().to_string();

    sqlx::query(
        "INSERT INTO app_user \
         (id, email, password_hash, kind, \
          password_reset_token, password_reset_expires_at) \
         VALUES ($1, $2, NULL, 'pro', \
                 encode(digest($3, 'sha256'), 'hex'), now() + interval '72 hours')",
    )
    .bind(user_id)
    .bind(format!("invited-sec-{}@test.local", user_id))
    .bind(&raw_token)
    .execute(db)
    .await
    .expect("insert invited app_user");

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentiste')")
        .bind(cabinet_id)
        .bind(format!("Cabinet invite {}", user_id))
        .execute(db)
        .await
        .expect("insert cabinet");

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) \
         VALUES ($1, $2, 'secretary', true)",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .execute(db)
    .await
    .expect("insert cabinet_membership");

    (user_id, cabinet_id, raw_token)
}

async fn cleanup_invited(db: &PgPool, user_id: Uuid, cabinet_id: Uuid) {
    sqlx::query("DELETE FROM cabinet_membership WHERE user_id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM refresh_token WHERE app_user_id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
}

// ── Test invitation 1 : token valide → 201 + access_token pro ────────────────

#[tokio::test]
async fn register_with_valid_invitation_token_returns_201() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let (user_id, cabinet_id, raw_token) = create_invited_secretary(&owner_db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": format!("invited-sec-{}@test.local", user_id),
                        "password": "password1",
                        "accept_cgu": true,
                        "cgu_version": "v1",
                        "invitation_token": raw_token
                    })
                    .to_string(),
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
    assert!(v["account_id"].is_string(), "account_id doit être présent");
    assert!(
        v["access_token"].is_string(),
        "access_token doit être présent"
    );
    assert!(
        v["refresh_token"].is_string(),
        "refresh_token doit être présent"
    );

    cleanup_invited(&owner_db, user_id, cabinet_id).await;
}

// ── Test invitation 2 : token invalide → 400 invitation_invalid ──────────────

#[tokio::test]
async fn register_with_invalid_invitation_token_returns_400() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": "anyone@test.local",
                        "password": "password1",
                        "accept_cgu": true,
                        "cgu_version": "v1",
                        "invitation_token": "totally-invalid-token-that-does-not-exist"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "invitation_invalid");
}

// ── Test invitation 3 : token expiré → 400 invitation_invalid ────────────────

#[tokio::test]
async fn register_with_expired_invitation_token_returns_400() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let raw_token = uuid::Uuid::new_v4().to_string();

    sqlx::query(
        "INSERT INTO app_user \
         (id, email, password_hash, kind, \
          password_reset_token, password_reset_expires_at) \
         VALUES ($1, $2, NULL, 'pro', \
                 encode(digest($3, 'sha256'), 'hex'), now() - interval '1 hour')",
    )
    .bind(user_id)
    .bind(format!("expired-inv-{}@test.local", user_id))
    .bind(&raw_token)
    .execute(&owner_db)
    .await
    .expect("insert expired invited app_user");

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentiste')")
        .bind(cabinet_id)
        .bind(format!("Cabinet expired {}", user_id))
        .execute(&owner_db)
        .await
        .expect("insert cabinet");

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) \
         VALUES ($1, $2, 'secretary', true)",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .execute(&owner_db)
    .await
    .expect("insert cabinet_membership");

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": format!("expired-inv-{}@test.local", user_id),
                        "password": "password1",
                        "accept_cgu": true,
                        "cgu_version": "v1",
                        "invitation_token": raw_token
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "invitation_invalid");

    cleanup_invited(&owner_db, user_id, cabinet_id).await;
}
