//! Tests d'intégration : GET /v1/documents/:id

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

const JWT_SECRET: &str = "test-jwt-secret-doc-get-by-id";

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

/// Crée app_user + patient_account. Retourne (user_id, account_id).
async fn insert_patient(db: &PgPool, label: &str) -> (Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("doc-byid-{label}+{user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'DocById')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
    (user_id, account_id)
}

/// Crée cabinet + patient + document. Retourne (cabinet_id, patient_id, doc_id).
async fn insert_doc_fixture(db: &PgPool, account_id: Uuid) -> (Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let doc_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet DocById {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Test', 'DocById', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO document \
         (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256) \
         VALUES ($1, $2, $3, 'ordonnance', 'key/doc-byid', 'ordo.pdf', 'application/pdf', $4)",
    )
    .bind(doc_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind("b".repeat(64))
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    (cabinet_id, patient_id, doc_id)
}

async fn cleanup_fixture(db: &PgPool, cabinet_id: Uuid, patient_id: Uuid, doc_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM document WHERE id = $1")
        .bind(doc_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
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

// ── Test 1 : happy-path — propriétaire du document → 200 avec signed_url non vide ──

#[tokio::test]
async fn document_get_by_id_owner_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id) = insert_patient(&db, "owner").await;
    let (cabinet_id, patient_id, doc_id) = insert_doc_fixture(&db, account_id).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/documents/{doc_id}"))
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

    assert_eq!(v["id"], doc_id.to_string(), "id doit correspondre");
    assert_eq!(v["category"], "ordonnance");
    assert_eq!(v["filename"], "ordo.pdf");
    assert_eq!(v["mime_type"], "application/pdf");
    assert!(v["size_bytes"].is_number(), "size_bytes doit être présent");
    assert!(v["sha256"].is_string(), "sha256 doit être présent");
    assert!(v["created_at"].is_string(), "created_at doit être présent");
    assert!(
        !v["signed_url"].as_str().unwrap_or("").is_empty(),
        "signed_url doit être non vide"
    );
    assert!(
        v["signed_url_expires_at"].is_string(),
        "signed_url_expires_at doit être présent"
    );

    cleanup_fixture(&db, cabinet_id, patient_id, doc_id).await;
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : document d'un autre patient → 404 (anti-énumération) ─────────────────

#[tokio::test]
async fn document_get_by_id_other_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    // Patient A : propriétaire du document.
    let (_user_a_id, account_a_id) = insert_patient(&db, "docA").await;
    // Patient B : le requérant.
    let (user_b_id, account_b_id) = insert_patient(&db, "docB").await;

    let (cabinet_id, patient_id, doc_id) = insert_doc_fixture(&db, account_a_id).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Patient B essaie d'accéder au document de Patient A → 404.
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/documents/{doc_id}"))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_b_id, account_b_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "document d'un autre patient doit retourner 404"
    );

    cleanup_fixture(&db, cabinet_id, patient_id, doc_id).await;
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(_user_a_id)
        .bind(user_b_id)
        .execute(&db)
        .await
        .ok();
}
