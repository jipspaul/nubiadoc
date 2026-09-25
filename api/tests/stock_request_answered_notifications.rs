//! Tests d'intégration : notification du cabinet lors de la réponse d'une
//! officine à une demande de stock (#7017) — `POST
//! /v1/pharmacy/stock-requests/:id/accept|reject|fulfill` ne créait jusqu'ici
//! aucune notification côté cabinet (seul l'aller cabinet → pharmacie était
//! notifié via `notify_pharmacy_staff`, cf. `create_stock_request`). Même
//! squelette que `quote_lifecycle_notifications.rs`.

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

const JWT_SECRET: &str = "test-jwt-secret-stock-request-answered-notifications";

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

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600
}

fn pharma_jwt(pharmacy_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "pharma", "pharmacy_id": pharmacy_id,
                "role": "pharmacist", "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    pharmacy_id: Uuid,
    practitioner_user_id: Uuid,
    secretary_user_id: Uuid,
    stock_request_id: Uuid,
}

/// Seed : cabinet + un membre `practitioner` + un membre `secretary` +
/// pharmacie listée + demande de stock au statut `status`.
async fn seed(db: &PgPool, status: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();
    let practitioner_user_id = Uuid::new_v4();
    let secretary_user_id = Uuid::new_v4();
    let stock_request_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(practitioner_user_id)
    .bind(format!(
        "stock-answered-practitioner+{practitioner_user_id}@nubia.test"
    ))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(secretary_user_id)
    .bind(format!(
        "stock-answered-secretary+{secretary_user_id}@nubia.test"
    ))
    .execute(db)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, $2)")
        .bind(cabinet_id)
        .bind(format!("Cabinet Stock Answered {cabinet_id}"))
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, $2, true)",
    )
    .bind(pharmacy_id)
    .bind(format!("Pharmacie Stock Answered {pharmacy_id}"))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) \
         VALUES ($1, $2, 'practitioner', true)",
    )
    .bind(cabinet_id)
    .bind(practitioner_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) \
         VALUES ($1, $2, 'secretary', true)",
    )
    .bind(cabinet_id)
    .bind(secretary_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO stock_request \
         (id, cabinet_id, pharmacy_id, created_by, cabinet_name, items, status) \
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(stock_request_id)
    .bind(cabinet_id)
    .bind(pharmacy_id)
    .bind(practitioner_user_id)
    .bind(format!("Cabinet Stock Answered {cabinet_id}"))
    .bind(json!([{"label": "Compresses stériles", "qty": 10}]))
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        pharmacy_id,
        practitioner_user_id,
        secretary_user_id,
        stock_request_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM stock_request WHERE id = $1")
        .bind(f.stock_request_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_membership WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();

    sqlx::query("DELETE FROM pharmacy WHERE id = $1")
        .bind(f.pharmacy_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM notification WHERE app_user_id IN ($1, $2)")
        .bind(f.practitioner_user_id)
        .bind(f.secretary_user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id IN ($1, $2)")
        .bind(f.practitioner_user_id)
        .bind(f.secretary_user_id)
        .execute(db)
        .await
        .ok();
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn respond(
    state: AppState,
    stock_request_id: Uuid,
    action: &str,
    token: String,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method("POST")
        .uri(format!(
            "/v1/pharmacy/stock-requests/{stock_request_id}/{action}"
        ))
        .header("Authorization", format!("Bearer {token}"));
    if body.is_some() {
        builder = builder.header("content-type", "application/json");
    }
    let response = app(state)
        .oneshot(
            builder
                .body(match body {
                    Some(v) => Body::from(v.to_string()),
                    None => Body::empty(),
                })
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

async fn notification_status(db: &PgPool, app_user_id: Uuid, kind: &str) -> Option<String> {
    sqlx::query_scalar(
        "SELECT data->>'status' FROM notification WHERE app_user_id = $1 AND kind = $2",
    )
    .bind(app_user_id)
    .bind(kind)
    .fetch_optional(db)
    .await
    .unwrap()
}

async fn count_notifications(db: &PgPool, app_user_id: Uuid, kind: &str) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM notification WHERE app_user_id = $1 AND kind = $2")
        .bind(app_user_id)
        .bind(kind)
        .fetch_one(db)
        .await
        .unwrap()
}

// ── Test 1 : refus d'une demande sent → praticien + secrétariat notifiés ───

#[tokio::test]
async fn rejecting_stock_request_notifies_practitioner_and_secretary() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "sent").await;

    let (status, body) = respond(
        state_with(app_pool().await),
        f.stock_request_id,
        "reject",
        pharma_jwt(f.pharmacy_id),
        Some(json!({"note": "Rupture fournisseur"})),
    )
    .await;

    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["status"], "rejected");

    assert_eq!(
        count_notifications(&db, f.practitioner_user_id, "stock_request_answered").await,
        1
    );
    assert_eq!(
        count_notifications(&db, f.secretary_user_id, "stock_request_answered").await,
        1
    );
    assert_eq!(
        notification_status(&db, f.secretary_user_id, "stock_request_answered").await,
        Some("rejected".to_string())
    );

    cleanup(&db, &f).await;
}

// ── Test 2 : acceptation d'une demande sent → cabinet notifié ───────────────

#[tokio::test]
async fn accepting_stock_request_notifies_cabinet() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "sent").await;

    let (status, body) = respond(
        state_with(app_pool().await),
        f.stock_request_id,
        "accept",
        pharma_jwt(f.pharmacy_id),
        None,
    )
    .await;

    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["status"], "accepted");

    assert_eq!(
        notification_status(&db, f.practitioner_user_id, "stock_request_answered").await,
        Some("accepted".to_string())
    );

    cleanup(&db, &f).await;
}

// ── Test 3 : une demande honorée notifie le cabinet ─────────────────────────

#[tokio::test]
async fn fulfilling_stock_request_notifies_cabinet() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "accepted").await;

    let (status, body) = respond(
        state_with(app_pool().await),
        f.stock_request_id,
        "fulfill",
        pharma_jwt(f.pharmacy_id),
        None,
    )
    .await;

    assert_eq!(status, StatusCode::OK, "body: {body}");
    assert_eq!(body["status"], "fulfilled");

    assert_eq!(
        notification_status(&db, f.secretary_user_id, "stock_request_answered").await,
        Some("fulfilled".to_string())
    );

    cleanup(&db, &f).await;
}
