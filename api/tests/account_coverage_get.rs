//! Tests d'intégration : GET /v1/account/coverage

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

const JWT_SECRET: &str = "test-jwt-secret-coverage-get";

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

// ── Test 1 : aucune ligne coverage → 200 + tiers_payant false ────────────────

#[tokio::test]
async fn coverage_no_row_returns_200_tiers_payant_false() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("coverage-norow+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'Dupont')",
    )
    .bind(account_id)
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
                .method("GET")
                .uri("/v1/account/coverage")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
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
    assert_eq!(v["tiers_payant"], false);
    assert!(v["nss"].is_null(), "nss ne doit jamais apparaître en clair");
    assert!(
        v["nss_encrypted"].is_null(),
        "nss_encrypted ne doit jamais apparaître"
    );

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : ligne avec nss_encrypted → nss_masked présent et masqué ─────────

#[tokio::test]
async fn coverage_with_nss_returns_masked() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("coverage-nss+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Carol', 'Martin')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    // patient_coverage a FORCE RLS (policy TO nubia_app) — on insère via nubia_app
    // avec le GUC app.patient_account_id posé en SET LOCAL (même chemin que le handler).
    // nss_encrypted = UTF-8 plaintext du NSS fictif (KMS non connecté, dev/test uniquement).
    // NIR fictif : 15 chiffres — 2 91 03 75 116 078 05
    {
        let seed_db = app_pool().await;
        let mut tx = seed_db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
            .bind(account_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO patient_coverage \
             (patient_account_id, regime_obligatoire, nss_encrypted, tiers_payant) \
             VALUES ($1, 'regime_general', $2, true)",
        )
        .bind(account_id)
        .bind("291037511607805".as_bytes())
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/coverage")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
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
    assert_eq!(v["tiers_payant"], true);
    assert_eq!(v["regime_obligatoire"], "regime_general");
    assert!(v["nss"].is_null(), "nss ne doit jamais apparaître en clair");
    assert!(
        v["nss_encrypted"].is_null(),
        "nss_encrypted ne doit jamais apparaître"
    );

    // nss_masked doit être présent et respecter le format masqué
    let nss_masked = v["nss_masked"]
        .as_str()
        .expect("nss_masked doit être présent quand nss_encrypted est renseigné");

    // Format attendu : {sexe} {aa} {mm} …{2 derniers chiffres}
    // ex : "2 91 03 …05"
    let parts: Vec<&str> = nss_masked.splitn(4, ' ').collect();
    assert_eq!(
        parts.len(),
        4,
        "nss_masked='{}' doit avoir 4 segments",
        nss_masked
    );
    assert!(
        parts[0].len() == 1 && parts[0].bytes().all(|b| b.is_ascii_digit()),
        "premier segment doit être un chiffre (sexe)"
    );
    assert!(
        parts[1].len() == 2 && parts[1].bytes().all(|b| b.is_ascii_digit()),
        "deuxième segment doit être 2 chiffres (année)"
    );
    assert!(
        parts[2].len() == 2 && parts[2].bytes().all(|b| b.is_ascii_digit()),
        "troisième segment doit être 2 chiffres (mois)"
    );
    assert!(
        parts[3].starts_with('…'),
        "quatrième segment doit commencer par '…'"
    );

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn coverage_no_jwt_returns_401() {
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
                .method("GET")
                .uri("/v1/account/coverage")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 4 : token pro → 403 ─────────────────────────────────────────────────

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id,
                "role": "admin", "account_id": Uuid::nil(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

#[tokio::test]
async fn coverage_pro_token_returns_403() {
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
                .method("GET")
                .uri("/v1/account/coverage")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(Uuid::new_v4(), Uuid::new_v4())),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}
