//! Tests d'intégration : POST /v1/webhooks/gocardless
//!
//! 3 cas :
//!   1. Happy path : payments.confirmed → payment.status = 'paid' + paid_at != NULL.
//!   2. HMAC invalide → 401.
//!   3. Événement ignoré (non payments.confirmed) → 200, payment non touché.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use hmac::{Hmac, Mac};
use serde_json::json;
use sha2::Sha256;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{
    app_with_dispatcher, AppState, GocardlessWebhookSecret, StubJobDispatcher, StubMailer,
    StubStorageSigner,
};

type HmacSha256 = Hmac<Sha256>;

const GC_SECRET: &str = "gc_integ_test_secret";

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

fn make_sig(secret: &str, body: &[u8]) -> String {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
    mac.update(body);
    BASE64.encode(mac.finalize().into_bytes())
}

fn build_app(db: PgPool) -> axum::Router {
    let state = AppState {
        db,
        jwt_secret: "unused".to_string(),
        mailer: Arc::new(StubMailer),
    };
    app_with_dispatcher(
        state,
        Arc::new(StubJobDispatcher),
        Arc::new(StubStorageSigner),
    )
    .layer(axum::Extension(GocardlessWebhookSecret(
        GC_SECRET.to_string(),
    )))
}

// ── Test 1 : happy path — payments.confirmed → status='paid' + paid_at positionné ──

#[tokio::test]
async fn gocardless_webhook_payments_confirmed_marks_paid() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let payment_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let gc_payment_id = format!("PM{}", Uuid::new_v4().simple());

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(prac_user_id)
        .bind(format!("gc-prac+{}@nubia.test", prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet GC Test {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
            .bind(prac_id)
            .bind(cabinet_id)
            .bind(prac_user_id)
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
             VALUES ($1, $2, 'Pat', 'GC')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO payment \
             (id, cabinet_id, patient_id, amount, currency, kind, provider, provider_ref, status) \
             VALUES ($1, $2, $3, 50.00, 'EUR', 'full', 'gocardless', $4, 'pending')",
        )
        .bind(payment_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(&gc_payment_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let body = serde_json::to_vec(&json!({
        "event": {
            "action": "payments.confirmed",
            "links": { "payment": gc_payment_id }
        }
    }))
    .unwrap();
    let sig = make_sig(GC_SECRET, &body);

    let response = build_app(app_pool().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/gocardless")
                .header("content-type", "application/json")
                .header("webhook-signature", &sig)
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    // Vérifie status = 'paid' et paid_at != NULL.
    let row = sqlx::query("SELECT status, paid_at FROM payment WHERE id = $1")
        .bind(payment_id)
        .fetch_one(&db)
        .await
        .unwrap();

    let status: String = row.try_get("status").unwrap();
    let paid_at: Option<chrono::DateTime<chrono::Utc>> = row.try_get("paid_at").unwrap();

    assert_eq!(status, "paid");
    assert!(
        paid_at.is_some(),
        "paid_at doit être non nul après payments.confirmed"
    );

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM payment WHERE id = $1")
            .bind(payment_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM patient WHERE id = $1")
            .bind(patient_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM practitioner WHERE id = $1")
            .bind(prac_id)
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : HMAC invalide → 401 ──────────────────────────────────────────────

#[tokio::test]
async fn gocardless_webhook_invalid_hmac_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();

    let body = serde_json::to_vec(&json!({
        "event": {
            "action": "payments.confirmed",
            "links": { "payment": "PM_bad" }
        }
    }))
    .unwrap();

    let response = build_app(db)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/gocardless")
                .header("content-type", "application/json")
                .header("webhook-signature", "invalidsignaturebase64==")
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 3 : événement ignoré → 200, payment non touché ───────────────────────

#[tokio::test]
async fn gocardless_webhook_ignored_event_returns_200_no_update() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let payment_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let gc_payment_id = format!("PM{}", Uuid::new_v4().simple());

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(prac_user_id)
        .bind(format!("gc-ignored+{}@nubia.test", prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet GC Ignored {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
            .bind(prac_id)
            .bind(cabinet_id)
            .bind(prac_user_id)
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
             VALUES ($1, $2, 'Pat2', 'GCZ')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO payment \
             (id, cabinet_id, patient_id, amount, currency, kind, provider, provider_ref, status) \
             VALUES ($1, $2, $3, 30.00, 'EUR', 'full', 'gocardless', $4, 'pending')",
        )
        .bind(payment_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(&gc_payment_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let body = serde_json::to_vec(&json!({
        "event": {
            "action": "payments.created",
            "links": { "payment": gc_payment_id }
        }
    }))
    .unwrap();
    let sig = make_sig(GC_SECRET, &body);

    let response = build_app(app_pool().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/gocardless")
                .header("content-type", "application/json")
                .header("webhook-signature", &sig)
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    // Vérifie que le payment n'a PAS été modifié.
    let row = sqlx::query("SELECT status, paid_at FROM payment WHERE id = $1")
        .bind(payment_id)
        .fetch_one(&db)
        .await
        .unwrap();

    let status: String = row.try_get("status").unwrap();
    let paid_at: Option<chrono::DateTime<chrono::Utc>> = row.try_get("paid_at").unwrap();

    assert_eq!(status, "pending", "status ne doit pas avoir changé");
    assert!(
        paid_at.is_none(),
        "paid_at doit rester null pour un événement ignoré"
    );

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM payment WHERE id = $1")
            .bind(payment_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM patient WHERE id = $1")
            .bind(patient_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM practitioner WHERE id = $1")
            .bind(prac_id)
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}
