//! Tests d'intégration : POST /v1/auth/select-pharmacy-context (lot B1, issue #3306)

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

const JWT_SECRET: &str = "test-jwt-secret-select-pharmacy-context";

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

/// JWT pro sans contexte (token login — précédant la sélection de contexte).
fn make_pro_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// JWT patient (doit être rejeté en 403).
fn make_patient_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn test_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

/// Crée un app_user pro + une pharmacie (listée ou non) + un membership optionnel.
async fn seed_pharmacy(
    db: &PgPool,
    user_id: Uuid,
    pharmacy_id: Uuid,
    is_listed: bool,
    membership: Option<(&str, bool)>,
) {
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("spc+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query("INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, $2, $3)")
        .bind(pharmacy_id)
        .bind(format!("Pharmacie test {}", pharmacy_id))
        .bind(is_listed)
        .execute(db)
        .await
        .unwrap();

    if let Some((role, active)) = membership {
        sqlx::query(
            "INSERT INTO pharmacy_membership (pharmacy_id, user_id, role, active) \
             VALUES ($1, $2, $3, $4)",
        )
        .bind(pharmacy_id)
        .bind(user_id)
        .bind(role)
        .bind(active)
        .execute(db)
        .await
        .unwrap();
    }
}

async fn post_select(token: &str, pharmacy_id: Uuid) -> axum::response::Response {
    app(test_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/select-pharmacy-context")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({"pharmacy_id": pharmacy_id}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap()
}

// ── Test 1 : membre actif → 200 + JWT kind=pharma + cookie ────────────────────

#[tokio::test]
async fn select_pharmacy_context_valid_returns_200_with_token() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();
    seed_pharmacy(&db, user_id, pharmacy_id, true, Some(("pharmacist", true))).await;

    let response = post_select(&make_pro_jwt(user_id), pharmacy_id).await;
    assert_eq!(response.status(), StatusCode::OK);

    let set_cookie = response.headers().get("set-cookie");
    assert!(set_cookie.is_some(), "Set-Cookie header must be present");
    let cookie_val = set_cookie.unwrap().to_str().unwrap();
    assert!(cookie_val.starts_with("nubia_jwt="));
    assert!(cookie_val.contains("HttpOnly"));
    assert!(
        cookie_val.contains("Secure"),
        "cookie must be Secure (#3846)"
    );

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["token_type"], "Bearer");
    assert_eq!(v["expires_in"], 900);
    assert_eq!(v["context"]["pharmacy_id"], json!(pharmacy_id));
    assert_eq!(v["context"]["role"], "pharmacist");

    // Le token émis porte bien kind=pharma + pharmacy_id (claims décodables).
    let token = v["access_token"].as_str().unwrap();
    let decoded = jsonwebtoken::decode::<serde_json::Value>(
        token,
        &jsonwebtoken::DecodingKey::from_secret(JWT_SECRET.as_bytes()),
        &jsonwebtoken::Validation::default(),
    )
    .unwrap();
    assert_eq!(decoded.claims["kind"], "pharma");
    assert_eq!(decoded.claims["pharmacy_id"], json!(pharmacy_id));
}

// ── Test 2 : non-membre d'une pharmacie listée → 403 no_membership ────────────

#[tokio::test]
async fn select_pharmacy_context_non_member_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();
    seed_pharmacy(&db, user_id, pharmacy_id, true, None).await;

    let response = post_select(&make_pro_jwt(user_id), pharmacy_id).await;
    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "no_membership");
}

// ── Test 3 : pharmacie inexistante → 404 ──────────────────────────────────────

#[tokio::test]
async fn select_pharmacy_context_unknown_pharmacy_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("spc-404+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    let response = post_select(&make_pro_jwt(user_id), Uuid::new_v4()).await;
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

// ── Test 4 : membership inactif d'une pharmacie NON listée → 404 (anti-énumération)

#[tokio::test]
async fn select_pharmacy_context_inactive_membership_unlisted_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();
    seed_pharmacy(
        &db,
        user_id,
        pharmacy_id,
        false,
        Some(("pharmacist", false)),
    )
    .await;

    let response = post_select(&make_pro_jwt(user_id), pharmacy_id).await;
    // Membership inactif → pas de contexte ; pharmacie non listée → indistinguable
    // d'une pharmacie inexistante pour un non-membre (anti-énumération).
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

// ── Test 5 : token patient → 403 ──────────────────────────────────────────────

#[tokio::test]
async fn select_pharmacy_context_patient_token_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();
    seed_pharmacy(&db, user_id, pharmacy_id, true, Some(("pharmacist", true))).await;

    let response = post_select(&make_patient_jwt(user_id), pharmacy_id).await;
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 6 : sans Authorization → 401 ─────────────────────────────────────────

#[tokio::test]
async fn select_pharmacy_context_without_token_returns_401() {
    if !db_available() {
        return;
    }
    let response = app(test_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/select-pharmacy-context")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"pharmacy_id": Uuid::new_v4()}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 7 : GET /v1/me expose pharmacy_memberships ───────────────────────────

#[tokio::test]
async fn me_includes_pharmacy_memberships() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();
    seed_pharmacy(&db, user_id, pharmacy_id, false, Some(("admin", true))).await;

    let response = app(test_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
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
    let memberships = v["pharmacy_memberships"].as_array().unwrap();
    assert_eq!(memberships.len(), 1);
    assert_eq!(memberships[0]["pharmacy_id"], json!(pharmacy_id));
    assert_eq!(memberships[0]["role"], "admin");
}
