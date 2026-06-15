//! Tests d'intégration : GET /v1/account/dependents/{id}

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

const JWT_SECRET: &str = "test-jwt-secret-dependents-get-by-id";

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

// ── Test 1 : tutelle active → 200 avec tous les champs ────────────────────────

#[tokio::test]
async fn dependent_get_by_id_active_returns_200() {
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
    .bind(format!("guardian-byid+{}@nubia.test", guardian_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Gardien')",
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
    .bind(format!("dependent-byid+{}@nubia.test", dependent_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name, birth_date) \
         VALUES ($1, $2, 'Bob', 'Proche', '2015-03-10')",
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

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/account/dependents/{}", dependent_account_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(
        json["dependent_account_id"],
        dependent_account_id.to_string()
    );
    assert_eq!(json["first_name"], "Bob");
    assert_eq!(json["last_name"], "Proche");
    assert_eq!(json["birth_date"], "2015-03-10");
    assert_eq!(json["relationship"], "enfant");
}

// ── Test 2 : proche inexistant → 404 ──────────────────────────────────────────

#[tokio::test]
async fn dependent_get_by_id_unknown_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("unknown-dep+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Solo', 'Patient')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(user_id, account_id);
    let unknown_id = Uuid::new_v4();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/account/dependents/{}", unknown_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

// ── Test 3 : proche appartenant à un autre guardian → 404 (anti-énumération) ──

#[tokio::test]
async fn dependent_get_by_id_other_guardian_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    // Guardian A (the requester)
    let guardian_a_user_id = Uuid::new_v4();
    let guardian_a_account_id = Uuid::new_v4();

    // Guardian B (owns the dependent)
    let guardian_b_user_id = Uuid::new_v4();
    let guardian_b_account_id = Uuid::new_v4();

    // Dependent of guardian B
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();

    for (uid, email, aid, fname) in [
        (
            guardian_a_user_id,
            format!("ga+{}@nubia.test", guardian_a_user_id),
            guardian_a_account_id,
            "GuardianA",
        ),
        (
            guardian_b_user_id,
            format!("gb+{}@nubia.test", guardian_b_user_id),
            guardian_b_account_id,
            "GuardianB",
        ),
        (
            dependent_user_id,
            format!("dep-b+{}@nubia.test", dependent_user_id),
            dependent_account_id,
            "Dependent",
        ),
    ] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) \
             VALUES ($1, $2, 'hash', 'patient')",
        )
        .bind(uid)
        .bind(&email)
        .execute(&db)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
             VALUES ($1, $2, $3, 'Test')",
        )
        .bind(aid)
        .bind(uid)
        .bind(fname)
        .execute(&db)
        .await
        .unwrap();
    }

    // Guardian B → Dependent link
    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'enfant', true)",
        )
        .bind(guardian_b_account_id)
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
    // Guardian A tries to access Guardian B's dependent
    let token = make_patient_jwt(guardian_a_user_id, guardian_a_account_id);

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/account/dependents/{}", dependent_account_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

// ── Test 4 : pas de JWT → 401 ─────────────────────────────────────────────────

#[tokio::test]
async fn dependent_get_by_id_no_auth_returns_401() {
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
                .method("GET")
                .uri(format!("/v1/account/dependents/{}", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 5 : proche avec active=false → 404 ───────────────────────────────────

#[tokio::test]
async fn dependent_get_by_id_inactive_returns_404() {
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
    .bind(format!(
        "guardian-inactive-byid+{}@nubia.test",
        guardian_user_id
    ))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Gardien')",
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
    .bind(format!(
        "dep-inactive-byid+{}@nubia.test",
        dependent_user_id
    ))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'Inactif')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(&db)
    .await
    .unwrap();

    // Tutelle inactive (active=false)
    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'enfant', false)",
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

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/account/dependents/{}", dependent_account_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // La tutelle inactive ne doit pas être visible → 404
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}
