//! Tests d'intégration : GET /v1/medication-references (référentiel
//! médicament, #7433)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-medication-references";

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok()
}

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

fn make_pro_token(role: &str) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub: Uuid::new_v4(),
            kind: "pro".into(),
            cabinet_id: Uuid::new_v4(),
            role: role.into(),
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn get(token: Option<&str>, uri: &str) -> (StatusCode, serde_json::Value) {
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let mut builder = Request::builder().method("GET").uri(uri);
    if let Some(t) = token {
        builder = builder.header("authorization", format!("Bearer {t}"));
    }
    let response = app(state)
        .oneshot(builder.body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null),
    )
}

// ── Test 1 : recherche par DCI → produits filtrés ────────────────────────────

#[tokio::test]
async fn search_by_dci_returns_matches() {
    if !db_available() {
        return;
    }
    let token = make_pro_token("practitioner");
    let (status, json) = get(Some(&token), "/v1/medication-references?q=amoxi").await;

    assert_eq!(status, StatusCode::OK);
    let data = json["data"].as_array().expect("data tableau");
    assert!(!data.is_empty(), "au moins une amoxicilline attendue");
    assert!(
        data.iter()
            .all(|m| m["dci"].as_str().unwrap().to_lowercase().contains("amoxi")),
        "tous les résultats doivent matcher la recherche"
    );
    let first = &data[0];
    assert!(first["id"].is_string());
    assert!(first["dci"].is_string());
    assert!(first["galenic_form"].is_string());
    assert!(first["therapeutic_class"].is_string());
}

// ── Test 2 : moins de 2 caractères → liste vide (pas d'erreur) ──────────────

#[tokio::test]
async fn short_query_returns_empty_list() {
    if !db_available() {
        return;
    }
    let token = make_pro_token("practitioner");

    let (status, json) = get(Some(&token), "/v1/medication-references").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["data"].as_array().unwrap().len(), 0);

    let (status, json) = get(Some(&token), "/v1/medication-references?q=a").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["data"].as_array().unwrap().len(), 0);
}

// ── Test 3 : secrétaire → 403, sans token → 401 ──────────────────────────────

#[tokio::test]
async fn secretary_forbidden_and_anonymous_unauthorized() {
    if !db_available() {
        return;
    }
    let (s_status, _) = get(
        Some(&make_pro_token("secretary")),
        "/v1/medication-references?q=amoxi",
    )
    .await;
    assert_eq!(s_status, StatusCode::FORBIDDEN);

    let (a_status, _) = get(None, "/v1/medication-references?q=amoxi").await;
    assert_eq!(a_status, StatusCode::UNAUTHORIZED);
}
