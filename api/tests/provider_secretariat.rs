//! Tests d'intégration R11 — assignation docteur ↔ secrétariat.
//!
//! Couvre :
//! - GET /v1/cabinet/providers/:id/secretariats → 200 (admin) ; liste les assignations actives
//! - GET /v1/cabinet/providers/:id/secretariats → 403 (secretary)
//! - PUT /v1/cabinet/providers/:id/secretariats → remplace ; vérifie row count dans provider_secretariat

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::{PgPool, Row};
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

/// JWT secrétaire (bloqué sur R11).
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

/// Enregistre un cabinet pro, renvoie `(access_token, account_id, cabinet_id, provider_id)`.
async fn register_pro(db: PgPool, email: &str) -> (String, Uuid, Uuid, Uuid) {
    let body = json!({
        "email": email,
        "password": "password1",
        "cabinet": { "raison_sociale": "Cabinet R11", "siret": null, "specialite": "dentaire" },
        "practitioner": { "first_name": "Admin", "last_name": "R11", "rpps": null, "adeli": null }
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
    let provider_id: Uuid = v["provider_id"].as_str().unwrap().parse().unwrap();
    (token, account_id, cabinet_id, provider_id)
}

/// Crée un secrétariat dans le cabinet et renvoie son id.
async fn create_secretariat(db: PgPool, token: &str) -> Uuid {
    let body = json!({ "name": "Secrétariat R11" });
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
    v["id"].as_str().unwrap().parse().unwrap()
}

// ── Test 1 : GET admin → 200, tableau vide initialement ─────────────────────

#[tokio::test]
async fn get_provider_secretariats_admin_returns_200() {
    if !db_available() {
        return;
    }
    let email = format!("r11_get_admin_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _, provider_id) = register_pro(db.clone(), &email).await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/providers/{}/secretariats",
                    provider_id
                ))
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

// ── Test 2 : GET secretary → 403 ────────────────────────────────────────────

#[tokio::test]
async fn get_provider_secretariats_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("r11_get_sec_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id, provider_id) = register_pro(db.clone(), &email).await;

    let secretary_token = make_secretary_token(account_id, cabinet_id);

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/providers/{}/secretariats",
                    provider_id
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

// ── Test 3 : PUT admin remplace ; vérifie row count dans provider_secretariat ─

#[tokio::test]
async fn put_provider_secretariats_replaces_assignments() {
    if !db_available() {
        return;
    }
    let email = format!("r11_put_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let owner_db = owner_pool().await;
    let (token, _, _, provider_id) = register_pro(db.clone(), &email).await;

    // Crée deux secrétariats.
    let sec1 = create_secretariat(db.clone(), &token).await;
    let sec2 = create_secretariat(db.clone(), &token).await;

    // Premier PUT : assigne sec1 seulement.
    let body1 = json!({ "secretariat_ids": [sec1] });
    let resp1 = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!(
                    "/v1/cabinet/providers/{}/secretariats",
                    provider_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body1.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp1.status(), StatusCode::OK);

    // Vérif : 1 ligne active dans provider_secretariat.
    let row = sqlx::query(
        "SELECT COUNT(*) AS n FROM provider_secretariat WHERE provider_id = $1 AND active = true",
    )
    .bind(provider_id)
    .fetch_one(&owner_db)
    .await
    .unwrap();
    let count: i64 = row.try_get("n").unwrap();
    assert_eq!(count, 1, "une seule assignation active après premier PUT");

    // Second PUT : remplace par sec1 + sec2.
    let body2 = json!({ "secretariat_ids": [sec1, sec2] });
    let resp2 = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!(
                    "/v1/cabinet/providers/{}/secretariats",
                    provider_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body2.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp2.status(), StatusCode::OK);
    let bytes2 = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let arr: serde_json::Value = serde_json::from_slice(&bytes2).unwrap();
    assert_eq!(
        arr.as_array().unwrap().len(),
        2,
        "réponse doit contenir 2 items"
    );

    // Vérif : 2 lignes actives dans provider_secretariat.
    let row2 = sqlx::query(
        "SELECT COUNT(*) AS n FROM provider_secretariat WHERE provider_id = $1 AND active = true",
    )
    .bind(provider_id)
    .fetch_one(&owner_db)
    .await
    .unwrap();
    let count2: i64 = row2.try_get("n").unwrap();
    assert_eq!(count2, 2, "deux assignations actives après second PUT");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_db)
        .await
        .ok();
}
