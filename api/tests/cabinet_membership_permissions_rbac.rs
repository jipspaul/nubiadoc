//! Tests d'intégration : RBAC de `PATCH /v1/cabinet/membership/:user_id/permissions`
//! (#5739 : un manager ne doit pas pouvoir modifier ses propres permissions,
//! ni celles d'un autre manager/admin — seul un `secretary` de son cabinet).

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

const JWT_SECRET: &str = "test-jwt-secret-membership-permissions-rbac";

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

fn make_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
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

async fn insert_cabinet(db: &PgPool, tag: &str) -> Uuid {
    let cabinet_id = Uuid::new_v4();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet MembershipPermRbac {tag} {cabinet_id}"))
        .execute(db)
        .await
        .unwrap();
    cabinet_id
}

async fn insert_member(db: &PgPool, cabinet_id: Uuid, tag: &str, role: &str) -> Uuid {
    let user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("membership-perm-rbac-{tag}+{user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES ($1, $2, $3)",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .bind(role)
    .execute(db)
    .await
    .unwrap();

    user_id
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, user_ids: &[Uuid]) {
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_membership WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
    for user_id in user_ids {
        sqlx::query("DELETE FROM app_user WHERE id = $1")
            .bind(user_id)
            .execute(db)
            .await
            .ok();
    }
}

async fn patch_permissions(
    state: AppState,
    actor_jwt: &str,
    target_user_id: Uuid,
    billing: bool,
) -> StatusCode {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/membership/{target_user_id}/permissions"))
                .header("Authorization", format!("Bearer {actor_jwt}"))
                .header("content-type", "application/json")
                .body(Body::from(json!({"billing": billing}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    response.status()
}

/// Repro exacte #5739 : un manager ne doit pas pouvoir restaurer lui-même
/// la permission `billing` que l'admin vient de lui retirer.
#[tokio::test]
async fn manager_cannot_self_restore_billing_permission() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = insert_cabinet(&db, "self-escalation").await;
    let manager_id = insert_member(&db, cabinet_id, "manager", "manager").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let manager_jwt = make_jwt(manager_id, cabinet_id, "manager");

    let status = patch_permissions(state.clone(), &manager_jwt, manager_id, true).await;

    assert_eq!(
        status,
        StatusCode::FORBIDDEN,
        "un manager ne doit pas pouvoir modifier ses propres permissions"
    );

    cleanup(&db, cabinet_id, &[manager_id]).await;
}

/// Un manager ne doit pas non plus pouvoir modifier les permissions d'un
/// autre manager ou d'un admin de son cabinet.
#[tokio::test]
async fn manager_cannot_modify_another_manager_or_admin_permissions() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = insert_cabinet(&db, "cross-manager").await;
    let manager_a = insert_member(&db, cabinet_id, "manager-a", "manager").await;
    let manager_b = insert_member(&db, cabinet_id, "manager-b", "manager").await;
    let admin_id = insert_member(&db, cabinet_id, "admin", "admin").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let manager_a_jwt = make_jwt(manager_a, cabinet_id, "manager");

    let status = patch_permissions(state.clone(), &manager_a_jwt, manager_b, true).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let status = patch_permissions(state.clone(), &manager_a_jwt, admin_id, true).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    cleanup(&db, cabinet_id, &[manager_a, manager_b, admin_id]).await;
}

/// Non-régression : un manager peut toujours modifier les permissions d'un
/// `secretary` de son cabinet.
#[tokio::test]
async fn manager_can_modify_secretary_permissions() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = insert_cabinet(&db, "manager-secretary").await;
    let manager_id = insert_member(&db, cabinet_id, "manager", "manager").await;
    let secretary_id = insert_member(&db, cabinet_id, "secretary", "secretary").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let manager_jwt = make_jwt(manager_id, cabinet_id, "manager");

    let status = patch_permissions(state.clone(), &manager_jwt, secretary_id, false).await;
    assert_eq!(status, StatusCode::OK);

    cleanup(&db, cabinet_id, &[manager_id, secretary_id]).await;
}

/// Non-régression : un admin peut toujours modifier les permissions d'un
/// manager (seul chemin légitime pour lever/imposer la restriction).
#[tokio::test]
async fn admin_can_modify_manager_permissions() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = insert_cabinet(&db, "admin-manager").await;
    let admin_id = insert_member(&db, cabinet_id, "admin", "admin").await;
    let manager_id = insert_member(&db, cabinet_id, "manager", "manager").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let admin_jwt = make_jwt(admin_id, cabinet_id, "admin");

    let status = patch_permissions(state.clone(), &admin_jwt, manager_id, false).await;
    assert_eq!(status, StatusCode::OK);

    cleanup(&db, cabinet_id, &[admin_id, manager_id]).await;
}
