//! Tests d'intégration #7148 (DP-F25.b) :
//! - POST /v1/cabinet/invite-links → 201 (admin) / 403 (non-admin) / 422 (rôle invalide)
//! - POST /v1/auth/register { invite_link_token } → 201 (compte pro rattaché
//!   au cabinet+rôle du lien) / 400 (token inconnu) / 410 (expiré/épuisé)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
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

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "secretary".into(),
            exp,
        },
        &EncodingKey::from_secret(b"test-secret"),
    )
    .unwrap()
}

/// Enregistre un cabinet pro, renvoie `(access_token, admin_user_id, cabinet_id)`.
async fn register_pro(db: PgPool, email: &str) -> (String, Uuid, Uuid) {
    let body = json!({
        "email": email,
        "password": "password1",
        "cabinet": { "raison_sociale": "Cabinet Invite", "siret": null, "specialite": "dentaire" },
        "practitioner": { "first_name": "Admin", "last_name": "Test", "rpps": null, "adeli": null }
    });
    let resp = app(make_state(db))
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
    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let token = v["access_token"].as_str().unwrap().to_string();
    let account_id: Uuid = v["account_id"].as_str().unwrap().parse().unwrap();
    let cabinet_id: Uuid = v["cabinet_id"].as_str().unwrap().parse().unwrap();
    (token, account_id, cabinet_id)
}

// ── Test 1 : admin crée un lien → 201 ────────────────────────────────────────

#[tokio::test]
async fn create_invite_link_as_admin_returns_201() {
    if !db_available() {
        return;
    }
    let email = format!("inv_admin_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, cabinet_id) = register_pro(db.clone(), &email).await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/invite-links")
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(json!({ "role": "secretary" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["role"], "secretary");
    assert!(v["token"].as_str().is_some());
    assert!(v["url"]
        .as_str()
        .unwrap()
        .contains(v["token"].as_str().unwrap()));
    assert_eq!(v["max_uses"], 20);

    let row = sqlx::query("SELECT cabinet_id FROM cabinet_invite_link WHERE id = $1")
        .bind(Uuid::parse_str(v["id"].as_str().unwrap()).unwrap())
        .fetch_one(&owner_pool().await)
        .await
        .unwrap();
    let stored_cabinet_id: Uuid = row.try_get("cabinet_id").unwrap();
    assert_eq!(stored_cabinet_id, cabinet_id);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 2 : non-admin → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn create_invite_link_non_admin_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("inv_403_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id) = register_pro(db.clone(), &email).await;
    let secretary_token = make_secretary_token(account_id, cabinet_id);

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/invite-links")
                .header("Authorization", format!("Bearer {}", secretary_token))
                .header("content-type", "application/json")
                .body(Body::from(json!({ "role": "secretary" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 3 : rôle hors énumération → 422 ────────────────────────────────────

#[tokio::test]
async fn create_invite_link_invalid_role_returns_422() {
    if !db_available() {
        return;
    }
    let email = format!("inv_422_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &email).await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/invite-links")
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(json!({ "role": "superadmin" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 4 : register via lien valide → 201, compte pro rattaché ────────────

#[tokio::test]
async fn register_via_invite_link_returns_201_and_creates_membership() {
    if !db_available() {
        return;
    }
    let email = format!("inv_owner_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, cabinet_id) = register_pro(db.clone(), &email).await;

    let create_resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/invite-links")
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(json!({ "role": "secretary" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(create_resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(create_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let link: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let link_token = link["token"].as_str().unwrap().to_string();

    let new_email = format!("inv_new_{}@test.local", Uuid::new_v4());
    let register_resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": new_email,
                        "password": "password1",
                        "accept_cgu": true,
                        "cgu_version": "v1",
                        "invite_link_token": link_token,
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(register_resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(register_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let new_user_id: Uuid = v["account_id"].as_str().unwrap().parse().unwrap();
    assert!(v["access_token"].as_str().is_some());

    let row = sqlx::query("SELECT cabinet_id, role FROM cabinet_membership WHERE user_id = $1")
        .bind(new_user_id)
        .fetch_one(&owner_pool().await)
        .await
        .unwrap();
    let membership_cabinet_id: Uuid = row.try_get("cabinet_id").unwrap();
    let membership_role: String = row.try_get("role").unwrap();
    assert_eq!(membership_cabinet_id, cabinet_id);
    assert_eq!(membership_role, "secretary");

    let uses: i32 = sqlx::query_scalar("SELECT uses FROM cabinet_invite_link WHERE token = $1")
        .bind(&link_token)
        .fetch_one(&owner_pool().await)
        .await
        .unwrap();
    assert_eq!(uses, 1);

    sqlx::query("DELETE FROM app_user WHERE email IN ($1, $2)")
        .bind(&email)
        .bind(&new_email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 5 : register avec un token inconnu → 400 ────────────────────────────

#[tokio::test]
async fn register_via_unknown_invite_link_token_returns_400() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let email = format!("inv_unknown_{}@test.local", Uuid::new_v4());

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": email,
                        "password": "password1",
                        "accept_cgu": true,
                        "cgu_version": "v1",
                        "invite_link_token": Uuid::new_v4().to_string(),
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "invitation_invalid");
}

// ── Test 6 : register via lien épuisé (uses >= max_uses) → 410 ──────────────

#[tokio::test]
async fn register_via_exhausted_invite_link_returns_410() {
    if !db_available() {
        return;
    }
    let email = format!("inv_exhausted_owner_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &email).await;

    let create_resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/invite-links")
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({ "role": "secretary", "max_uses": 1 }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let bytes = axum::body::to_bytes(create_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let link: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let link_token = link["token"].as_str().unwrap().to_string();

    let first_email = format!("inv_first_{}@test.local", Uuid::new_v4());
    let first_resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": first_email,
                        "password": "password1",
                        "accept_cgu": true,
                        "cgu_version": "v1",
                        "invite_link_token": link_token,
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(first_resp.status(), StatusCode::CREATED);

    let second_email = format!("inv_second_{}@test.local", Uuid::new_v4());
    let second_resp = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "email": second_email,
                        "password": "password1",
                        "accept_cgu": true,
                        "cgu_version": "v1",
                        "invite_link_token": link_token,
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(second_resp.status(), StatusCode::GONE);
    let bytes = axum::body::to_bytes(second_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "link_expired");

    sqlx::query("DELETE FROM app_user WHERE email IN ($1, $2, $3)")
        .bind(&email)
        .bind(&first_email)
        .bind(&second_email)
        .execute(&owner_pool().await)
        .await
        .ok();
}
