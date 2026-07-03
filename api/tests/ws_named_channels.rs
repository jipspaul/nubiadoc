//! Tests d'intégration : canaux WS nommés `conversation:<id>` et
//! `patient_queue:<id>` (#3238) — autorisation DB + broadcast.

use futures_util::{SinkExt, StreamExt};
use jsonwebtoken::{encode, EncodingKey, Header};
use nubia_api::{app_with_hub, AppState, StubMailer, WsHub};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio_tungstenite::tungstenite;
use uuid::Uuid;

const JWT_SECRET: &str = "test-ws-named-secret";

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

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

fn make_patient_token(account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": Uuid::new_v4(),
            "kind": "patient",
            "account_id": account_id,
            "exp": exp_secs()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn owner_pool() -> PgPool {
    let url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_owner@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

async fn spawn_server(hub: Arc<WsHub>) -> std::net::SocketAddr {
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
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app_with_hub(state, hub))
            .await
            .unwrap();
    });
    addr
}

/// Fixture : cabinet + compte patient + patient + conversation.
/// Retourne `(cabinet_id, account_user_id, account_id, patient_id, conversation_id)`.
async fn insert_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let account_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(account_user_id)
    .bind(format!("ws-named+{}@nubia.test", account_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet WS Named', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Ws', 'Named')",
    )
    .bind(account_id)
    .bind(account_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name) \
         VALUES ($1, $2, $3, 'Ws', 'Named')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO conversation (id, cabinet_id, patient_id) VALUES ($1, $2, $3)")
        .bind(conversation_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    tx.commit().await.unwrap();
    (
        cabinet_id,
        account_user_id,
        account_id,
        patient_id,
        conversation_id,
    )
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    account_user_id: Uuid,
    account_id: Uuid,
    patient_id: Uuid,
    conversation_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM message WHERE conversation_id = $1")
        .bind(conversation_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM conversation WHERE id = $1")
        .bind(conversation_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(account_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

async fn subscribe(
    addr: std::net::SocketAddr,
    token: &str,
    channel: &str,
) -> (
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>,
    serde_json::Value,
) {
    let url = format!("ws://{}/v1/ws?access_token={}", addr, token);
    let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    ws.send(tungstenite::Message::Text(
        json!({"op": "subscribe", "channel": channel}).to_string(),
    ))
    .await
    .unwrap();
    let reply = tokio::time::timeout(Duration::from_secs(2), ws.next())
        .await
        .expect("réponse subscribe dans les 2 s")
        .unwrap()
        .unwrap();
    let text = match reply {
        tungstenite::Message::Text(t) => t,
        other => panic!("attendu Text, reçu {:?}", other),
    };
    (ws, serde_json::from_str(&text).unwrap())
}

// ── Test 1 : patient propriétaire → subscribed + reçoit message_created ──────

#[tokio::test]
async fn conversation_owner_subscribes_and_receives() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, account_user_id, account_id, patient_id, conversation_id) =
        insert_fixture(&owner).await;

    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub.clone()).await;
    let channel = format!("conversation:{conversation_id}");

    let (mut ws, reply) = subscribe(addr, &make_patient_token(account_id), &channel).await;
    assert_eq!(reply["op"], "subscribed", "reply: {reply}");
    assert_eq!(reply["channel"], channel);

    hub.publish_named(
        &channel,
        json!({"channel": channel, "event": "message_created", "data": {}}).to_string(),
    );

    let msg = tokio::time::timeout(Duration::from_secs(2), ws.next())
        .await
        .expect("event broadcast reçu en < 2 s")
        .unwrap()
        .unwrap();
    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["event"], "message_created");

    cleanup_fixture(
        &owner,
        cabinet_id,
        account_user_id,
        account_id,
        patient_id,
        conversation_id,
    )
    .await;
}

// ── Test 2 : patient étranger → forbidden ─────────────────────────────────────

#[tokio::test]
async fn conversation_foreign_patient_forbidden() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, account_user_id, account_id, patient_id, conversation_id) =
        insert_fixture(&owner).await;

    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub).await;
    let channel = format!("conversation:{conversation_id}");

    // Compte patient qui ne possède PAS la conversation.
    let (_ws, reply) = subscribe(addr, &make_patient_token(Uuid::new_v4()), &channel).await;
    assert_eq!(reply["error"], "forbidden", "reply: {reply}");

    cleanup_fixture(
        &owner,
        cabinet_id,
        account_user_id,
        account_id,
        patient_id,
        conversation_id,
    )
    .await;
}

// ── Test 3 : pro du cabinet → subscribed ; pro d'un autre cabinet → forbidden ─

#[tokio::test]
async fn conversation_pro_cabinet_scoping() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, account_user_id, account_id, patient_id, conversation_id) =
        insert_fixture(&owner).await;

    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub).await;
    let channel = format!("conversation:{conversation_id}");

    let (_ws_ok, reply_ok) = subscribe(addr, &make_pro_token(cabinet_id), &channel).await;
    assert_eq!(reply_ok["op"], "subscribed", "pro même cabinet: {reply_ok}");

    let (_ws_ko, reply_ko) = subscribe(addr, &make_pro_token(Uuid::new_v4()), &channel).await;
    assert_eq!(
        reply_ko["error"], "forbidden",
        "pro autre cabinet: {reply_ko}"
    );

    cleanup_fixture(
        &owner,
        cabinet_id,
        account_user_id,
        account_id,
        patient_id,
        conversation_id,
    )
    .await;
}

// ── Test 4 : canal inconnu → unknown_channel ──────────────────────────────────

#[tokio::test]
async fn unknown_channel_rejected() {
    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub).await;

    let (_ws, reply) = subscribe(addr, &make_patient_token(Uuid::new_v4()), "autre_chose").await;
    assert_eq!(reply["error"], "unknown_channel");
}
