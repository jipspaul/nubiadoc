//! Tests d'intégration : GET/POST/PATCH/DELETE /v1/cabinet/members

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
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

/// Crée un JWT signé avec le rôle `secretary` (même secret que le stub).
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

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    }
}

/// Enregistre un pro, renvoie `(access_token, account_id, cabinet_id)`.
async fn register_pro(db: PgPool, email: &str) -> (String, Uuid, Uuid) {
    let body = json!({
        "email": email,
        "password": "password1",
        "cabinet": { "raison_sociale": "Cabinet Membres", "siret": null, "specialite": "dentaire" },
        "practitioner": { "first_name": "Alice", "last_name": "Martin", "rpps": null, "adeli": null }
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
    let account_id: Uuid = v["account_id"].as_str().unwrap().parse().unwrap();
    let cabinet_id: Uuid = v["cabinet_id"].as_str().unwrap().parse().unwrap();
    (token, account_id, cabinet_id)
}

// ── Test 1 : POST /v1/cabinet/members avec email existant → 409 ──────────────

#[tokio::test]
async fn post_cabinet_members_duplicate_email_returns_409() {
    if !db_available() {
        return;
    }
    let admin_email = format!("members_admin_{}@test.local", Uuid::new_v4());
    let member_email = format!("members_dup_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &admin_email).await;

    let member_body = json!({
        "email": member_email,
        "role": "secretary",
        "first_name": "Bob",
        "last_name": "Dupont"
    });

    // Première invitation → 201
    let r1 = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/members")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(member_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r1.status(), StatusCode::CREATED);

    // Deuxième invitation (même email, même cabinet) → 409
    let r2 = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/members")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(member_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r2.status(), StatusCode::CONFLICT);

    let bytes = axum::body::to_bytes(r2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "member_already_exists");

    let owner = owner_pool().await;
    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&admin_email)
        .execute(&owner)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&member_email)
        .execute(&owner)
        .await
        .ok();
}

// ── Test 2 : GET /v1/cabinet/members → 200 liste le créateur du cabinet ──────

#[tokio::test]
async fn get_cabinet_members_returns_list_with_admin() {
    if !db_available() {
        return;
    }
    let email = format!("members_list_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, account_id, _) = register_pro(db.clone(), &email).await;

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/members")
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
    let members: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let arr = members.as_array().expect("réponse doit être un tableau");
    assert!(
        arr.iter().any(|m| {
            m["user_id"].as_str().and_then(|s| s.parse::<Uuid>().ok()) == Some(account_id)
                && m["role"] == "admin"
        }),
        "le créateur admin doit figurer dans la liste"
    );

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 3 : GET /v1/cabinet/members non-admin → 403 ─────────────────────────

#[tokio::test]
async fn get_cabinet_members_non_admin_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("members_secretary_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id) = register_pro(db.clone(), &email).await;

    let secretary_token = make_secretary_token(account_id, cabinet_id);

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/members")
                .header("Authorization", format!("Bearer {}", secretary_token))
                .body(Body::empty())
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

// ── Test 4 : POST /v1/cabinet/members non-admin → 403 ────────────────────────

#[tokio::test]
async fn post_cabinet_members_non_admin_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("members_secretary_post_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id) = register_pro(db.clone(), &email).await;

    let secretary_token = make_secretary_token(account_id, cabinet_id);
    let member_body = json!({
        "email": format!("invitee_{}@test.local", Uuid::new_v4()),
        "role": "secretary",
        "first_name": "Carl",
        "last_name": "Dupont"
    });

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/members")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", secretary_token))
                .body(Body::from(member_body.to_string()))
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

// ── Test 5 : DELETE /v1/cabinet/members/:user_id admin OK → 204 ──────────────

#[tokio::test]
async fn delete_cabinet_member_admin_ok_returns_204() {
    if !db_available() {
        return;
    }
    let admin_email = format!("del_admin_{}@test.local", Uuid::new_v4());
    let member_email = format!("del_member_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &admin_email).await;

    // Invite a second member (secretary)
    let member_body = json!({
        "email": member_email,
        "role": "secretary",
        "first_name": "Dan",
        "last_name": "Durand"
    });
    let r_post = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/members")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(member_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r_post.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(r_post.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let member_id = v["user_id"].as_str().unwrap().to_string();

    // DELETE the secretary
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/cabinet/members/{}", member_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NO_CONTENT);

    let owner = owner_pool().await;
    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&admin_email)
        .execute(&owner)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&member_email)
        .execute(&owner)
        .await
        .ok();
}

// ── Test 6 : DELETE /v1/cabinet/members/:user_id last admin → 409 ────────────

#[tokio::test]
async fn delete_cabinet_member_last_admin_returns_409() {
    if !db_available() {
        return;
    }
    let admin_email = format!("del_lastadmin_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, account_id, _) = register_pro(db.clone(), &admin_email).await;

    // Try to delete the only admin (himself via a direct request using his own ID)
    // The handler blocks self-delete with 403, so we invite a second member first,
    // promote them to admin, then remove them — leaving the original as last admin.
    // Simpler: create a second admin and attempt to delete the first via token of second.
    // Easiest path: call DELETE on the admin's own ID from another admin's token is not possible
    // without a second admin token. Instead, create a non-admin member and make him admin,
    // then call DELETE /members/:original_admin from the second admin's token.
    // But POST promote is PATCH, not trivially available here.
    //
    // Simplest valid test: register a second pro (second cabinet), then try to remove
    // the only admin of the first cabinet using a manufactured token.
    // Actually the cleanest: invite a secretary, make admin (PATCH), then try deleting
    // the original admin — but we need a second JWT for that cabinet with role=admin.
    //
    // Cleanest feasible path without PATCH dependency:
    // Use make_secretary_token with role admin to impersonate a second admin,
    // then try to DELETE the real admin (account_id). The guard checks active admin count,
    // which is 1, so it should return 409.

    #[derive(serde::Serialize)]
    struct Claims {
        sub: uuid::Uuid,
        kind: String,
        cabinet_id: uuid::Uuid,
        role: String,
        exp: u64,
    }
    let exp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    // Parse the real cabinet_id from the register response is already done via account_id.
    // We need cabinet_id — extract it from the original token we have.
    // Re-parse the JWT to get cabinet_id.
    use jsonwebtoken::{decode, Algorithm, DecodingKey, Validation};
    #[derive(serde::Deserialize)]
    struct PartialClaims {
        cabinet_id: uuid::Uuid,
    }
    let mut val = Validation::new(Algorithm::HS256);
    val.validate_exp = false;
    let cabinet_id =
        decode::<PartialClaims>(&token, &DecodingKey::from_secret(b"test-secret"), &val)
            .unwrap()
            .claims
            .cabinet_id;

    // Forge a second-admin token (same cabinet, different sub so self-delete check passes).
    let fake_second_admin_id = Uuid::new_v4();
    let second_admin_token = jsonwebtoken::encode(
        &jsonwebtoken::Header::default(),
        &Claims {
            sub: fake_second_admin_id,
            kind: "pro".into(),
            cabinet_id,
            role: "admin".into(),
            exp,
        },
        &jsonwebtoken::EncodingKey::from_secret(b"test-secret"),
    )
    .unwrap();

    // Try to delete the only real admin using this forged second-admin token.
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/cabinet/members/{}", account_id))
                .header("Authorization", format!("Bearer {}", second_admin_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CONFLICT);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "last_admin_cannot_be_removed");

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&admin_email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 8 : PATCH /v1/cabinet/members/:user_id admin OK → 200 ───────────────

#[tokio::test]
async fn patch_cabinet_member_admin_ok_returns_200() {
    if !db_available() {
        return;
    }
    let admin_email = format!("patch_admin_{}@test.local", Uuid::new_v4());
    let member_email = format!("patch_member_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &admin_email).await;

    // Invite a secretary
    let member_body = json!({
        "email": member_email,
        "role": "secretary",
        "first_name": "Eve",
        "last_name": "Durand"
    });
    let r_post = app(make_state(db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/members")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(member_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r_post.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(r_post.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let member_id = v["user_id"].as_str().unwrap().to_string();

    // PATCH → promote to manager
    let patch_body = json!({ "role": "manager" });
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/members/{}", member_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(patch_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["role"], "manager");
    assert_eq!(v["user_id"].as_str().unwrap(), member_id);

    let owner = owner_pool().await;
    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&admin_email)
        .execute(&owner)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&member_email)
        .execute(&owner)
        .await
        .ok();
}

// ── Test 9 : PATCH /v1/cabinet/members/:user_id non-admin → 403 ──────────────

#[tokio::test]
async fn patch_cabinet_member_non_admin_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("patch_secretary_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id) = register_pro(db.clone(), &email).await;

    let secretary_token = make_secretary_token(account_id, cabinet_id);
    let patch_body = json!({ "role": "admin" });

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/members/{}", account_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", secretary_token))
                .body(Body::from(patch_body.to_string()))
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

// ── Test 10 : PATCH /v1/cabinet/members/:user_id user not member → 404 ────────

#[tokio::test]
async fn patch_cabinet_member_not_member_returns_404() {
    if !db_available() {
        return;
    }
    let admin_email = format!("patch_notmember_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &admin_email).await;

    let unknown_user_id = Uuid::new_v4();
    let patch_body = json!({ "role": "secretary" });

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/members/{}", unknown_user_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(patch_body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(&admin_email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 7 : DELETE /v1/cabinet/members/:user_id non-admin → 403 ─────────────

#[tokio::test]
async fn delete_cabinet_member_non_admin_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("del_secretary_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id) = register_pro(db.clone(), &email).await;

    let secretary_token = make_secretary_token(account_id, cabinet_id);

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/cabinet/members/{}", account_id))
                .header("Authorization", format!("Bearer {}", secretary_token))
                .body(Body::empty())
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
