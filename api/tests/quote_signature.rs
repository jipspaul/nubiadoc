//! Tests d'intégration : POST /v1/quotes/:id/signature (#4064)
//!
//! Démarrage réel d'une session de signature Yousign (mock HTTP server) :
//! 202 + redirect_url, le devis reste `sent` (la transition `signed` arrive
//! uniquement par webhook, hors scope de ce test).

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
use wiremock::matchers::method;
use wiremock::{Mock, MockServer, ResponseTemplate};

use nubia_api::{app_with_quote_signature_client, AppState, StubMailer, YousignClient};

const JWT_SECRET: &str = "test-jwt-secret-quote-signature";

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
        &json!({
            "sub": user_id,
            "kind": "patient",
            "account_id": account_id,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
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

struct Fixture {
    cabinet_id: Uuid,
    patient_account_user_id: Uuid,
    patient_account_id: Uuid,
    patient_id: Uuid,
    quote_id: Uuid,
}

/// Seed : cabinet + patient (compte + fiche) + devis au statut `status`.
async fn seed(db: &PgPool, status: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let account_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(account_user_id)
    .bind(format!("quote-sig+{account_user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Signature')",
    )
    .bind(account_id)
    .bind(account_user_id)
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet QuoteSig {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Test', 'Signature', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, $4, 100.00, 'EUR')",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        patient_account_user_id: account_user_id,
        patient_account_id: account_id,
        patient_id,
        quote_id,
    }
}

async fn quote_row(db: &PgPool, cabinet_id: Uuid, quote_id: Uuid) -> (String, Option<Uuid>) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT status, signature_id FROM quote WHERE id = $1")
        .bind(quote_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    let status: String = row.try_get("status").unwrap();
    let signature_id: Option<Uuid> = row.try_get("signature_id").unwrap();
    tx.commit().await.unwrap();
    (status, signature_id)
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("UPDATE quote SET signature_id = NULL WHERE id = $1")
        .bind(f.quote_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM signature WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE id = $1")
        .bind(f.quote_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();

    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.patient_account_user_id)
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

async fn initiate_signature(
    state: AppState,
    yousign_base_url: &str,
    quote_id: Uuid,
    token: String,
) -> (StatusCode, serde_json::Value) {
    let client = Arc::new(YousignClient::with_base_url(
        "test-api-key",
        yousign_base_url,
    ));
    let response = app_with_quote_signature_client(state, client)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/quotes/{quote_id}/signature"))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
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

// ── Test 1 : happy path — 202 + redirect_url, devis reste `sent` ────────────

#[tokio::test]
async fn initiate_signature_on_sent_quote_returns_202_and_keeps_sent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "sent").await;

    let mock_server = MockServer::start().await;
    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "id": "yousign-session-abc123",
            "redirect_url": "https://yousign.example/sign/abc123"
        })))
        .expect(1)
        .mount(&mock_server)
        .await;

    let (status, body) = initiate_signature(
        state_with(app_pool().await),
        &mock_server.uri(),
        f.quote_id,
        make_patient_jwt(f.patient_account_user_id, f.patient_account_id),
    )
    .await;

    assert_eq!(status, StatusCode::ACCEPTED);
    assert_eq!(body["provider"], "yousign");
    assert_eq!(body["redirect_url"], "https://yousign.example/sign/abc123");
    assert!(body["signature_id"].is_string());

    // Le devis reste `sent` — seul le webhook fera la transition vers `signed`.
    let (db_status, signature_id) = quote_row(&db, f.cabinet_id, f.quote_id).await;
    assert_eq!(db_status, "sent");
    assert!(signature_id.is_some(), "quote.signature_id doit être posé");

    cleanup(&db, &f).await;
}

// ── Test 2 : devis déjà signé → 409 quote_locked, aucun appel provider ──────

#[tokio::test]
async fn initiate_signature_on_signed_quote_returns_409_without_calling_provider() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;

    let mock_server = MockServer::start().await;
    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(200))
        .expect(0)
        .mount(&mock_server)
        .await;

    let (status, body) = initiate_signature(
        state_with(app_pool().await),
        &mock_server.uri(),
        f.quote_id,
        make_patient_jwt(f.patient_account_user_id, f.patient_account_id),
    )
    .await;

    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "quote_locked");

    cleanup(&db, &f).await;
}

// ── Test 3 : devis draft (pas encore envoyé) → 404, masqué par la RLS ───────
//
// Assertion corrigée (dérive pré-existante, découverte en vérifiant contre
// Postgres réel, sans lien avec le diff en cours) : la policy
// `quote_patient_read` (migration 0134/#3487) exclut `status = 'draft'` de la
// visibilité patient — un brouillon cabinet non encore envoyé. Le JOIN de
// `initiate_quote_signature` est donc filtré par la RLS avant même d'évaluer
// son propre contrôle de statut : un devis `draft` renvoie TOUJOURS 404, ne
// peut structurellement jamais atteindre la branche `409 invalid_status`.
// L'assertion originale (409) date d'avant la migration 0134 et n'avait
// jamais été mise à jour.

#[tokio::test]
async fn initiate_signature_on_draft_quote_returns_404_hidden_by_rls() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "draft").await;

    let mock_server = MockServer::start().await;
    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(200))
        .expect(0)
        .mount(&mock_server)
        .await;

    let (status, _body) = initiate_signature(
        state_with(app_pool().await),
        &mock_server.uri(),
        f.quote_id,
        make_patient_jwt(f.patient_account_user_id, f.patient_account_id),
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}

// ── Test 4 : provider en erreur → 502, quote.signature_id reste NULL ────────

#[tokio::test]
async fn initiate_signature_provider_error_returns_502() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "sent").await;

    let mock_server = MockServer::start().await;
    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(500))
        .mount(&mock_server)
        .await;

    let (status, body) = initiate_signature(
        state_with(app_pool().await),
        &mock_server.uri(),
        f.quote_id,
        make_patient_jwt(f.patient_account_user_id, f.patient_account_id),
    )
    .await;

    assert_eq!(status, StatusCode::BAD_GATEWAY);
    assert_eq!(body["code"], "upstream_unavailable");

    let (db_status, signature_id) = quote_row(&db, f.cabinet_id, f.quote_id).await;
    assert_eq!(db_status, "sent");
    assert!(signature_id.is_none());

    cleanup(&db, &f).await;
}

// ── Test 5 : token pro → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn initiate_signature_with_pro_token_returns_403() {
    let mock_server = MockServer::start().await;
    let state = AppState {
        db: PgPool::connect_lazy(
            &std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
        )
        .unwrap(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let (status, _) = initiate_signature(
        state,
        &mock_server.uri(),
        Uuid::new_v4(),
        make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "practitioner"),
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);
}

// ── Test 6 : devis inexistant / hors patient → 404 ───────────────────────────

#[tokio::test]
async fn initiate_signature_unknown_quote_returns_404() {
    if !db_available() {
        return;
    }
    let mock_server = MockServer::start().await;
    Mock::given(method("POST"))
        .respond_with(ResponseTemplate::new(200))
        .expect(0)
        .mount(&mock_server)
        .await;

    let (status, _) = initiate_signature(
        state_with(app_pool().await),
        &mock_server.uri(),
        Uuid::new_v4(),
        make_patient_jwt(Uuid::new_v4(), Uuid::new_v4()),
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
}
