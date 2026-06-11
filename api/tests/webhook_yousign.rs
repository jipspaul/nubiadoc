//! Tests d'intégration : POST /v1/webhooks/yousign
//!
//! 3 cas :
//!   1. Happy path : signature.completed → quote.signed_at != NULL, status = 'signed'.
//!   2. HMAC invalide → 401.
//!   3. Événement ignoré (non signature.completed) → 200, quote non touchée.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{
    app_with_dispatcher, AppState, StubJobDispatcher, StubMailer, StubStorageSigner,
    YousignWebhookSecret,
};

const YOUSIGN_SECRET: &str = "yousign_integ_test_secret";

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
    use hmac::{Hmac, Mac};
    use sha2::Sha256;
    type HmacSha256 = Hmac<Sha256>;
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
    mac.update(body);
    hex::encode(mac.finalize().into_bytes())
}

fn build_app(db: PgPool) -> axum::Router {
    let state = AppState {
        db,
        jwt_secret: "unused".to_string(),
        mailer: Arc::new(StubMailer),
    };
    // Injecte le secret Yousign via une variante with_dispatcher pour contrôler l'Extension.
    // On reconstruit le router en surchargeant le layer YousignWebhookSecret.
    app_with_dispatcher(
        state,
        Arc::new(StubJobDispatcher),
        Arc::new(StubStorageSigner),
    )
    .layer(axum::Extension(YousignWebhookSecret(
        YOUSIGN_SECRET.to_string(),
    )))
}

// ── Test 1 : happy path — signature.completed → quote signé ───────────────────

#[tokio::test]
async fn yousign_webhook_signature_completed_signs_quote() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

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
        .bind(format!("yousign-prac+{}@nubia.test", prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet Yousign Test {}", cabinet_id))
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
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES ($1, $2, 'Pat', 'Y')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
             VALUES ($1, $2, $3, 'sent', 100.00, 'EUR')",
        )
        .bind(quote_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let body = serde_json::to_vec(&json!({
        "event_type": "signature.completed",
        "data": { "quote_id": quote_id.to_string() }
    }))
    .unwrap();
    let sig = make_sig(YOUSIGN_SECRET, &body);

    let response = build_app(app_pool().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/yousign")
                .header("content-type", "application/json")
                .header("x-yousign-signature", &sig)
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    // Vérifie que signed_at est positionné et status = 'signed'.
    let row = sqlx::query("SELECT status, signed_at FROM quote WHERE id = $1")
        .bind(quote_id)
        .fetch_one(&db)
        .await
        .unwrap();

    let status: String = row.try_get("status").unwrap();
    let signed_at: Option<chrono::DateTime<chrono::Utc>> = row.try_get("signed_at").unwrap();

    assert_eq!(status, "signed");
    assert!(signed_at.is_some(), "signed_at doit être non nul");

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM quote WHERE id = $1")
            .bind(quote_id)
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
async fn yousign_webhook_invalid_hmac_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();

    let body = serde_json::to_vec(&json!({
        "event_type": "signature.completed",
        "data": { "quote_id": Uuid::new_v4().to_string() }
    }))
    .unwrap();

    let response = build_app(db)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/yousign")
                .header("content-type", "application/json")
                .header("x-yousign-signature", "invalidsignaturehex")
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 3 : événement ignoré → 200, quote non touchée ───────────────────────

#[tokio::test]
async fn yousign_webhook_ignored_event_returns_200_no_update() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

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
        .bind(format!("yousign-ignored+{}@nubia.test", prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet Yousign Ignored {}", cabinet_id))
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
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES ($1, $2, 'Pat2', 'Z')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
             VALUES ($1, $2, $3, 'sent', 80.00, 'EUR')",
        )
        .bind(quote_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let body = serde_json::to_vec(&json!({
        "event_type": "signature.started",
        "data": { "quote_id": quote_id.to_string() }
    }))
    .unwrap();
    let sig = make_sig(YOUSIGN_SECRET, &body);

    let response = build_app(app_pool().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/webhooks/yousign")
                .header("content-type", "application/json")
                .header("x-yousign-signature", &sig)
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    // Vérifie que la quote n'a PAS été modifiée.
    let row = sqlx::query("SELECT status, signed_at FROM quote WHERE id = $1")
        .bind(quote_id)
        .fetch_one(&db)
        .await
        .unwrap();

    let status: String = row.try_get("status").unwrap();
    let signed_at: Option<chrono::DateTime<chrono::Utc>> = row.try_get("signed_at").unwrap();

    assert_eq!(status, "sent", "status ne doit pas avoir changé");
    assert!(signed_at.is_none(), "signed_at doit rester null");

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM quote WHERE id = $1")
            .bind(quote_id)
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
