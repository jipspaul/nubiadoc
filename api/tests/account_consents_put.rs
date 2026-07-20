//! Tests d'intégration : PUT /v1/account/consents/{purpose}

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

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-consents-put";

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
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "role": "admin",
                "account_id": Uuid::nil(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn setup_patient(db: &PgPool) -> (Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("consents-put+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Patient')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
    (user_id, account_id)
}

async fn cleanup(db: &PgPool, user_id: Uuid) {
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : PUT granted=true → 200 avec purpose + granted + updated_at ─────

#[tokio::test]
async fn consent_put_granted_true_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id) = setup_patient(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/consents/soins")
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::from(r#"{"granted":true}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["purpose"], "soins");
    assert_eq!(v["granted"], true);
    assert!(v["updated_at"].is_string(), "updated_at doit être présent");

    cleanup(&db, user_id).await;
}

// ── Test 2 : PUT granted=false → 200, revoked_at présent en base ─────────────

#[tokio::test]
async fn consent_put_granted_false_sets_revoked_at() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id) = setup_patient(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/consents/marketing")
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::from(r#"{"granted":false}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["purpose"], "marketing");
    assert_eq!(v["granted"], false);
    assert!(v["updated_at"].is_string(), "updated_at doit être présent");

    // Vérifie que revoked_at est bien peuplé en base.
    let row = sqlx::query(
        "SELECT revoked_at FROM consent_record WHERE patient_account_id = $1 AND purpose = 'marketing'",
    )
    .bind(account_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let revoked_at: Option<chrono::DateTime<chrono::Utc>> = row.try_get("revoked_at").unwrap();
    assert!(revoked_at.is_some(), "revoked_at doit être peuplé");

    cleanup(&db, user_id).await;
}

// ── Test 3 : PUT deux fois granted=true → idempotent, 200 les deux fois ──────

#[tokio::test]
async fn consent_put_idempotent_double_grant() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id) = setup_patient(&db).await;

    let make_state = || AppState {
        db: {
            let url = std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
            PgPool::connect_lazy(&url).unwrap()
        },
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    for _ in 0..2 {
        let response = app(make_state())
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri("/v1/account/consents/soins")
                    .header("Content-Type", "application/json")
                    .header(
                        "Authorization",
                        format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                    )
                    .body(Body::from(r#"{"granted":true}"#))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }

    // Un seul enregistrement en base (upsert).
    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM consent_record WHERE patient_account_id = $1 AND purpose = 'soins'",
    )
    .bind(account_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(count, 1, "upsert doit produire un seul enregistrement");

    cleanup(&db, user_id).await;
}

// ── Test 3bis : ré-affirmer granted=true déjà accordé ne bouge pas granted_at
// (#3876 — l'upsert doit être vraiment idempotent, pas juste dédupliquer la ligne) ──

#[tokio::test]
async fn consent_put_reaffirm_granted_true_keeps_granted_at_stable() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id) = setup_patient(&db).await;

    let make_state = || AppState {
        db: {
            let url = std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
            PgPool::connect_lazy(&url).unwrap()
        },
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let put_grant = || {
        Request::builder()
            .method("PUT")
            .uri("/v1/account/consents/marketing")
            .header("Content-Type", "application/json")
            .header(
                "Authorization",
                format!("Bearer {}", make_patient_jwt(user_id, account_id)),
            )
            .body(Body::from(r#"{"granted":true}"#))
            .unwrap()
    };

    let r1 = app(make_state()).oneshot(put_grant()).await.unwrap();
    assert_eq!(r1.status(), StatusCode::OK);

    let granted_at_1: chrono::DateTime<chrono::Utc> = sqlx::query(
        "SELECT granted_at FROM consent_record \
         WHERE patient_account_id = $1 AND purpose = 'marketing'",
    )
    .bind(account_id)
    .fetch_one(&db)
    .await
    .unwrap()
    .try_get("granted_at")
    .unwrap();

    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    // Ré-affirme le MÊME état (granted:true, déjà accordé) — no-op logique.
    let r2 = app(make_state()).oneshot(put_grant()).await.unwrap();
    assert_eq!(r2.status(), StatusCode::OK);

    let granted_at_2: chrono::DateTime<chrono::Utc> = sqlx::query(
        "SELECT granted_at FROM consent_record \
         WHERE patient_account_id = $1 AND purpose = 'marketing'",
    )
    .bind(account_id)
    .fetch_one(&db)
    .await
    .unwrap()
    .try_get("granted_at")
    .unwrap();

    assert_eq!(
        granted_at_1, granted_at_2,
        "granted_at doit rester stable sur une ré-affirmation idempotente, \
         pas être réécrit à chaque PUT granted:true"
    );

    cleanup(&db, user_id).await;
}

// ── Test 3ter : symétrique côté révocation (#3876) ────────────────────────────

#[tokio::test]
async fn consent_put_reaffirm_revoked_keeps_revoked_at_stable() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id) = setup_patient(&db).await;

    let make_state = || AppState {
        db: {
            let url = std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
            PgPool::connect_lazy(&url).unwrap()
        },
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let put_revoke = || {
        Request::builder()
            .method("PUT")
            .uri("/v1/account/consents/marketing")
            .header("Content-Type", "application/json")
            .header(
                "Authorization",
                format!("Bearer {}", make_patient_jwt(user_id, account_id)),
            )
            .body(Body::from(r#"{"granted":false}"#))
            .unwrap()
    };

    let r1 = app(make_state()).oneshot(put_revoke()).await.unwrap();
    assert_eq!(r1.status(), StatusCode::OK);

    let revoked_at_1: chrono::DateTime<chrono::Utc> = sqlx::query(
        "SELECT revoked_at FROM consent_record \
         WHERE patient_account_id = $1 AND purpose = 'marketing'",
    )
    .bind(account_id)
    .fetch_one(&db)
    .await
    .unwrap()
    .try_get("revoked_at")
    .unwrap();

    tokio::time::sleep(std::time::Duration::from_millis(50)).await;

    // Ré-affirme le MÊME état (granted:false, déjà révoqué) — no-op logique.
    let r2 = app(make_state()).oneshot(put_revoke()).await.unwrap();
    assert_eq!(r2.status(), StatusCode::OK);

    let revoked_at_2: chrono::DateTime<chrono::Utc> = sqlx::query(
        "SELECT revoked_at FROM consent_record \
         WHERE patient_account_id = $1 AND purpose = 'marketing'",
    )
    .bind(account_id)
    .fetch_one(&db)
    .await
    .unwrap()
    .try_get("revoked_at")
    .unwrap();

    assert_eq!(
        revoked_at_1, revoked_at_2,
        "revoked_at doit rester stable sur une ré-affirmation idempotente"
    );

    cleanup(&db, user_id).await;
}

// ── Test 4 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn consent_put_no_jwt_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/consents/soins")
                .header("Content-Type", "application/json")
                .body(Body::from(r#"{"granted":true}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 5 : token pro → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn consent_put_pro_token_returns_403() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/consents/soins")
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(Uuid::new_v4(), Uuid::new_v4())),
                )
                .body(Body::from(r#"{"granted":true}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 6 : body JSON malformé → 422 ────────────────────────────────────────

#[tokio::test]
async fn consent_put_malformed_body_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id) = setup_patient(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // `granted` doit être un booléen — envoyer une chaîne de caractères → 422
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/consents/soins")
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::from(r#"{"granted":"yes"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, user_id).await;
}

// ── Test 7 : régression #3624 — une ligne CGU plateforme préexistante
// (app_user_id, 'soins') ne doit PAS faire 500 sur PUT /consents/soins. ───────

#[tokio::test]
async fn consent_put_soins_with_existing_platform_cgu_row_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id) = setup_patient(&db).await;

    // Ligne CGU plateforme préexistante pour CET app_user (comme le seed) :
    // app_user_id renseigné, patient_account_id NULL, purpose 'soins'. Avant le
    // fix, l'INSERT du handler liait aussi app_user_id → collision avec la
    // contrainte UNIQUE (app_user_id, purpose) 0027, non gérée par l'ON CONFLICT
    // (patient_account_id, purpose) → 500 permanent.
    sqlx::query(
        "INSERT INTO consent_record (app_user_id, purpose, granted, granted_at) \
         VALUES ($1, 'soins', true, now())",
    )
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/consents/soins")
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::from(r#"{"granted":true}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["purpose"], "soins");
    assert_eq!(v["granted"], true);

    // La ligne consentement patient est créée séparément (scopée patient_account_id).
    let cnt: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM consent_record WHERE patient_account_id = $1 AND purpose = 'soins'",
    )
    .bind(account_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(cnt, 1, "la ligne consentement patient doit exister");

    sqlx::query("DELETE FROM consent_record WHERE app_user_id = $1 OR patient_account_id = $2")
        .bind(user_id)
        .bind(account_id)
        .execute(&db)
        .await
        .ok();
    cleanup(&db, user_id).await;
}
