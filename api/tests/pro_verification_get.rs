//! Tests d'intégration : GET /v1/pro/verification

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

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    }
}

/// Enregistre un pro et renvoie son access_token (portant cabinet_id + role:"admin").
async fn register_pro(db: PgPool, email: &str) -> String {
    let body = json!({
        "email": email,
        "password": "password1",
        "cabinet": { "raison_sociale": "Cabinet Test", "siret": null, "specialite": "dentaire" },
        "practitioner": { "first_name": "Jean", "last_name": "Dupont", "rpps": null, "adeli": null }
    });
    let response = app(make_state(db))
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
    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    v["access_token"].as_str().unwrap().to_string()
}

// ── Test 1 : GET après un POST → 200 avec status:"pending" ───────────────────

#[tokio::test]
async fn get_pro_verification_after_post_returns_200_pending() {
    if !db_available() {
        return;
    }
    let email = format!("get_verif_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let token = register_pro(db.clone(), &email).await;

    // POST pour créer un enregistrement pending
    let post_resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/pro/verification")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({"id_type": "rpps", "identifier": "12345678901"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(post_resp.status(), StatusCode::ACCEPTED);

    // GET doit renvoyer 200 avec le même enregistrement
    let get_resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/pro/verification")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_resp.status(), StatusCode::OK);

    let bytes = axum::body::to_bytes(get_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["verification_id"].is_string(), "verification_id manquant");
    assert_eq!(v["id_type"], "rpps");
    assert_eq!(v["identifier"], "12345678901");
    assert_eq!(v["status"], "pending");
    assert!(v["created_at"].is_string(), "created_at manquant");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 2 : GET sans enregistrement préalable → 404 ─────────────────────────

#[tokio::test]
async fn get_pro_verification_without_record_returns_404() {
    if !db_available() {
        return;
    }
    let email = format!("get_verif_empty_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let token = register_pro(db.clone(), &email).await;

    let get_resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/pro/verification")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_resp.status(), StatusCode::NOT_FOUND);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}
