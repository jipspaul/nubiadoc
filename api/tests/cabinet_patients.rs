//! Tests d'intégration : GET /v1/cabinet/patients + POST /v1/cabinet/patients (§14)

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

/// Enregistre un pro, renvoie `(access_token, user_id, cabinet_id)`.
async fn register_pro(db: PgPool, email: &str) -> (String, Uuid, Uuid) {
    let body = json!({
        "email": email,
        "password": "password1",
        "cabinet": { "raison_sociale": "Cabinet Patients Test", "siret": null, "specialite": "dentaire" },
        "practitioner": { "first_name": "Paul", "last_name": "Durand", "rpps": null, "adeli": null }
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
    let user_id: Uuid = v["account_id"].as_str().unwrap().parse().unwrap();
    let cabinet_id: Uuid = v["cabinet_id"].as_str().unwrap().parse().unwrap();
    (token, user_id, cabinet_id)
}

/// Crée un `patient_account` en DB (rôle owner, hors RLS cabinet), renvoie son `id`.
async fn create_patient_account(owner: &PgPool, email: &str) -> Uuid {
    let id = Uuid::new_v4();
    // Crée d'abord l'app_user associé.
    let user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'x', 'patient')",
    )
    .bind(user_id)
    .bind(email)
    .execute(owner)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Marie', 'Curie')",
    )
    .bind(id)
    .bind(user_id)
    .execute(owner)
    .await
    .unwrap();
    id
}

/// Crée un JWT signé `kind=patient` (pour tester le 403 patient).
fn make_patient_token(sub: Uuid, account_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        account_id: Uuid,
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
            kind: "patient".into(),
            account_id,
            exp,
        },
        &EncodingKey::from_secret(b"test-secret"),
    )
    .unwrap()
}

// ── Test 1 : GET /v1/cabinet/patients → 200 avec token pro valide ─────────────

#[tokio::test]
async fn list_cabinet_patients_returns_200() {
    if !db_available() {
        return;
    }
    let email = format!("list_patients_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &email).await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/patients")
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
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["data"].is_array(), "data doit être un tableau");
    assert!(v["page"].is_object(), "page doit être un objet");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 2 : GET /v1/cabinet/patients sans token → 401 ───────────────────────

#[tokio::test]
async fn list_cabinet_patients_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/patients")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 3 : GET /v1/cabinet/patients avec token patient → 403 ───────────────

#[tokio::test]
async fn list_cabinet_patients_patient_token_returns_403() {
    if !db_available() {
        return;
    }
    let account_id = Uuid::new_v4();
    let token = make_patient_token(account_id, account_id);
    let db = app_pool().await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/patients")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}

// ── Test 4 : POST /v1/cabinet/patients → 201 + patient_id retourné ──────────

#[tokio::test]
async fn create_cabinet_patient_returns_201() {
    if !db_available() {
        return;
    }
    let pro_email = format!("create_patient_pro_{}@test.local", Uuid::new_v4());
    let patient_email = format!("create_patient_acct_{}@test.local", Uuid::new_v4());
    let owner = owner_pool().await;
    let db = app_pool().await;

    let (token, _, _) = register_pro(db.clone(), &pro_email).await;
    let patient_account_id = create_patient_account(&owner, &patient_email).await;

    let body = json!({ "patient_account_id": patient_account_id, "note": "Test" });
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/patients")
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
    assert!(
        v["patient_id"]
            .as_str()
            .and_then(|s| s.parse::<Uuid>().ok())
            .is_some(),
        "patient_id doit être un UUID valide"
    );

    sqlx::query("DELETE FROM app_user WHERE email = $1 OR email = $2")
        .bind(&pro_email)
        .bind(&patient_email)
        .execute(&owner)
        .await
        .ok();
}

// ── Test 5 : POST /v1/cabinet/patients sans token → 401 ──────────────────────

#[tokio::test]
async fn create_cabinet_patient_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let body = json!({ "patient_account_id": Uuid::new_v4() });
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/patients")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 6 : POST /v1/cabinet/patients avec token patient → 403 ──────────────

#[tokio::test]
async fn create_cabinet_patient_patient_token_returns_403() {
    if !db_available() {
        return;
    }
    let account_id = Uuid::new_v4();
    let token = make_patient_token(account_id, account_id);
    let db = app_pool().await;
    let body = json!({ "patient_account_id": Uuid::new_v4() });

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/patients")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}
