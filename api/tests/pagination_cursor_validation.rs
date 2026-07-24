//! Test d'intégration ciblé : un curseur de pagination malformé doit
//! renvoyer `422 validation_error`, pas silencieusement redémarrer à la
//! page 1 (#4367, régression de la famille #3874/notifications.rs).
//!
//! Couvre les 3 sites qui utilisaient encore `.and_then(decode_cursor)`
//! (conflate "absent" et "malformé" en `None`) : `GET /v1/conversations`,
//! `GET /v1/conversations/:id/messages`, `GET /v1/documents`.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-cursor-validation";

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

async fn app_pool() -> sqlx::PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    sqlx::PgPool::connect(&url).await.unwrap()
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

async fn get(uri: &str, token: &str) -> StatusCode {
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(uri)
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    response.status()
}

#[tokio::test]
async fn list_conversations_malformed_cursor_returns_422() {
    if !db_available() {
        return;
    }
    let token = make_patient_jwt(Uuid::new_v4(), Uuid::new_v4());
    let status = get("/v1/conversations?cursor=not-a-valid-cursor", &token).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn get_conversation_messages_malformed_cursor_returns_422() {
    if !db_available() {
        return;
    }
    let token = make_patient_jwt(Uuid::new_v4(), Uuid::new_v4());
    let uri = format!(
        "/v1/conversations/{}/messages?cursor=not-a-valid-cursor",
        Uuid::new_v4()
    );
    let status = get(&uri, &token).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[tokio::test]
async fn list_documents_malformed_cursor_returns_422() {
    if !db_available() {
        return;
    }
    let token = make_patient_jwt(Uuid::new_v4(), Uuid::new_v4());
    let status = get("/v1/documents?cursor=not-a-valid-cursor", &token).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}
