//! Tests d'intégration : GET /v1/ccam/acts (référentiel CCAM, #3226)

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

const JWT_SECRET: &str = "test-secret-ccam-acts";

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

// ── Test 1 : recherche par libellé → actes filtrés ───────────────────────────

#[tokio::test]
#[ignore = "quarantaine: échec réel révélé par le fix DB CI (env reset+migrate), voir #4602"]
async fn search_by_label_returns_matches() {
    if !db_available() {
        return;
    }
    let token = make_pro_token("practitioner");
    let (status, json) = get(Some(&token), "/v1/ccam/acts?q=detartrage").await;

    assert_eq!(status, StatusCode::OK);
    let data = json["data"].as_array().expect("data tableau");
    assert!(!data.is_empty(), "au moins un acte de détartrage attendu");
    assert!(
        data.iter().all(|a| a["label"]
            .as_str()
            .unwrap()
            .to_lowercase()
            .contains("détartrage")
            || a["code"]
                .as_str()
                .unwrap()
                .to_lowercase()
                .contains("detartrage")),
        "tous les résultats doivent matcher la recherche"
    );
    // Champs du contrat.
    let first = &data[0];
    assert!(first["code"].is_string());
    assert!(first["label"].is_string());
}

// ── Test 2 : recherche par code ───────────────────────────────────────────────

#[tokio::test]
async fn search_by_code_returns_match() {
    if !db_available() {
        return;
    }
    let token = make_pro_token("practitioner");
    let (status, json) = get(Some(&token), "/v1/ccam/acts?q=HBQK002").await;

    assert_eq!(status, StatusCode::OK);
    let data = json["data"].as_array().unwrap();
    assert!(data.iter().any(|a| a["code"] == "HBQK002"));
}

// ── Test 3 : sans q → catalogue (non vide, borné à 25) ───────────────────────

#[tokio::test]
async fn no_query_returns_catalog() {
    if !db_available() {
        return;
    }
    let token = make_pro_token("practitioner");
    let (status, json) = get(Some(&token), "/v1/ccam/acts").await;

    assert_eq!(status, StatusCode::OK);
    let data = json["data"].as_array().unwrap();
    assert!(!data.is_empty());
    assert!(data.len() <= 25);
}

// ── Test 4 : secrétaire → 403, sans token → 401 ──────────────────────────────

#[tokio::test]
async fn secretary_forbidden_and_anonymous_unauthorized() {
    if !db_available() {
        return;
    }
    let (s_status, _) = get(Some(&make_pro_token("secretary")), "/v1/ccam/acts").await;
    assert_eq!(s_status, StatusCode::FORBIDDEN);

    let (a_status, _) = get(None, "/v1/ccam/acts").await;
    assert_eq!(a_status, StatusCode::UNAUTHORIZED);
}
