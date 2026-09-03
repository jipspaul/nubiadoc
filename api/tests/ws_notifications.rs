//! Tests d'intégration : canal WS `notifications` — abonnement au canal
//! PERSONNEL (clé dérivée du JWT, jamais d'un paramètre client) + réception
//! des enveloppes publiées, et isolation entre utilisateurs.

use futures_util::{SinkExt, StreamExt};
use jsonwebtoken::{encode, EncodingKey, Header};
use nubia_api::{app_with_hub, user_notifications_key, AppState, StubMailer, WsHub};
use serde::Serialize;
use serde_json::json;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio_tungstenite::tungstenite;
use uuid::Uuid;

const JWT_SECRET: &str = "test-ws-notifications-secret";

#[derive(Serialize)]
struct TestClaims {
    sub: Uuid,
    kind: &'static str,
    exp: u64,
}

fn make_jwt(sub: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &TestClaims {
            sub,
            kind: "pro",
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn spawn_server(hub: Arc<WsHub>) -> std::net::SocketAddr {
    // connect_lazy : aucun accès DB nécessaire pour ce canal (authz = JWT seul).
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
    let app = app_with_hub(state, hub);
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });
    addr
}

async fn connect_and_subscribe(
    addr: std::net::SocketAddr,
    user_id: Uuid,
) -> tokio_tungstenite::WebSocketStream<
    tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
> {
    let url = format!("ws://{}/v1/ws?access_token={}", addr, make_jwt(user_id));
    let (mut ws, _) = tokio_tungstenite::connect_async(&url).await.unwrap();
    ws.send(tungstenite::Message::Text(
        r#"{"op":"subscribe","channel":"notifications"}"#.to_string(),
    ))
    .await
    .unwrap();
    let ack = tokio::time::timeout(Duration::from_millis(500), ws.next())
        .await
        .expect("ack attendu")
        .unwrap()
        .unwrap();
    let ack: serde_json::Value = serde_json::from_str(ack.to_text().unwrap()).unwrap();
    assert_eq!(ack["op"], "subscribed");
    assert_eq!(ack["channel"], "notifications");
    ws
}

/// L'abonné reçoit l'enveloppe publiée sur SON canal personnel.
#[tokio::test]
async fn notifications_subscriber_receives_own_events() {
    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub.clone()).await;
    let user_id = Uuid::new_v4();
    let mut ws = connect_and_subscribe(addr, user_id).await;

    hub.publish_named(
        &user_notifications_key(user_id),
        json!({
            "channel": "notifications",
            "event": "notification_created",
            "data": {"id": Uuid::new_v4(), "kind": "message_received", "title": "Nouveau message reçu"}
        })
        .to_string(),
    );

    let msg = tokio::time::timeout(Duration::from_millis(500), ws.next())
        .await
        .expect("événement attendu")
        .unwrap()
        .unwrap();
    let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
    assert_eq!(v["channel"], "notifications");
    assert_eq!(v["event"], "notification_created");
    assert_eq!(v["data"]["kind"], "message_received");
}

/// Isolation : une publication destinée à un AUTRE utilisateur n'arrive jamais.
#[tokio::test]
async fn notifications_other_user_events_not_delivered() {
    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub.clone()).await;
    let mut ws = connect_and_subscribe(addr, Uuid::new_v4()).await;

    hub.publish_named(
        &user_notifications_key(Uuid::new_v4()),
        json!({"channel": "notifications", "event": "notification_created", "data": {}})
            .to_string(),
    );

    let silence = tokio::time::timeout(Duration::from_millis(300), ws.next()).await;
    assert!(silence.is_err(), "aucun message ne doit traverser les canaux d'autrui");
}
