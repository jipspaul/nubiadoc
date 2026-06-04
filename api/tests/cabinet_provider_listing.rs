//! Tests d'intégration : PUT /v1/cabinet/provider/listing

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

/// Enregistre un pro, renvoie `(access_token, cabinet_id)`.
async fn register_pro(db: PgPool, email: &str) -> (String, Uuid) {
    let body = json!({
        "email": email,
        "password": "password1",
        "cabinet": { "raison_sociale": "Cabinet Listing", "siret": null, "specialite": "dentaire" },
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
    let token = v["access_token"].as_str().unwrap().to_string();
    let cabinet_id: Uuid = v["cabinet_id"].as_str().unwrap().parse().unwrap();
    (token, cabinet_id)
}

// ── Test 1 : online=true avec rpps_verified=true → 200 { is_listed: true } ────

#[tokio::test]
async fn put_listing_online_rpps_verified_returns_200() {
    if !db_available() {
        return;
    }
    let email = format!("listing_verified_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, cabinet_id) = register_pro(db.clone(), &email).await;

    // Simule rpps_verified=true. La table provider a FORCE RLS, donc il faut
    // passer par le rôle app avec le GUC positionné (SET LOCAL).
    {
        let owner = owner_pool().await;
        let mut tx = owner.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query("UPDATE provider SET rpps_verified = true WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
    }

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/cabinet/provider/listing")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({"online": true}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["is_listed"], true);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 2 : online=true avec rpps_verified=false → 409 provider_not_verified ─

#[tokio::test]
async fn put_listing_online_rpps_not_verified_returns_409() {
    if !db_available() {
        return;
    }
    let email = format!("listing_unverified_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _) = register_pro(db.clone(), &email).await;

    // rpps_verified=false par défaut à la création — pas de modification nécessaire.

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/cabinet/provider/listing")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({"online": true}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CONFLICT);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "provider_not_verified");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}
