//! Tests d'intégration : canal `waiting_room` WebSocket (WS-B.b + WS-B.c).
//!
//! 4 tests :
//! 1. Subscribe OK — pro (cabinet_id présent) reçoit `subscribed`.
//! 2. Subscribe refus — patient (pas de cabinet_id) reçoit `forbidden`.
//! 3. Broadcast — publish hub → WS client reçoit l'enveloppe en < 2 s.
//! 4. Isolation — publish sur cabinet B → abonné cabinet A ne reçoit rien.

use futures_util::{SinkExt, StreamExt};
use jsonwebtoken::{encode, EncodingKey, Header};
use nubia_api::{app_with_hub, AppState, StubMailer, WsHub};
use serde_json::json;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio_tungstenite::tungstenite;
use uuid::Uuid;

const JWT_SECRET: &str = "test-ws-wr-secret";

fn exp_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900
}

fn make_pro_token(cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": Uuid::new_v4(),
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": "practitioner",
            "exp": exp_secs()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_patient_token() -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": Uuid::new_v4(),
            "kind": "patient",
            "account_id": Uuid::new_v4(),
            "exp": exp_secs()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_app(hub: Arc<WsHub>) -> axum::Router {
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
    app_with_hub(state, hub)
}

async fn spawn_server(hub: Arc<WsHub>) -> std::net::SocketAddr {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, make_app(hub)).await.unwrap();
    });
    addr
}

// ── Test 1 : Subscribe OK ────────────────────────────────────────────────────

/// Un pro (avec cabinet_id dans son JWT) peut s'abonner à `waiting_room`.
#[tokio::test]
async fn ws_waiting_room_subscribe_ok() {
    let cabinet_id = Uuid::new_v4();
    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub).await;

    let token = make_pro_token(cabinet_id);
    let url = format!("ws://{}/v1/ws?access_token={}", addr, token);
    let (mut ws, _) = tokio_tungstenite::connect_async(&url)
        .await
        .expect("connexion WS avec token pro valide");

    ws.send(tungstenite::Message::Text(
        r#"{"op":"subscribe","channel":"waiting_room"}"#.to_string(),
    ))
    .await
    .unwrap();

    let reply = tokio::time::timeout(Duration::from_millis(500), ws.next())
        .await
        .expect("réponse reçue dans les 500 ms")
        .unwrap()
        .unwrap();

    let text = match reply {
        tungstenite::Message::Text(t) => t,
        other => panic!("attendu Text, reçu {:?}", other),
    };

    let v: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["op"], "subscribed", "op doit être subscribed");
    assert_eq!(
        v["channel"], "waiting_room",
        "channel doit être waiting_room"
    );
}

// ── Test 2 : Subscribe refus ─────────────────────────────────────────────────

/// Un patient (sans cabinet_id dans son JWT) ne peut pas s'abonner à `waiting_room`.
#[tokio::test]
async fn ws_waiting_room_subscribe_refused_patient() {
    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub).await;

    let token = make_patient_token();
    let url = format!("ws://{}/v1/ws?access_token={}", addr, token);
    let (mut ws, _) = tokio_tungstenite::connect_async(&url)
        .await
        .expect("connexion WS avec token patient valide");

    ws.send(tungstenite::Message::Text(
        r#"{"op":"subscribe","channel":"waiting_room"}"#.to_string(),
    ))
    .await
    .unwrap();

    let reply = tokio::time::timeout(Duration::from_millis(500), ws.next())
        .await
        .expect("réponse reçue dans les 500 ms")
        .unwrap()
        .unwrap();

    let text = match reply {
        tungstenite::Message::Text(t) => t,
        other => panic!("attendu Text, reçu {:?}", other),
    };

    let v: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(
        v["error"], "forbidden",
        "error doit être forbidden pour un patient"
    );
    assert_eq!(v["channel"], "waiting_room");
}

// ── Test 3 : Broadcast ───────────────────────────────────────────────────────

/// Un pro abonné reçoit le message broadcast publié par le hub en < 2 s.
#[tokio::test]
async fn ws_waiting_room_broadcast_delivered() {
    let cabinet_id = Uuid::new_v4();
    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub.clone()).await;

    let token = make_pro_token(cabinet_id);
    let url = format!("ws://{}/v1/ws?access_token={}", addr, token);
    let (mut ws, _) = tokio_tungstenite::connect_async(&url)
        .await
        .expect("connexion WS pro");

    ws.send(tungstenite::Message::Text(
        r#"{"op":"subscribe","channel":"waiting_room"}"#.to_string(),
    ))
    .await
    .unwrap();

    // Attend la confirmation d'abonnement
    let _sub_reply = tokio::time::timeout(Duration::from_millis(500), ws.next())
        .await
        .expect("subscribed reçu")
        .unwrap()
        .unwrap();

    // Simule la publication (ce que font confirm_appointment / create_appointment)
    let appt_id = Uuid::new_v4();
    let envelope = json!({
        "channel": "waiting_room",
        "event": "queue_updated",
        "data": { "appointment_id": appt_id, "status": "confirmed" }
    })
    .to_string();
    hub.publish(cabinet_id, envelope);

    // Le WS client doit recevoir l'enveloppe en moins de 2 s
    let msg = tokio::time::timeout(Duration::from_secs(2), ws.next())
        .await
        .expect("enveloppe reçue en < 2 s")
        .unwrap()
        .unwrap();

    let text = match msg {
        tungstenite::Message::Text(t) => t,
        other => panic!("attendu Text, reçu {:?}", other),
    };

    let v: serde_json::Value = serde_json::from_str(&text).unwrap();
    assert_eq!(v["channel"], "waiting_room");
    assert_eq!(v["event"], "queue_updated");
    assert_eq!(v["data"]["appointment_id"], appt_id.to_string());
    assert_eq!(v["data"]["status"], "confirmed");
}

// ── Test 4 : Isolation cabinet ───────────────────────────────────────────────

/// Un pro abonné au cabinet A ne doit pas recevoir les broadcasts du cabinet B.
#[tokio::test]
async fn ws_waiting_room_isolation_cabinet() {
    let cabinet_a = Uuid::new_v4();
    let cabinet_b = Uuid::new_v4();
    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub.clone()).await;

    // Connecte et abonne le pro A (cabinet A)
    let token_a = make_pro_token(cabinet_a);
    let url_a = format!("ws://{}/v1/ws?access_token={}", addr, token_a);
    let (mut ws_a, _) = tokio_tungstenite::connect_async(&url_a)
        .await
        .expect("connexion WS pro A");

    ws_a.send(tungstenite::Message::Text(
        r#"{"op":"subscribe","channel":"waiting_room"}"#.to_string(),
    ))
    .await
    .unwrap();

    // Attend la confirmation
    let _sub = tokio::time::timeout(Duration::from_millis(500), ws_a.next())
        .await
        .expect("subscribed reçu pour A")
        .unwrap()
        .unwrap();

    // Publie sur le cabinet B (pas A)
    hub.publish(
        cabinet_b,
        json!({
            "channel": "waiting_room",
            "event": "queue_updated",
            "data": { "appointment_id": Uuid::new_v4(), "status": "confirmed" }
        })
        .to_string(),
    );

    // Le pro A ne doit rien recevoir dans les 400 ms
    let nothing = tokio::time::timeout(Duration::from_millis(400), ws_a.next()).await;
    assert!(
        nothing.is_err(),
        "pro A ne doit pas recevoir de broadcast du cabinet B"
    );
}
