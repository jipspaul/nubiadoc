//! Tests d'intégration : POST /v1/webhooks/stripe
//!
//! 7 cas :
//!   1. Header Stripe-Signature absent → 401.
//!   2. HMAC invalide (mauvaise signature) → 401.
//!   3. Signature expirée (ts > 300 s) → 401.
//!   4. Happy path : payment_intent.succeeded → payment.status = 'paid'.
//!   5. Replay attack : même event_id deux fois → 2ᵉ appel 200, idempotent
//!      (une seule entrée dans webhook_event_log).
//!   6. Événement ignoré (customer.subscription.created) → 200, payment non touché.
//!   7. payment_intent.payment_failed → payment.status = 'failed'.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use hmac::{Hmac, Mac};
use serde_json::json;
use sha2::Sha256;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{
    app_with_dispatcher, AppState, StripeWebhookSecret, StubJobDispatcher, StubMailer,
    StubStorageSigner,
};

type HmacSha256 = Hmac<Sha256>;

const STRIPE_SECRET: &str = "whsec_stripe_integ_test_secret";

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

/// Génère un header `Stripe-Signature` valide.
/// Format : `t=<ts>,v1=<hex(HMAC-SHA256(secret, "<ts>.<body>"))>`
fn make_stripe_sig(secret: &str, body: &[u8], ts: i64) -> String {
    let signed_payload = [ts.to_string().as_bytes(), b".", body].concat();
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
    mac.update(&signed_payload);
    let sig = hex::encode(mac.finalize().into_bytes());
    format!("t={ts},v1={sig}")
}

fn now_ts() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64
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
    .layer(axum::Extension(StripeWebhookSecret(
        STRIPE_SECRET.to_string(),
    )))
}

// ── Test 1 : header Stripe-Signature absent → 401 ────────────────────────────

#[tokio::test]
async fn stripe_webhook_absent_signature_header_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();

    let body = serde_json::to_vec(&json!({
        "id": "evt_absent",
        "type": "payment_intent.succeeded",
        "data": { "object": { "id": "pi_absent" } }
    }))
    .unwrap();

    let response = build_app(db)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/stripe")
                .header("content-type", "application/json")
                // Pas de header Stripe-Signature
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 2 : HMAC invalide → 401 ─────────────────────────────────────────────

#[tokio::test]
async fn stripe_webhook_invalid_hmac_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();

    let body = serde_json::to_vec(&json!({
        "id": "evt_invalid",
        "type": "payment_intent.succeeded",
        "data": { "object": { "id": "pi_invalid" } }
    }))
    .unwrap();

    let ts = now_ts();
    // Signature hexadécimale incorrecte (bon format t=..,v1=.. mais mauvais HMAC).
    let bad_sig =
        format!("t={ts},v1=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef");

    let response = build_app(db)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/stripe")
                .header("content-type", "application/json")
                .header("stripe-signature", bad_sig)
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 3 : signature expirée (ts > 300 s) → 401 ────────────────────────────

#[tokio::test]
async fn stripe_webhook_expired_signature_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();

    let body = serde_json::to_vec(&json!({
        "id": "evt_expired",
        "type": "payment_intent.succeeded",
        "data": { "object": { "id": "pi_expired" } }
    }))
    .unwrap();

    // Timestamp vieux de 600 s (dépasse la tolérance Stripe de 300 s).
    let stale_ts = now_ts() - 600;
    let sig = make_stripe_sig(STRIPE_SECRET, &body, stale_ts);

    let response = build_app(db)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/stripe")
                .header("content-type", "application/json")
                .header("stripe-signature", sig)
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 4 : happy path — payment_intent.succeeded → status='paid' ───────────

#[tokio::test]
async fn stripe_webhook_payment_intent_succeeded_marks_paid() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let payment_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let pi_id = format!("pi_{}", Uuid::new_v4().simple());
    let event_id = format!("evt_{}", Uuid::new_v4().simple());

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
        .bind(format!("stripe-prac+{}@nubia.test", prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet Stripe Test {}", cabinet_id))
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
             VALUES ($1, $2, 'Pat', 'S')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO payment \
             (id, cabinet_id, patient_id, amount, currency, kind, provider, provider_ref, status) \
             VALUES ($1, $2, $3, 75.00, 'EUR', 'full', 'stripe', $4, 'pending')",
        )
        .bind(payment_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(&pi_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let body = serde_json::to_vec(&json!({
        "id": event_id,
        "type": "payment_intent.succeeded",
        "data": { "object": { "id": pi_id } }
    }))
    .unwrap();
    let sig = make_stripe_sig(STRIPE_SECRET, &body, now_ts());

    let response = build_app(app_pool().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/stripe")
                .header("content-type", "application/json")
                .header("stripe-signature", &sig)
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let row = sqlx::query("SELECT status FROM payment WHERE id = $1")
        .bind(payment_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let status: String = row.try_get("status").unwrap();
    assert_eq!(status, "paid");

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
    sqlx::query("DELETE FROM webhook_event_log WHERE provider = 'stripe' AND event_id = $1")
        .bind(&event_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 5 : replay attack — même event_id deux fois → 200 idempotent ─────────

#[tokio::test]
async fn stripe_webhook_replay_attack_idempotent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let payment_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let pi_id = format!("pi_{}", Uuid::new_v4().simple());
    let event_id = format!("evt_{}", Uuid::new_v4().simple());

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
        .bind(format!("stripe-replay+{}@nubia.test", prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet Stripe Replay {}", cabinet_id))
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
             VALUES ($1, $2, 'Pat', 'Replay')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO payment \
             (id, cabinet_id, patient_id, amount, currency, kind, provider, provider_ref, status) \
             VALUES ($1, $2, $3, 60.00, 'EUR', 'full', 'stripe', $4, 'pending')",
        )
        .bind(payment_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(&pi_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let body = serde_json::to_vec(&json!({
        "id": event_id,
        "type": "payment_intent.succeeded",
        "data": { "object": { "id": pi_id } }
    }))
    .unwrap();

    // Premier appel : traite l'événement, insère dans webhook_event_log.
    let sig1 = make_stripe_sig(STRIPE_SECRET, &body, now_ts());
    let resp1 = build_app(app_pool().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/stripe")
                .header("content-type", "application/json")
                .header("stripe-signature", &sig1)
                .body(Body::from(body.clone()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp1.status(), StatusCode::OK);

    // Deuxième appel : même event_id → ON CONFLICT DO NOTHING, skip idempotent.
    let sig2 = make_stripe_sig(STRIPE_SECRET, &body, now_ts());
    let resp2 = build_app(app_pool().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/stripe")
                .header("content-type", "application/json")
                .header("stripe-signature", &sig2)
                .body(Body::from(body.clone()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp2.status(), StatusCode::OK);

    // Le payment est 'paid' (mis à jour une seule fois, pas annulé par le 2ᵉ appel).
    let row = sqlx::query("SELECT status FROM payment WHERE id = $1")
        .bind(payment_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let status: String = row.try_get("status").unwrap();
    assert_eq!(
        status, "paid",
        "payment doit être 'paid' après les deux appels"
    );

    // Une seule entrée dans webhook_event_log (idempotence garantie par UNIQUE).
    let count_row = sqlx::query(
        "SELECT COUNT(*) as cnt FROM webhook_event_log \
         WHERE provider = 'stripe' AND event_id = $1",
    )
    .bind(&event_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let count: i64 = count_row.try_get("cnt").unwrap();
    assert_eq!(
        count, 1,
        "une seule entrée webhook_event_log attendue pour un event_id rejoué"
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
    sqlx::query("DELETE FROM webhook_event_log WHERE provider = 'stripe' AND event_id = $1")
        .bind(&event_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 7 : payment_intent.payment_failed → payment.status = 'failed' ───────

#[tokio::test]
async fn stripe_webhook_payment_intent_failed_marks_failed() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let payment_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let pi_id = format!("pi_{}", Uuid::new_v4().simple());
    let event_id = format!("evt_{}", Uuid::new_v4().simple());

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
        .bind(format!("stripe-failed+{}@nubia.test", prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet Stripe Failed {}", cabinet_id))
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
             VALUES ($1, $2, 'Pat', 'F')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO payment \
             (id, cabinet_id, patient_id, amount, currency, kind, provider, provider_ref, status) \
             VALUES ($1, $2, $3, 55.00, 'EUR', 'full', 'stripe', $4, 'pending')",
        )
        .bind(payment_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(&pi_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let body = serde_json::to_vec(&json!({
        "id": event_id,
        "type": "payment_intent.payment_failed",
        "data": { "object": { "id": pi_id } }
    }))
    .unwrap();
    let sig = make_stripe_sig(STRIPE_SECRET, &body, now_ts());

    let response = build_app(app_pool().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/stripe")
                .header("content-type", "application/json")
                .header("stripe-signature", &sig)
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let row = sqlx::query("SELECT status FROM payment WHERE id = $1")
        .bind(payment_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let status: String = row.try_get("status").unwrap();
    assert_eq!(status, "failed");

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
    sqlx::query("DELETE FROM webhook_event_log WHERE provider = 'stripe' AND event_id = $1")
        .bind(&event_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 6 : événement ignoré → 200, payment non touché ──────────────────────

#[tokio::test]
async fn stripe_webhook_ignored_event_returns_200_no_update() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let payment_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let pi_id = format!("pi_{}", Uuid::new_v4().simple());
    let event_id = format!("evt_{}", Uuid::new_v4().simple());

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
        .bind(format!("stripe-ignored+{}@nubia.test", prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet Stripe Ignored {}", cabinet_id))
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
             VALUES ($1, $2, 'Pat', 'SI')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO payment \
             (id, cabinet_id, patient_id, amount, currency, kind, provider, provider_ref, status) \
             VALUES ($1, $2, $3, 45.00, 'EUR', 'full', 'stripe', $4, 'pending')",
        )
        .bind(payment_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(&pi_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let body = serde_json::to_vec(&json!({
        "id": event_id,
        "type": "customer.subscription.created",
        "data": { "object": { "id": pi_id } }
    }))
    .unwrap();
    let sig = make_stripe_sig(STRIPE_SECRET, &body, now_ts());

    let response = build_app(app_pool().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/stripe")
                .header("content-type", "application/json")
                .header("stripe-signature", &sig)
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    // Vérifie que le payment n'a PAS été modifié.
    let row = sqlx::query("SELECT status FROM payment WHERE id = $1")
        .bind(payment_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let status: String = row.try_get("status").unwrap();
    assert_eq!(
        status, "pending",
        "payment ne doit pas changer pour un événement ignoré"
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
    sqlx::query("DELETE FROM webhook_event_log WHERE provider = 'stripe' AND event_id = $1")
        .bind(&event_id)
        .execute(&db)
        .await
        .ok();
}
