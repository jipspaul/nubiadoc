//! Tests d'intégration : POST /v1/pro/register

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

fn pro_register_body(email: &str) -> serde_json::Value {
    json!({
        "email": email,
        "password": "password1",
        "cabinet": {
            "raison_sociale": "Cabinet Dentaire Test",
            "siret": null,
            "specialite": "dentaire"
        },
        "practitioner": {
            "first_name": "Jean",
            "last_name": "Dupont",
            "rpps": null,
            "adeli": null
        }
    })
}

// ── Test 1 : happy path → 201 + { account_id, cabinet_id, provider_id, access_token } ──

#[tokio::test]
async fn pro_register_happy_path_returns_201() {
    if !db_available() {
        return;
    }
    let email = format!("pro_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;

    let response = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/pro/register")
                .header("content-type", "application/json")
                .body(Body::from(pro_register_body(&email).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(v["account_id"].is_string(), "account_id manquant");
    assert!(v["cabinet_id"].is_string(), "cabinet_id manquant");
    assert!(v["provider_id"].is_string(), "provider_id manquant");
    assert!(v["access_token"].is_string(), "access_token manquant");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 2 (#3748, anti-énumération) : email déjà pris → 201 générique, ─────
// pas 409 — sinon le statut HTTP est un oracle fiable d'existence de compte
// sur un endpoint anonyme sans rate-limit ni CAPTCHA. Réponse structurellement
// identique à un succès (mêmes champs, vrai JWT signé), mais aucun compte créé.

#[tokio::test]
async fn pro_register_duplicate_email_returns_201_generic_no_account_created() {
    if !db_available() {
        return;
    }
    let email = format!("pro_dup_{}@test.local", Uuid::new_v4());
    let owner = owner_pool().await;

    sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind) VALUES ($1, 'placeholder', 'pro')",
    )
    .bind(&email)
    .execute(&owner)
    .await
    .expect("insert existing user");

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/pro/register")
                .header("content-type", "application/json")
                .body(Body::from(pro_register_body(&email).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::CREATED,
        "email déjà pris doit renvoyer 201 générique, pas 409 (anti-énumération)"
    );

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    // Même forme qu'un succès réel : tous les champs présents, un vrai JWT.
    assert!(v["account_id"].is_string(), "account_id manquant");
    assert!(v["cabinet_id"].is_string(), "cabinet_id manquant");
    assert!(v["provider_id"].is_string(), "provider_id manquant");
    assert!(v["access_token"].is_string(), "access_token manquant");
    assert!(
        v["access_token"].as_str().unwrap().split('.').count() == 3,
        "access_token doit avoir la forme d'un JWT valide (3 segments)"
    );

    // Aucun 2e compte n'a été créé pour cet email (toujours l'unique placeholder).
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM app_user WHERE email = $1")
        .bind(&email)
        .fetch_one(&owner)
        .await
        .unwrap();
    assert_eq!(count, 1, "aucun 2e compte ne doit être créé");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner)
        .await
        .ok();
}
