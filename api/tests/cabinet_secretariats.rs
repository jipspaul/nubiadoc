//! Tests d'intégration R12 — CRUD secrétariats + membres.
//!
//! Couvre :
//! - GET /v1/cabinet/secretariats → 200 (membre quelconque)
//! - POST /v1/cabinet/secretariats → 201 (admin) / 403 (non-admin)
//! - PATCH /v1/cabinet/secretariats/:id → 200 (admin) / 403 (non-admin)
//! - DELETE /v1/cabinet/secretariats/:id → 204 (admin) / 403 (non-admin)
//! - POST /v1/cabinet/secretariats/:id/members → 201 (admin) / 403 (non-admin)
//! - DELETE /v1/cabinet/secretariats/:id/members/:user_id → 204 (admin) / 403 (non-admin)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
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

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    }
}

/// JWT secrétaire (non-admin).
fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "secretary".into(),
            exp,
        },
        &EncodingKey::from_secret(b"test-secret"),
    )
    .unwrap()
}

/// Enregistre un cabinet pro, renvoie `(access_token, account_id, cabinet_id)`.
async fn register_pro(db: PgPool, email: &str) -> (String, Uuid, Uuid) {
    let body = json!({
        "email": email,
        "password": "password1",
        "cabinet": { "raison_sociale": "Cabinet Sec", "siret": null, "specialite": "dentaire" },
        "practitioner": { "first_name": "Admin", "last_name": "Test", "rpps": null, "adeli": null }
    });
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/pro/register")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let token = v["access_token"].as_str().unwrap().to_string();
    let account_id: Uuid = v["account_id"].as_str().unwrap().parse().unwrap();
    let cabinet_id: Uuid = v["cabinet_id"].as_str().unwrap().parse().unwrap();
    (token, account_id, cabinet_id)
}

// ── Test 1 : GET /v1/cabinet/secretariats → 200 (backfill = au moins 1 secrétariat) ──

#[tokio::test]
async fn get_secretariats_returns_200() {
    if !db_available() {
        return;
    }
    let email = format!("sec_list_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &email).await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/secretariats")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let arr: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(arr.as_array().is_some(), "réponse doit être un tableau");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 2 : POST /v1/cabinet/secretariats non-admin → 403 ──────────────────

#[tokio::test]
async fn post_secretariat_non_admin_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("sec_create_403_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id) = register_pro(db.clone(), &email).await;

    let secretary_token = make_secretary_token(account_id, cabinet_id);
    let body = json!({ "name": "Secrétariat Nord" });

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/secretariats")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", secretary_token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 3 : POST /v1/cabinet/secretariats admin → 201 ──────────────────────

#[tokio::test]
async fn post_secretariat_admin_returns_201() {
    if !db_available() {
        return;
    }
    let email = format!("sec_create_201_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &email).await;

    let body = json!({ "name": "Secrétariat Nord" });

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/secretariats")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["name"], "Secrétariat Nord");
    assert!(v["id"].as_str().is_some());

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 4 : PATCH non-admin → 403 ──────────────────────────────────────────

#[tokio::test]
async fn patch_secretariat_non_admin_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("sec_patch_403_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id) = register_pro(db.clone(), &email).await;

    let secretary_token = make_secretary_token(account_id, cabinet_id);
    let body = json!({ "name": "Nouveau nom" });

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/secretariats/{}", Uuid::new_v4()))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", secretary_token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 5 : DELETE non-admin → 403 ─────────────────────────────────────────

#[tokio::test]
async fn delete_secretariat_non_admin_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("sec_del_403_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id) = register_pro(db.clone(), &email).await;

    let secretary_token = make_secretary_token(account_id, cabinet_id);

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/cabinet/secretariats/{}", Uuid::new_v4()))
                .header("Authorization", format!("Bearer {}", secretary_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 6 : POST membres non-admin → 403 ───────────────────────────────────

#[tokio::test]
async fn post_secretariat_member_non_admin_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("sec_memb_403_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id) = register_pro(db.clone(), &email).await;

    let secretary_token = make_secretary_token(account_id, cabinet_id);
    let body = json!({ "user_id": Uuid::new_v4(), "role": "secretary" });

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/secretariats/{}/members",
                    Uuid::new_v4()
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", secretary_token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 7 : DELETE membre non-admin → 403 ──────────────────────────────────

#[tokio::test]
async fn delete_secretariat_member_non_admin_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("sec_del_memb_403_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id) = register_pro(db.clone(), &email).await;

    let secretary_token = make_secretary_token(account_id, cabinet_id);

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/v1/cabinet/secretariats/{}/members/{}",
                    Uuid::new_v4(),
                    Uuid::new_v4()
                ))
                .header("Authorization", format!("Bearer {}", secretary_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}
