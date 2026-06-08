//! Tests d'intégration : GET /v1/me

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

const JWT_SECRET: &str = "test-jwt-secret-me";

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

// ── Test 1 : JWT patient valide → 200 + kind:"patient" + account_id non null ─

#[tokio::test]
async fn me_patient_jwt_returns_200_with_account_id() {
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
    .bind(format!("me-patient+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES ($1, $2, '', '')",
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

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["kind"], "patient");
    assert!(
        v["account_id"].is_string(),
        "account_id doit être non null pour un patient"
    );
    assert_eq!(v["user_id"], user_id.to_string());
    assert!(v["memberships"].is_array());

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : JWT pro valide → 200 + kind:"pro" ────────────────────────────────

#[tokio::test]
async fn me_pro_jwt_returns_200_with_kind_pro() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("me-pro+{}@nubia.test", user_id))
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
                .method("GET")
                .uri("/v1/me")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["kind"], "pro");
    assert_eq!(v["user_id"], user_id.to_string());
    assert!(v["memberships"].is_array());

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 4 : pro sans membership → memberships:[] ─────────────────────────────

#[tokio::test]
async fn me_pro_no_membership_returns_empty_memberships() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("me-pro-nomem+{}@nubia.test", user_id))
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
                .method("GET")
                .uri("/v1/me")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["memberships"], serde_json::json!([]));

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 5 : pro avec 1 membership → memberships:[{cabinet_id, role}] ─────────

#[tokio::test]
async fn me_pro_one_membership_returns_one_entry() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("me-pro-1mem+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet Test 1', 'dentiste')",
    )
    .bind(cabinet_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) VALUES ($1, $2, 'admin', true)",
    )
    .bind(cabinet_id)
    .bind(user_id)
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
                .method("GET")
                .uri("/v1/me")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let memberships = v["memberships"].as_array().unwrap();
    assert_eq!(memberships.len(), 1);
    assert_eq!(memberships[0]["cabinet_id"], cabinet_id.to_string());
    assert_eq!(memberships[0]["role"], "admin");

    sqlx::query("DELETE FROM cabinet_membership WHERE user_id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 6 : pro avec 2 memberships → memberships avec 2 entrées ──────────────

#[tokio::test]
async fn me_pro_two_memberships_returns_two_entries() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let cabinet_id_a = Uuid::new_v4();
    let cabinet_id_b = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("me-pro-2mem+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    for (cabinet_id, name) in [(cabinet_id_a, "Cabinet 2A"), (cabinet_id_b, "Cabinet 2B")] {
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentiste')",
        )
        .bind(cabinet_id)
        .bind(name)
        .execute(&db)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) VALUES ($1, $2, 'practitioner', true)",
        )
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let memberships = v["memberships"].as_array().unwrap();
    assert_eq!(memberships.len(), 2);
    let cabinet_ids: std::collections::HashSet<String> = memberships
        .iter()
        .map(|m| m["cabinet_id"].as_str().unwrap().to_string())
        .collect();
    assert!(cabinet_ids.contains(&cabinet_id_a.to_string()));
    assert!(cabinet_ids.contains(&cabinet_id_b.to_string()));

    for cabinet_id in [cabinet_id_a, cabinet_id_b] {
        sqlx::query("DELETE FROM cabinet_membership WHERE user_id = $1 AND cabinet_id = $2")
            .bind(user_id)
            .bind(cabinet_id)
            .execute(&db)
            .await
            .ok();
        sqlx::query("DELETE FROM cabinet WHERE id = $1")
            .bind(cabinet_id)
            .execute(&db)
            .await
            .ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

#[tokio::test]
async fn me_no_jwt_returns_401() {
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
                .uri("/v1/me")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
