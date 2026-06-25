//! Tests d'intégration : GET /v1/ws — handshake WebSocket + JWT auth + ping/pong

use futures_util::{SinkExt, StreamExt};
use jsonwebtoken::{encode, EncodingKey, Header};
use nubia_api::{app, AppState, StubMailer};
use serde::Serialize;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio_tungstenite::tungstenite;
use uuid::Uuid;

const JWT_SECRET: &str = "test-ws-secret";

#[derive(Serialize)]
struct TestPatientClaims {
    sub: Uuid,
    kind: &'static str,
    account_id: Uuid,
    exp: u64,
}

fn make_patient_jwt() -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    let claims = TestPatientClaims {
        sub: Uuid::new_v4(),
        kind: "patient",
        account_id: Uuid::new_v4(),
        exp,
    };
    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_app() -> axum::Router {
    let db = sqlx::PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    };
    app(state)
}

async fn spawn_server() -> std::net::SocketAddr {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, make_app()).await.unwrap();
    });
    addr
}

/// Test 1 : token patient valide → connexion établie + ping/pong rondtrip < 500ms.
#[tokio::test]
async fn ws_valid_patient_token_ping_pong() {
    let addr = spawn_server().await;
    let token = make_patient_jwt();
    let url = format!("ws://{}/v1/ws?access_token={}", addr, token);

    let (mut ws, _) = tokio_tungstenite::connect_async(&url)
        .await
        .expect("connexion ws doit être établie avec un token valide");

    ws.send(tungstenite::Message::Text(r#"{"op":"ping"}"#.to_string()))
        .await
        .unwrap();

    let reply = tokio::time::timeout(Duration::from_millis(500), ws.next())
        .await
        .expect("pong reçu dans les 500ms")
        .unwrap()
        .unwrap();

    let text = match reply {
        tungstenite::Message::Text(t) => t,
        other => panic!("attendu Text, reçu {:?}", other),
    };

    let v: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["op"], "pong", "op doit être pong");
    assert!(v["ts"].is_string(), "ts doit être une string ISO 8601");
}

/// Test 2 : token JWT invalide (mauvaise signature) → rejeté HTTP 401 avant upgrade.
#[tokio::test]
async fn ws_invalid_token_rejected_401() {
    let addr = spawn_server().await;
    let url = format!("ws://{}/v1/ws?access_token=invalid.jwt.token", addr);

    let err = tokio_tungstenite::connect_async(&url)
        .await
        .expect_err("doit être rejeté avec un token invalide");

    match err {
        tungstenite::Error::Http(resp) => {
            assert_eq!(resp.status(), 401, "code HTTP attendu : 401");
        }
        other => panic!("attendu tungstenite::Error::Http, reçu {:?}", other),
    }
}

/// Test 3 : aucun token → rejeté HTTP 401 avant upgrade.
#[tokio::test]
async fn ws_no_token_rejected_401() {
    let addr = spawn_server().await;
    let url = format!("ws://{}/v1/ws", addr);

    let err = tokio_tungstenite::connect_async(&url)
        .await
        .expect_err("doit être rejeté sans token");

    match err {
        tungstenite::Error::Http(resp) => {
            assert_eq!(resp.status(), 401, "code HTTP attendu : 401");
        }
        other => panic!("attendu tungstenite::Error::Http, reçu {:?}", other),
    }
}
