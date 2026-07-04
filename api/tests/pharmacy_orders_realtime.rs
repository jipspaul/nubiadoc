//! Tests d'intégration : temps réel + notifications commandes pharmacie
//! (lot B4, issue #3309) — canaux `pharmacy_orders:<id>` / `account_orders:<id>`,
//! événements de transition, notifications in-app sans PII.

use futures_util::{SinkExt, StreamExt};
use jsonwebtoken::{encode, EncodingKey, Header};
use nubia_api::{app_with_hub, AppState, StubMailer, WsHub};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio_tungstenite::tungstenite;
use uuid::Uuid;

const JWT_SECRET: &str = "test-ws-pharmacy-orders-secret";

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

fn pharma_token(pharmacy_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "pharma", "pharmacy_id": pharmacy_id,
                "role": "pharmacist", "exp": exp_secs()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn patient_token(account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "patient", "account_id": account_id,
                "exp": exp_secs()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn pro_token(cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "pro", "cabinet_id": cabinet_id,
                "role": "practitioner", "exp": exp_secs()}),
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

struct Fixture {
    account_id: Uuid,
    patient_user_id: Uuid,
    pharmacy_id: Uuid,
    pharmacist_user_id: Uuid,
    order_id: Uuid,
}

/// Fixture : commande `received` + un membre actif de la pharmacie.
async fn seed(db: &PgPool) -> Fixture {
    let patient_user_id = Uuid::new_v4();
    let pro_user_id = Uuid::new_v4();
    let pharmacist_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let document_id = Uuid::new_v4();
    let prescription_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();
    let order_id = Uuid::new_v4();

    for (id, kind) in [
        (patient_user_id, "patient"),
        (pro_user_id, "pro"),
        (pharmacist_user_id, "pro"),
    ] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(id)
        .bind(format!("rt-{}@nubia.test", id))
        .bind(kind)
        .execute(db)
        .await
        .unwrap();
    }
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Jean', 'Demo')",
    )
    .bind(account_id)
    .bind(patient_user_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet RT')")
        .bind(cabinet_id)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Jean', 'Demo', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(pro_user_id)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, \
                               mime_type, sha256, scan_status, uploaded_by, size_bytes) \
         VALUES ($1, $2, $3, 'ordonnance', $4, 'ordo.pdf', 'application/pdf', \
                 repeat('0', 64), 'clean', $5, 0)",
    )
    .bind(document_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(format!("sk-{}", document_id))
    .bind(pro_user_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, \
                                   document_id, signed_at) \
         VALUES ($1, $2, $3, $4, 'sent', $5, now())",
    )
    .bind(prescription_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(document_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Pharmacie RT', true)",
    )
    .bind(pharmacy_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO pharmacy_membership (pharmacy_id, user_id, role, active) \
         VALUES ($1, $2, 'pharmacist', true)",
    )
    .bind(pharmacy_id)
    .bind(pharmacist_user_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO pharmacy_order (id, pharmacy_id, cabinet_id, patient_account_id, \
                                     prescription_id, document_id, created_by_kind, \
                                     pharmacy_name, patient_display_name) \
         VALUES ($1, $2, $3, $4, $5, $6, 'patient', 'Pharmacie RT', 'Jean D.')",
    )
    .bind(order_id)
    .bind(pharmacy_id)
    .bind(cabinet_id)
    .bind(account_id)
    .bind(prescription_id)
    .bind(document_id)
    .execute(db)
    .await
    .unwrap();

    Fixture {
        account_id,
        patient_user_id,
        pharmacy_id,
        pharmacist_user_id,
        order_id,
    }
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

// ── Autorisations de subscribe ────────────────────────────────────────────────

#[tokio::test]
async fn subscribe_authorization_matrix() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub.clone()).await;

    // Staff de la pharmacie → subscribed.
    let channel = format!("pharmacy_orders:{}", fx.pharmacy_id);
    let (_ws, reply) = subscribe(addr, &pharma_token(fx.pharmacy_id), &channel).await;
    assert_eq!(reply["op"], "subscribed", "reply: {reply}");

    // Autre pharmacie → forbidden.
    let (_ws, reply) = subscribe(addr, &pharma_token(Uuid::new_v4()), &channel).await;
    assert_eq!(reply["error"], "forbidden");

    // Token pro → forbidden (cloisonnement).
    let (_ws, reply) = subscribe(addr, &pro_token(Uuid::new_v4()), &channel).await;
    assert_eq!(reply["error"], "forbidden");

    // Patient titulaire → subscribed sur son canal de commandes.
    let account_channel = format!("account_orders:{}", fx.account_id);
    let (_ws, reply) = subscribe(addr, &patient_token(fx.account_id), &account_channel).await;
    assert_eq!(reply["op"], "subscribed");

    // Autre patient → forbidden.
    let (_ws, reply) = subscribe(addr, &patient_token(Uuid::new_v4()), &account_channel).await;
    assert_eq!(reply["error"], "forbidden");
}

// ── Transition → événement WS + notification in-app ──────────────────────────

#[tokio::test]
async fn accept_transition_broadcasts_and_notifies() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub.clone()).await;

    // Les deux bords s'abonnent.
    let pharmacy_channel = format!("pharmacy_orders:{}", fx.pharmacy_id);
    let account_channel = format!("account_orders:{}", fx.account_id);
    let (mut ws_pharma, reply) =
        subscribe(addr, &pharma_token(fx.pharmacy_id), &pharmacy_channel).await;
    assert_eq!(reply["op"], "subscribed");
    let (mut ws_patient, reply) =
        subscribe(addr, &patient_token(fx.account_id), &account_channel).await;
    assert_eq!(reply["op"], "subscribed");

    // Le pharmacien accepte la commande via l'API HTTP du même serveur.
    let client = reqwest::Client::new();
    let response = client
        .post(format!(
            "http://{}/v1/pharmacy/orders/{}/accept",
            addr, fx.order_id
        ))
        .header(
            "Authorization",
            format!("Bearer {}", pharma_token(fx.pharmacy_id)),
        )
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 200);

    // Événement reçu sur les deux canaux — enveloppe zéro PII.
    for ws in [&mut ws_pharma, &mut ws_patient] {
        let msg = tokio::time::timeout(Duration::from_secs(2), ws.next())
            .await
            .expect("événement en < 2 s")
            .unwrap()
            .unwrap();
        let v: serde_json::Value = serde_json::from_str(msg.to_text().unwrap()).unwrap();
        assert_eq!(v["event"], "order_status_changed");
        assert_eq!(v["data"]["order_id"], json!(fx.order_id));
        assert_eq!(v["data"]["status"], "preparing");
        assert!(
            v["data"].get("patient_display_name").is_none(),
            "zéro PII dans l'enveloppe WS"
        );
    }

    // Notification in-app créée pour le patient (titre générique sans PII).
    let notif = sqlx::query(
        "SELECT title, data FROM notification \
         WHERE app_user_id = $1 AND kind = 'order_status_changed' \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(fx.patient_user_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let title: String = notif.try_get("title").unwrap();
    let data: serde_json::Value = notif.try_get("data").unwrap();
    assert_eq!(title, "Votre commande a été mise à jour");
    assert_eq!(data["status"], "preparing");
}

// ── Création → notification du staff pharmacie ────────────────────────────────

#[tokio::test]
async fn patient_cancel_notifies_pharmacy_staff() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let hub = Arc::new(WsHub::new());
    let addr = spawn_server(hub.clone()).await;

    let client = reqwest::Client::new();
    let response = client
        .post(format!(
            "http://{}/v1/account/orders/{}/cancel",
            addr, fx.order_id
        ))
        .header(
            "Authorization",
            format!(
                "Bearer {}",
                patient_token_for(fx.patient_user_id, fx.account_id)
            ),
        )
        .send()
        .await
        .unwrap();
    assert_eq!(response.status(), 200);

    let count: i64 = sqlx::query(
        "SELECT count(*) AS n FROM notification \
         WHERE app_user_id = $1 AND kind = 'order_status_changed'",
    )
    .bind(fx.pharmacist_user_id)
    .fetch_one(&db)
    .await
    .unwrap()
    .try_get("n")
    .unwrap();
    assert_eq!(count, 1, "le staff pharmacie est notifié de l'annulation");
}

fn patient_token_for(user_id: Uuid, account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id,
                "exp": exp_secs()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}
