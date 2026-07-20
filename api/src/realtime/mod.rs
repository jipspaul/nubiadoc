//! WebSocket handshake `GET /v1/ws` — auth JWT + ping/pong keepalive (WS-A) +
//! subscribe/broadcast canal `waiting_room` (WS-B).
#![forbid(unsafe_code)]

pub mod channels;

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Extension, Query, State,
    },
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use jsonwebtoken::{decode, DecodingKey, Validation};
use serde::Deserialize;
use serde_json::json;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::{sync::broadcast, time::timeout};
use uuid::Uuid;

use crate::AppState;

// ── Hub ──────────────────────────────────────────────────────────────────────

/// Hub de broadcast partagé : `cabinet_id` → canal `waiting_room`.
///
/// Injecté via `Extension<Arc<WsHub>>`. Les handlers `confirm_appointment` et
/// `create_appointment` l'utilisent pour notifier les abonnés WS.
pub struct WsHub {
    senders: Mutex<HashMap<Uuid, broadcast::Sender<String>>>,
    /// Canaux nommés (`conversation:<uuid>`, `patient_queue:<uuid>`) — #3238.
    named: Mutex<HashMap<String, broadcast::Sender<String>>>,
}

impl Default for WsHub {
    fn default() -> Self {
        Self::new()
    }
}

impl WsHub {
    pub fn new() -> Self {
        Self {
            senders: Mutex::new(HashMap::new()),
            named: Mutex::new(HashMap::new()),
        }
    }

    /// Retourne un `Receiver` pour le canal `waiting_room` du cabinet donné.
    /// Crée le canal s'il n'existe pas encore.
    pub fn subscribe(&self, cabinet_id: Uuid) -> broadcast::Receiver<String> {
        let mut map = self.senders.lock().unwrap_or_else(|e| e.into_inner());
        let tx = map.entry(cabinet_id).or_insert_with(|| {
            let (tx, _) = broadcast::channel(128);
            tx
        });
        tx.subscribe()
    }

    /// Publie un message vers tous les abonnés du cabinet. No-op s'il n'y en a aucun.
    pub fn publish(&self, cabinet_id: Uuid, msg: String) {
        let map = self.senders.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(tx) = map.get(&cabinet_id) {
            let _ = tx.send(msg);
        }
    }

    /// Retourne un `Receiver` pour un canal nommé (`conversation:<uuid>`,
    /// `patient_queue:<uuid>`). Crée le canal s'il n'existe pas encore.
    pub fn subscribe_named(&self, key: &str) -> broadcast::Receiver<String> {
        let mut map = self.named.lock().unwrap_or_else(|e| e.into_inner());
        let tx = map.entry(key.to_owned()).or_insert_with(|| {
            let (tx, _) = broadcast::channel(128);
            tx
        });
        tx.subscribe()
    }

    /// Publie sur un canal nommé. No-op s'il n'a aucun abonné.
    pub fn publish_named(&self, key: &str, msg: String) {
        let map = self.named.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(tx) = map.get(key) {
            let _ = tx.send(msg);
        }
    }
}

// ── WS handler ───────────────────────────────────────────────────────────────

#[derive(Deserialize)]
pub(crate) struct WsQuery {
    access_token: Option<String>,
}

/// Claims minimaux communs à tous les tokens (patient et pro).
#[derive(Deserialize)]
struct AnyClaims {
    sub: Uuid,
    kind: String,
    #[serde(default)]
    cabinet_id: Option<Uuid>,
    #[serde(default)]
    account_id: Option<Uuid>,
    #[serde(default)]
    pharmacy_id: Option<Uuid>,
    #[serde(default)]
    role: Option<String>,
}

/// Contexte extrait du JWT, porté pour toute la durée de la connexion.
struct WsSession {
    user_id: Uuid,
    kind: String,
    cabinet_id: Option<Uuid>,
    account_id: Option<Uuid>,
    pharmacy_id: Option<Uuid>,
    role: Option<String>,
}

fn resolve_token(query: &WsQuery, headers: &HeaderMap) -> Option<String> {
    if let Some(t) = &query.access_token {
        return Some(t.clone());
    }
    headers
        .get("Authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .map(str::to_owned)
}

fn verify_jwt(token: &str, secret: &str) -> Option<WsSession> {
    let key = DecodingKey::from_secret(secret.as_bytes());
    let mut val = Validation::default();
    val.validate_exp = true;
    decode::<AnyClaims>(token, &key, &val)
        .ok()
        .map(|d| WsSession {
            user_id: d.claims.sub,
            kind: d.claims.kind,
            cabinet_id: d.claims.cabinet_id,
            account_id: d.claims.account_id,
            pharmacy_id: d.claims.pharmacy_id,
            role: d.claims.role,
        })
}

/// `GET /v1/ws` — upgrade WebSocket après vérification JWT.
///
/// Extrait le token de `?access_token=` ou `Authorization: Bearer`. Retourne `401`
/// avant l'upgrade si le token est absent ou invalide.
///
/// Protocole après connexion :
/// - `{"op":"ping"}` → `{"op":"pong","ts":"<iso8601>"}`
/// - `{"op":"subscribe","channel":"waiting_room"}` → abonné si pro (cabinet_id présent),
///   sinon `{"error":"forbidden","channel":"waiting_room"}`
/// - Un socket peut être abonné à plusieurs canaux en parallèle (un bridge de
///   relais par canal, cf. `spawn_bridge`, #3870) — s'abonner à un 2e canal
///   ne coupe plus les précédents.
/// - Tout autre op → `{"error":"unknown_op"}`
/// - Timeout idle 60 s.
pub async fn ws_handshake(
    ws: WebSocketUpgrade,
    Query(query): Query<WsQuery>,
    headers: HeaderMap,
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
) -> Response {
    let token = match resolve_token(&query, &headers) {
        Some(t) => t,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(json!({"code": "unauthenticated"})),
            )
                .into_response()
        }
    };

    let session = match verify_jwt(&token, &state.jwt_secret) {
        Some(s) => s,
        None => {
            return (
                StatusCode::UNAUTHORIZED,
                Json(json!({"code": "unauthorized"})),
            )
                .into_response()
        }
    };

    let db = state.db.clone();
    ws.on_upgrade(move |socket| handle_socket(socket, session, hub, db))
}

async fn handle_socket(
    mut socket: WebSocket,
    session: WsSession,
    hub: Arc<WsHub>,
    db: sqlx::PgPool,
) {
    tracing::debug!(
        user_id = %session.user_id,
        kind = %session.kind,
        cabinet_id = ?session.cabinet_id,
        account_id = ?session.account_id,
        "ws connected"
    );

    // Canal mpsc : les bridge tasks y écrivent les messages broadcast à relayer.
    // Une task PAR canal abonné (#3870) : un socket peut suivre plusieurs
    // canaux simultanément (conversation + patient_queue par ex.) — un unique
    // slot `Option<JoinHandle>` faisait que chaque nouvel abonnement tuait le
    // relais du précédent, le rendant muet malgré l'ACK "subscribed" reçu par
    // le client. Clé = nom du canal : un ré-abonnement au MÊME canal remplace
    // proprement son unique bridge (pas de double-livraison), sans affecter
    // les autres canaux.
    let (bc_tx, mut bc_rx) = tokio::sync::mpsc::channel::<String>(64);
    let mut bc_tasks: HashMap<String, tokio::task::JoinHandle<()>> = HashMap::new();

    const IDLE: Duration = Duration::from_secs(60);

    loop {
        tokio::select! {
            // Messages entrants du client
            client = timeout(IDLE, socket.recv()) => {
                let msg = match client {
                    Ok(Some(Ok(m))) => m,
                    _ => break,
                };
                match msg {
                    Message::Text(text) => {
                        let reply = handle_client_op(
                            text.as_str(),
                            &session,
                            &hub,
                            &db,
                            &bc_tx,
                            &mut bc_tasks,
                        )
                        .await;
                        if socket.send(Message::Text(reply)).await.is_err() {
                            break;
                        }
                    }
                    Message::Close(_) => break,
                    _ => {}
                }
            }

            // Messages broadcast à relayer vers le client
            Some(msg) = bc_rx.recv() => {
                if socket.send(Message::Text(msg)).await.is_err() {
                    break;
                }
            }
        }
    }

    for task in bc_tasks.into_values() {
        task.abort();
    }
}

/// Traite un message texte entrant et retourne la réponse à envoyer.
async fn handle_client_op(
    text: &str,
    session: &WsSession,
    hub: &Arc<WsHub>,
    db: &sqlx::PgPool,
    bc_tx: &tokio::sync::mpsc::Sender<String>,
    bc_tasks: &mut HashMap<String, tokio::task::JoinHandle<()>>,
) -> String {
    let v = match serde_json::from_str::<serde_json::Value>(text) {
        Ok(v) => v,
        Err(_) => return json!({"error": "invalid_json"}).to_string(),
    };

    match v.get("op").and_then(|o| o.as_str()) {
        Some("ping") => json!({
            "op": "pong",
            "ts": chrono::Utc::now().to_rfc3339()
        })
        .to_string(),

        Some("subscribe") => {
            let channel = v.get("channel").and_then(|c| c.as_str()).unwrap_or("");

            // ── waiting_room (historique) : pros du cabinet uniquement ──────
            if channel == "waiting_room" {
                if session.kind != "pro" {
                    return json!({"error": "forbidden", "channel": channel}).to_string();
                }
                let Some(cabinet_id) = session.cabinet_id else {
                    return json!({"error": "forbidden", "channel": channel}).to_string();
                };
                spawn_bridge(
                    bc_tasks,
                    channel,
                    bc_tx,
                    BridgeSource::Cabinet(hub.subscribe(cabinet_id)),
                );
                return json!({"op": "subscribed", "channel": channel}).to_string();
            }

            // ── conversation:<uuid> : patient propriétaire OU pro du cabinet ──
            if let Some(id) = channel.strip_prefix("conversation:") {
                let Ok(conversation_id) = Uuid::parse_str(id) else {
                    return json!({"error": "unknown_channel"}).to_string();
                };
                if !authorize_conversation(db, session, conversation_id).await {
                    return json!({"error": "forbidden", "channel": channel}).to_string();
                }
                spawn_bridge(
                    bc_tasks,
                    channel,
                    bc_tx,
                    BridgeSource::Named(hub.subscribe_named(channel)),
                );
                return json!({"op": "subscribed", "channel": channel}).to_string();
            }

            // ── patient_queue:<uuid> : patient du RDV OU pro du cabinet ──────
            if let Some(id) = channel.strip_prefix("patient_queue:") {
                let Ok(appointment_id) = Uuid::parse_str(id) else {
                    return json!({"error": "unknown_channel"}).to_string();
                };
                if !authorize_patient_queue(db, session, appointment_id).await {
                    return json!({"error": "forbidden", "channel": channel}).to_string();
                }
                spawn_bridge(
                    bc_tasks,
                    channel,
                    bc_tx,
                    BridgeSource::Named(hub.subscribe_named(channel)),
                );
                return json!({"op": "subscribed", "channel": channel}).to_string();
            }

            // ── pharmacy_orders:<uuid> : staff de la pharmacie uniquement ────
            if let Some(id) = channel.strip_prefix("pharmacy_orders:") {
                let Ok(pharmacy_id) = Uuid::parse_str(id) else {
                    return json!({"error": "unknown_channel"}).to_string();
                };
                if session.kind != "pharma" || session.pharmacy_id != Some(pharmacy_id) {
                    return json!({"error": "forbidden", "channel": channel}).to_string();
                }
                spawn_bridge(
                    bc_tasks,
                    channel,
                    bc_tx,
                    BridgeSource::Named(hub.subscribe_named(channel)),
                );
                return json!({"op": "subscribed", "channel": channel}).to_string();
            }

            // ── account_orders:<uuid> : patient titulaire uniquement ─────────
            if let Some(id) = channel.strip_prefix("account_orders:") {
                let Ok(account_id) = Uuid::parse_str(id) else {
                    return json!({"error": "unknown_channel"}).to_string();
                };
                if session.kind != "patient" || session.account_id != Some(account_id) {
                    return json!({"error": "forbidden", "channel": channel}).to_string();
                }
                spawn_bridge(
                    bc_tasks,
                    channel,
                    bc_tx,
                    BridgeSource::Named(hub.subscribe_named(channel)),
                );
                return json!({"op": "subscribed", "channel": channel}).to_string();
            }

            json!({"error": "unknown_channel"}).to_string()
        }

        _ => json!({"error": "unknown_op"}).to_string(),
    }
}

/// Source du bridge broadcast→client (deux hubs : cabinet legacy + nommé).
enum BridgeSource {
    Cabinet(broadcast::Receiver<String>),
    Named(broadcast::Receiver<String>),
}

/// (Re)lance la task qui relaie un Receiver broadcast vers le client WS, pour
/// le canal `channel`. Un socket peut avoir une task par canal abonné (#3870) :
/// seul le bridge du MÊME `channel` est remplacé (ré-abonnement idempotent),
/// les bridges des autres canaux déjà abonnés restent actifs.
fn spawn_bridge(
    bc_tasks: &mut HashMap<String, tokio::task::JoinHandle<()>>,
    channel: &str,
    bc_tx: &tokio::sync::mpsc::Sender<String>,
    source: BridgeSource,
) {
    if let Some(old) = bc_tasks.remove(channel) {
        old.abort();
    }
    let mut receiver = match source {
        BridgeSource::Cabinet(r) | BridgeSource::Named(r) => r,
    };
    let tx_clone = bc_tx.clone();
    let task = tokio::spawn(async move {
        use tokio::sync::broadcast::error::RecvError;
        loop {
            match receiver.recv().await {
                Ok(msg) => {
                    if tx_clone.send(msg).await.is_err() {
                        break;
                    }
                }
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => break,
            }
        }
    });
    bc_tasks.insert(channel.to_owned(), task);
}

/// Le porteur du token peut-il écouter `conversation:<id>` ?
/// Pro : la conversation appartient à son cabinet. Patient : la conversation
/// est la sienne (RLS `conversation_patient_read` via app.patient_account_id).
async fn authorize_conversation(
    db: &sqlx::PgPool,
    session: &WsSession,
    conversation_id: Uuid,
) -> bool {
    let Ok(mut tx) = db.begin().await else {
        return false;
    };
    let ok = match (
        session.kind.as_str(),
        session.cabinet_id,
        session.account_id,
    ) {
        ("pharma", _, _) => {
            let Some(pharmacy_id) = session.pharmacy_id else {
                return false;
            };
            if sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
                .bind(pharmacy_id.to_string())
                .execute(&mut *tx)
                .await
                .is_err()
            {
                return false;
            }
            sqlx::query("SELECT 1 FROM conversation WHERE id = $1 AND pharmacy_id = $2")
                .bind(conversation_id)
                .bind(pharmacy_id)
                .fetch_optional(&mut *tx)
                .await
                .ok()
                .flatten()
                .is_some()
        }
        ("pro", Some(cabinet_id), _) => {
            if sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
                .bind(cabinet_id.to_string())
                .execute(&mut *tx)
                .await
                .is_err()
            {
                return false;
            }
            sqlx::query(
                "SELECT 1 FROM conversation WHERE id = $1 AND cabinet_id = $2 \
                 AND (scope != 'clinical' OR $3 != 'secretary')",
            )
            .bind(conversation_id)
            .bind(cabinet_id)
            .bind(session.role.as_deref().unwrap_or(""))
            .fetch_optional(&mut *tx)
            .await
            .ok()
            .flatten()
            .is_some()
        }
        ("patient", _, Some(account_id)) => {
            if sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
                .bind(account_id.to_string())
                .execute(&mut *tx)
                .await
                .is_err()
            {
                return false;
            }
            sqlx::query("SELECT 1 FROM conversation WHERE id = $1")
                .bind(conversation_id)
                .fetch_optional(&mut *tx)
                .await
                .ok()
                .flatten()
                .is_some()
        }
        _ => false,
    };
    let _ = tx.rollback().await;
    ok
}

/// Le porteur du token peut-il écouter `patient_queue:<appointment_id>` ?
/// Patient : le RDV est le sien (RLS patient sur appointment). Pro : RDV du cabinet.
async fn authorize_patient_queue(
    db: &sqlx::PgPool,
    session: &WsSession,
    appointment_id: Uuid,
) -> bool {
    let Ok(mut tx) = db.begin().await else {
        return false;
    };
    let ok = match (
        session.kind.as_str(),
        session.cabinet_id,
        session.account_id,
    ) {
        ("pro", Some(cabinet_id), _) => {
            if sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
                .bind(cabinet_id.to_string())
                .execute(&mut *tx)
                .await
                .is_err()
            {
                return false;
            }
            sqlx::query("SELECT 1 FROM appointment WHERE id = $1 AND cabinet_id = $2")
                .bind(appointment_id)
                .bind(cabinet_id)
                .fetch_optional(&mut *tx)
                .await
                .ok()
                .flatten()
                .is_some()
        }
        ("patient", _, Some(account_id)) => {
            if sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
                .bind(account_id.to_string())
                .execute(&mut *tx)
                .await
                .is_err()
            {
                return false;
            }
            sqlx::query("SELECT 1 FROM appointment WHERE id = $1")
                .bind(appointment_id)
                .fetch_optional(&mut *tx)
                .await
                .ok()
                .flatten()
                .is_some()
        }
        _ => false,
    };
    let _ = tx.rollback().await;
    ok
}
