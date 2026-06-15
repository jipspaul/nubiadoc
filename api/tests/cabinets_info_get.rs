//! Tests d'intégration : GET /v1/cabinets/:id/info (US-P28)
//! Route publique — aucun JWT obligatoire.

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

const JWT_SECRET: &str = "test-secret-cabinfo";

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

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    }
}

/// Insère un cabinet minimal avec settings JSON.
/// Retourne `cabinet_id`.
async fn insert_cabinet(db: &PgPool, suffix: &str) -> Uuid {
    let cabinet_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite, settings) \
         VALUES ($1, $2, 'dentaire', $3::jsonb)",
    )
    .bind(cabinet_id)
    .bind(format!("Cabinet Info {}", suffix))
    .bind(json!({
        "address": { "street": "12 rue de la Paix", "city": "Paris" },
        "contact": { "phone": "0102030405" },
        "door_code": "A1B2",
        "parking": "parking souterrain",
        "pmr_access": true
    }))
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    cabinet_id
}

async fn cleanup_cabinet(db: &PgPool, cabinet_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

/// JWT patient valide (kind = "patient").
fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({ "sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// JWT pro (kind = "pro") — doit être silencieusement ignoré sur cette route publique.
fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({ "sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "exp": exp }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── Test 1 : happy path — cabinet existant, sans JWT → 200 + body conforme ──────

#[tokio::test]
async fn get_cabinet_info_happy_path_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let cabinet_id = insert_cabinet(&db, &suffix).await;

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinets/{}/info", cabinet_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK, "cabinet existant → 200");

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(
        v["id"].as_str().unwrap().parse::<Uuid>().unwrap(),
        cabinet_id,
        "id doit correspondre"
    );
    assert_eq!(
        v["name"],
        format!("Cabinet Info {}", suffix),
        "name doit correspondre à raison_sociale"
    );
    assert!(v["address"].is_object(), "address doit être un objet");
    assert!(v["contact"].is_object(), "contact doit être un objet");
    // is_current_patient absent (pas de JWT)
    assert!(
        v["is_current_patient"].is_null(),
        "is_current_patient doit être null sans JWT patient"
    );

    cleanup_cabinet(&db, cabinet_id).await;
}

// ── Test 2 : cabinet inexistant → 404 ────────────────────────────────────────

#[tokio::test]
async fn get_cabinet_info_unknown_id_returns_404() {
    if !db_available() {
        return;
    }
    let random_id = Uuid::new_v4();

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinets/{}/info", random_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "ID inexistant → 404"
    );
}

// ── Test 3 : UUID mal formé → 400 ou 422 ─────────────────────────────────────

#[tokio::test]
async fn get_cabinet_info_invalid_uuid_returns_error() {
    if !db_available() {
        return;
    }
    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinets/not-a-uuid/info")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    let status = response.status().as_u16();
    assert!(
        status == 400 || status == 422,
        "UUID invalide → 400 ou 422, got {}",
        status
    );
}

// ── Test 4 (edge) : token patient valide + patient inscrit → is_current_patient = true ──

#[tokio::test]
async fn get_cabinet_info_with_patient_jwt_returns_is_current_patient_true() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let cabinet_id = insert_cabinet(&db, &suffix).await;

    // Crée un patient_account + app_user patient
    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("cabinfo-patient-{}@nubia.test", suffix))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Cabinet', 'Info')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
    .execute(&db)
    .await
    .unwrap();

    // Inscrit le patient dans ce cabinet
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Cabinet', 'Info', $3)",
        )
        .bind(Uuid::new_v4())
        .bind(cabinet_id)
        .bind(patient_account_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let jwt = make_patient_jwt(patient_user_id, patient_account_id);

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinets/{}/info", cabinet_id))
                .header("Authorization", format!("Bearer {}", jwt))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK, "doit retourner 200");

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(
        v["is_current_patient"].as_bool(),
        Some(true),
        "patient inscrit → is_current_patient = true"
    );

    cleanup_cabinet(&db, cabinet_id).await;
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(patient_account_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(patient_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 5 (edge) : token pro (kind != "patient") → is_current_patient null ──

#[tokio::test]
async fn get_cabinet_info_with_pro_jwt_ignores_token_is_current_patient_null() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let cabinet_id = insert_cabinet(&db, &suffix).await;

    let pro_user_id = Uuid::new_v4();
    let pro_jwt = make_pro_jwt(pro_user_id, cabinet_id);

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinets/{}/info", cabinet_id))
                .header("Authorization", format!("Bearer {}", pro_jwt))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::OK,
        "route publique → 200 même avec token pro"
    );

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert!(
        v["is_current_patient"].is_null(),
        "token pro → is_current_patient doit être null (kind != patient ignoré)"
    );

    cleanup_cabinet(&db, cabinet_id).await;
}
