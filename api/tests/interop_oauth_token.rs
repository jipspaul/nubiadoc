//! Tests d'intégration : POST /v1/interop/oauth/token (lot A1, socle auth partenaire).
//!
//! Couvre : succès (client_credentials, scope sous-ensemble), client inconnu,
//! secret invalide, client révoqué, tentative d'escalade de scope.
//! Suit le même pattern que `api/tests/account_avatar.rs` : skip silencieux
//! si `APP_DATABASE_URL`/`DATABASE_URL` ne sont pas configurées (pas de
//! Postgres dans ce sandbox — cf. rapport de vérification de la PR).

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use integrations_interop::hash_secret;
use serde_json::Value;
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-interop-oauth-token";

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

fn state_sync(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

/// Crée un cabinet + interop_client + interop_client_secret (owner pool,
/// bypass RLS — même pattern que `insert_account` dans account_avatar.rs).
async fn insert_client(
    db: &PgPool,
    client_id: &str,
    secret: &str,
    scopes: &[&str],
    status: &str,
) -> (Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let interop_client_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, $2)")
        .bind(cabinet_id)
        .bind(format!("Cabinet interop test {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    let scopes_owned: Vec<String> = scopes.iter().map(|s| s.to_string()).collect();
    sqlx::query(
        "INSERT INTO interop_client (id, client_id, cabinet_id, display_name, scopes, status) \
         VALUES ($1, $2, $3, 'PMS externe test', $4, $5)",
    )
    .bind(interop_client_id)
    .bind(client_id)
    .bind(cabinet_id)
    .bind(&scopes_owned)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();
    let hash = hash_secret(secret).unwrap();
    sqlx::query("INSERT INTO interop_client_secret (client_id_ref, secret_hash) VALUES ($1, $2)")
        .bind(interop_client_id)
        .bind(hash)
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    (cabinet_id, interop_client_id)
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, interop_client_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("DELETE FROM interop_client_secret WHERE client_id_ref = $1")
        .bind(interop_client_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM interop_client WHERE id = $1")
        .bind(interop_client_id)
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

async fn post_token(state: AppState, form_body: &str) -> (StatusCode, Value) {
    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/interop/oauth/token")
                .header("content-type", "application/x-www-form-urlencoded")
                .body(Body::from(form_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&bytes).unwrap();
    (status, json)
}

// ── Succès : client_credentials, scope sous-ensemble des scopes accordés ────

#[tokio::test]
async fn issues_token_for_valid_client_credentials() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, interop_client_id) = insert_client(
        &owner,
        "client-a1-ok",
        "s3cret-ok",
        &["appointments:read", "directory:read"],
        "active",
    )
    .await;

    let (status, body) = post_token(
        state_sync(app_pool().await),
        "grant_type=client_credentials&client_id=client-a1-ok&client_secret=s3cret-ok&scope=appointments%3Aread",
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert!(body["access_token"].as_str().is_some_and(|s| !s.is_empty()));
    assert_eq!(body["token_type"], "Bearer");
    assert_eq!(body["expires_in"], 900);
    assert_eq!(body["scope"], "appointments:read");

    cleanup(&owner, cabinet_id, interop_client_id).await;
}

// ── Scope absent de la requête → tous les scopes accordés ───────────────────

#[tokio::test]
async fn omitted_scope_grants_all_client_scopes() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, interop_client_id) = insert_client(
        &owner,
        "client-a1-noscope",
        "s3cret-noscope",
        &["appointments:read", "directory:read"],
        "active",
    )
    .await;

    let (status, body) = post_token(
        state_sync(app_pool().await),
        "grant_type=client_credentials&client_id=client-a1-noscope&client_secret=s3cret-noscope",
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["scope"], "appointments:read directory:read");

    cleanup(&owner, cabinet_id, interop_client_id).await;
}

// ── client_id inconnu → 401 invalid_client ───────────────────────────────────

#[tokio::test]
async fn unknown_client_id_returns_invalid_client() {
    if !db_available() {
        return;
    }
    let (status, body) = post_token(
        state_sync(app_pool().await),
        "grant_type=client_credentials&client_id=does-not-exist&client_secret=whatever",
    )
    .await;

    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body["error"], "invalid_client");
}

// ── secret incorrect → 401 invalid_client ────────────────────────────────────

#[tokio::test]
async fn wrong_secret_returns_invalid_client() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, interop_client_id) = insert_client(
        &owner,
        "client-a1-badsecret",
        "the-real-secret",
        &["appointments:read"],
        "active",
    )
    .await;

    let (status, body) = post_token(
        state_sync(app_pool().await),
        "grant_type=client_credentials&client_id=client-a1-badsecret&client_secret=not-the-secret",
    )
    .await;

    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body["error"], "invalid_client");

    cleanup(&owner, cabinet_id, interop_client_id).await;
}

// ── client révoqué → 401 invalid_client même avec le bon secret ─────────────

#[tokio::test]
async fn revoked_client_returns_invalid_client() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, interop_client_id) = insert_client(
        &owner,
        "client-a1-revoked",
        "still-the-secret",
        &["appointments:read"],
        "revoked",
    )
    .await;

    let (status, body) = post_token(
        state_sync(app_pool().await),
        "grant_type=client_credentials&client_id=client-a1-revoked&client_secret=still-the-secret",
    )
    .await;

    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body["error"], "invalid_client");

    cleanup(&owner, cabinet_id, interop_client_id).await;
}

// ── tentative d'escalade de scope → 400 invalid_scope ────────────────────────

#[tokio::test]
async fn scope_escalation_attempt_returns_invalid_scope() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, interop_client_id) = insert_client(
        &owner,
        "client-a1-escalate",
        "s3cret-escalate",
        &["directory:read"],
        "active",
    )
    .await;

    let (status, body) = post_token(
        state_sync(app_pool().await),
        "grant_type=client_credentials&client_id=client-a1-escalate&client_secret=s3cret-escalate&scope=appointments%3Awrite",
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"], "invalid_scope");

    cleanup(&owner, cabinet_id, interop_client_id).await;
}

// ── #4615 : paramètre requis totalement ABSENT (pas juste vide) ─────────────
// → doit produire la même enveloppe RFC 6749 que le cas « champ présent mais
// vide » (`InteropError::InvalidRequest`, 400 `{"error":"invalid_request"}`),
// et non le 422 `{"code":"validation_error"}` générique émis par défaut par
// l'extracteur `Form` d'Axum sur un champ manquant.

#[tokio::test]
async fn missing_client_secret_field_returns_rfc6749_invalid_request() {
    if !db_available() {
        return;
    }
    let (status, body) = post_token(
        state_sync(app_pool().await),
        "grant_type=client_credentials&client_id=x",
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"], "invalid_request");
}

#[tokio::test]
async fn empty_client_id_field_present_returns_same_invalid_request_envelope() {
    if !db_available() {
        return;
    }
    let (status, body) = post_token(
        state_sync(app_pool().await),
        "grant_type=client_credentials&client_id=&client_secret=y",
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"], "invalid_request");
}

// ── grant_type non supporté → 400 unsupported_grant_type ─────────────────────

#[tokio::test]
async fn unsupported_grant_type_is_rejected() {
    if !db_available() {
        return;
    }
    let (status, body) = post_token(
        state_sync(app_pool().await),
        "grant_type=authorization_code&client_id=whatever&client_secret=whatever",
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["error"], "unsupported_grant_type");
}
