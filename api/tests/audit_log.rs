//! Tests d'intégration : GET /v1/cabinet/audit-log (#4155)

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

/// Enregistre un pro (rôle `admin` par défaut au register), renvoie `(access_token, cabinet_id)`.
async fn register_pro(db: PgPool, email: &str) -> (String, Uuid) {
    let body = json!({
        "email": email,
        "password": "password1",
        "cabinet": { "raison_sociale": "Cabinet Audit", "siret": null, "specialite": "dentaire" },
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

/// Insère une ligne `audit_log` pour `cabinet_id` (RLS `tenant_isolation` — GUC requis).
async fn insert_audit_row(cabinet_id: Uuid, action: &str, entity: &str) {
    let app_db = app_pool().await;
    let mut tx = app_db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO audit_log (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, NULL, 'admin', $2, $3, NULL, '{}')",
    )
    .bind(cabinet_id)
    .bind(action)
    .bind(entity)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
}

// ── Test 1 : rôle admin → 200, retrouve les entrées du cabinet ────────────────

#[tokio::test]
async fn get_audit_log_admin_returns_entries() {
    if !db_available() {
        return;
    }
    let email = format!("audit_admin_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, cabinet_id) = register_pro(db.clone(), &email).await;

    insert_audit_row(cabinet_id, "login", "session").await;
    insert_audit_row(cabinet_id, "read_record", "patient").await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/audit-log")
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
    let data = v["data"].as_array().unwrap();
    assert_eq!(
        data.len(),
        2,
        "les deux entrées insérées pour ce cabinet doivent revenir"
    );
    // Le register lui-même n'écrit pas dans audit_log ; seules les 2 lignes
    // insérées manuellement sont attendues, triées occurred_at DESC.
    assert_eq!(data[0]["action"], "read_record");
    assert_eq!(data[1]["action"], "login");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 2 : filtre `entity` ───────────────────────────────────────────────────

#[tokio::test]
async fn get_audit_log_filters_by_entity() {
    if !db_available() {
        return;
    }
    let email = format!("audit_entity_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, cabinet_id) = register_pro(db.clone(), &email).await;

    insert_audit_row(cabinet_id, "login", "session").await;
    insert_audit_row(cabinet_id, "read_record", "patient").await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/audit-log?entity=patient")
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
    let data = v["data"].as_array().unwrap();
    assert_eq!(data.len(), 1);
    assert_eq!(data[0]["entity"], "patient");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 3 : rôle secretary → 403 (réservé admin/manager) ─────────────────────

#[tokio::test]
async fn get_audit_log_secretary_role_returns_403() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;

    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let secretary_token = encode(
        &Header::default(),
        &json!({
            "sub": Uuid::new_v4(),
            "kind": "pro",
            "cabinet_id": Uuid::new_v4(),
            "role": "secretary",
            "exp": exp
        }),
        &EncodingKey::from_secret("test-secret".as_bytes()),
    )
    .unwrap();

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/audit-log")
                .header("Authorization", format!("Bearer {}", secretary_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        resp.status(),
        StatusCode::FORBIDDEN,
        "un rôle secretary/practitioner ne doit pas accéder au journal d'accès (#4155)"
    );
}

// ── Test 4 : token patient VALIDE → 403, pas 401 (#3806) ──────────────────────

#[tokio::test]
async fn get_audit_log_patient_token_returns_403_not_401() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;

    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let patient_token = encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp}),
        &EncodingKey::from_secret("test-secret".as_bytes()),
    )
    .unwrap();

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/audit-log")
                .header("Authorization", format!("Bearer {}", patient_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);
}
