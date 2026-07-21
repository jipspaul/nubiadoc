//! Tests d'intégration : `cabinet_membership.permissions` consommée par
//! GET /v1/cabinet/quotes (#4081)

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

const JWT_SECRET: &str = "test-jwt-secret-quotes-billing-permission";

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

fn make_secretary_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
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
            "role": "secretary",
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn insert_cabinet_and_user(db: &PgPool, tag: &str) -> (Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("quotes-billing-perm-{tag}+{user_id}@nubia.test"))
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
        .bind(format!("Cabinet QuotesBillingPerm {tag} {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    (cabinet_id, user_id)
}

async fn insert_membership(db: &PgPool, cabinet_id: Uuid, user_id: Uuid, permissions: &str) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, permissions) \
         VALUES ($1, $2, 'secretary', $3::jsonb)",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .bind(permissions)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, user_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_membership WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
}

/// Spec exacte de l'issue #4081 : membership `permissions:{"billing":false}`
/// → 403 sur GET /v1/cabinet/quotes malgré le rôle secretary, normalement
/// autorisé.
#[tokio::test]
async fn billing_permission_false_forbids_secretary_from_quotes() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id) = insert_cabinet_and_user(&db, "denied").await;
    insert_membership(&db, cabinet_id, user_id, r#"{"billing": false}"#).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/quotes")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_secretary_jwt(user_id, cabinet_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::FORBIDDEN,
        "permissions.billing=false doit bloquer même un rôle secretary normalement autorisé"
    );

    cleanup(&db, cabinet_id, user_id).await;
}

/// Non-régression : `permissions = {}` (valeur par défaut de la colonne,
/// migration 0002) → toujours autorisé (default-allow).
#[tokio::test]
async fn billing_permission_empty_object_still_allows_secretary() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id) = insert_cabinet_and_user(&db, "default").await;
    insert_membership(&db, cabinet_id, user_id, "{}").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/quotes")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_secretary_jwt(user_id, cabinet_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::OK,
        "permissions={{}} (défaut) ne doit rien changer au comportement existant"
    );

    cleanup(&db, cabinet_id, user_id).await;
}

/// Non-régression : aucune ligne `cabinet_membership` du tout (comme tous
/// les tests JWT-only existants de `cabinet_quotes_get.rs`) → toujours
/// autorisé.
#[tokio::test]
async fn billing_permission_no_membership_row_still_allows_secretary() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id) = insert_cabinet_and_user(&db, "nomembership").await;
    // Pas d'INSERT cabinet_membership.

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/quotes")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_secretary_jwt(user_id, cabinet_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::OK,
        "absence de ligne cabinet_membership ne doit pas bloquer (default-allow)"
    );

    cleanup(&db, cabinet_id, user_id).await;
}
