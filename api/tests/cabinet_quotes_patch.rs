//! Tests d'intégration : PATCH /v1/cabinet/quotes/:id (#4065)
//!
//! Édition d'un devis non signé : remplacement des lignes, incrément de
//! `version`, verrouillage post-signature (409 `quote_locked`).

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-cabinet-quotes-patch";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": user_id,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": role,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Seed : cabinet + patient + un devis (statut `status`, version 1) + une
/// ligne existante. Retourne `quote_id`.
async fn seed_quote(db: &PgPool, cabinet_id: Uuid, patient_id: Uuid, status: &str) -> Uuid {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet CQP {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Patient')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    let quote_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, $4, 50.00, 'EUR')",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, unit_amount) \
         VALUES ($1, $2, 'Ligne initiale', 50.00)",
    )
    .bind(cabinet_id)
    .bind(quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    quote_id
}

async fn quote_row(db: &PgPool, cabinet_id: Uuid, quote_id: Uuid) -> (String, i32, String) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row =
        sqlx::query("SELECT status, version, total_amount::text AS total FROM quote WHERE id = $1")
            .bind(quote_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    let status: String = row.try_get("status").unwrap();
    let version: i32 = row.try_get("version").unwrap();
    let total: String = row.try_get("total").unwrap();
    tx.commit().await.unwrap();
    (status, version, total)
}

async fn item_labels(db: &PgPool, cabinet_id: Uuid, quote_id: Uuid) -> Vec<String> {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let rows = sqlx::query("SELECT label FROM quote_item WHERE quote_id = $1 ORDER BY label")
        .bind(quote_id)
        .fetch_all(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    rows.iter()
        .map(|r| r.try_get::<String, _>("label").unwrap())
        .collect()
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_item WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
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

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn patch(
    state: AppState,
    quote_id: Uuid,
    token: String,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/quotes/{quote_id}"))
                .header("Authorization", format!("Bearer {token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

// ── Test 1 : happy path — brouillon édité, lignes remplacées, version+1 ──────

#[tokio::test]
async fn patch_draft_quote_replaces_items_and_bumps_version() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let quote_id = seed_quote(&db, cabinet_id, patient_id, "draft").await;

    let body = json!({
        "items": [
            { "label": "Détartrage", "amount_cents": 8000 },
            { "label": "Consultation", "amount_cents": 5000 }
        ]
    });

    let (status, resp) = patch(
        state_with(app_pool().await),
        quote_id,
        make_pro_jwt(user_id, cabinet_id, "practitioner"),
        body,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(resp["version"], 2);
    assert_eq!(resp["total_amount_cents"], 13000);

    let (db_status, version, total) = quote_row(&db, cabinet_id, quote_id).await;
    assert_eq!(db_status, "draft");
    assert_eq!(version, 2);
    assert_eq!(total, "130.00");

    let labels = item_labels(&db, cabinet_id, quote_id).await;
    assert_eq!(
        labels,
        vec!["Consultation".to_string(), "Détartrage".to_string()]
    );

    cleanup(&db, cabinet_id).await;
}

// ── Test 2 : devis signé → 409 quote_locked, rien modifié ────────────────────

#[tokio::test]
async fn patch_signed_quote_returns_409_and_leaves_items_untouched() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let quote_id = seed_quote(&db, cabinet_id, patient_id, "signed").await;

    let body = json!({
        "items": [{ "label": "Tentative de modif", "amount_cents": 1000 }]
    });

    let (status, resp) = patch(
        state_with(app_pool().await),
        quote_id,
        make_pro_jwt(user_id, cabinet_id, "practitioner"),
        body,
    )
    .await;

    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(resp["code"], "quote_locked");

    // Rollback transactionnel : la ligne initiale doit être intacte.
    let labels = item_labels(&db, cabinet_id, quote_id).await;
    assert_eq!(labels, vec!["Ligne initiale".to_string()]);
    let (_, version, _) = quote_row(&db, cabinet_id, quote_id).await;
    assert_eq!(version, 1);

    cleanup(&db, cabinet_id).await;
}

// ── Test 3 : items vide → 422 ─────────────────────────────────────────────────

#[tokio::test]
async fn patch_empty_items_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let quote_id = seed_quote(&db, cabinet_id, patient_id, "draft").await;

    let (status, _) = patch(
        state_with(app_pool().await),
        quote_id,
        make_pro_jwt(user_id, cabinet_id, "practitioner"),
        json!({ "items": [] }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, cabinet_id).await;
}

// ── Test 4 : devis d'un autre cabinet → 404 (isolation RLS) ──────────────────

#[tokio::test]
async fn patch_quote_of_other_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = Uuid::new_v4();
    let other_cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let quote_id = seed_quote(&db, cabinet_id, patient_id, "draft").await;

    let (status, _) = patch(
        state_with(app_pool().await),
        quote_id,
        make_pro_jwt(user_id, other_cabinet_id, "practitioner"),
        json!({ "items": [{ "label": "X", "amount_cents": 1000 }] }),
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
    let labels = item_labels(&db, cabinet_id, quote_id).await;
    assert_eq!(labels, vec!["Ligne initiale".to_string()]);

    cleanup(&db, cabinet_id).await;
}

// ── Test 5 : token secretary → 403 (practitioner/admin uniquement) ──────────

#[tokio::test]
async fn patch_with_secretary_token_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let quote_id = seed_quote(&db, cabinet_id, patient_id, "draft").await;

    let (status, _) = patch(
        state_with(app_pool().await),
        quote_id,
        make_pro_jwt(user_id, cabinet_id, "secretary"),
        json!({ "items": [{ "label": "X", "amount_cents": 1000 }] }),
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);

    cleanup(&db, cabinet_id).await;
}
