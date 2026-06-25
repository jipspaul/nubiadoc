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
}

/// Contexte extrait du JWT, porté pour toute la durée de la connexion.
struct WsSession {
    user_id: Uuid,
    kind: String,
    cabinet_id: Option<Uuid>,
    account_id: Option<Uuid>,
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

    ws.on_upgrade(move |socket| handle_socket(socket, session, hub))
}

async fn handle_socket(mut socket: WebSocket, session: WsSession, hub: Arc<WsHub>) {
    tracing::debug!(
        user_id = %session.user_id,
        kind = %session.kind,
        cabinet_id = ?session.cabinet_id,
        account_id = ?session.account_id,
        "ws connected"
    );

    // Canal mpsc : le bridge task y écrit les messages broadcast à relayer.
    let (bc_tx, mut bc_rx) = tokio::sync::mpsc::channel::<String>(64);
    let mut bc_task: Option<tokio::task::JoinHandle<()>> = None;

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
                            &bc_tx,
                            &mut bc_task,
                        );
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

    if let Some(task) = bc_task {
        task.abort();
    }
}

/// Traite un message texte entrant et retourne la réponse à envoyer.
fn handle_client_op(
    text: &str,
    session: &WsSession,
    hub: &Arc<WsHub>,
    bc_tx: &tokio::sync::mpsc::Sender<String>,
    bc_task: &mut Option<tokio::task::JoinHandle<()>>,
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
            if channel != "waiting_room" {
                return json!({"error": "unknown_channel"}).to_string();
            }
            if session.kind != "pro" {
                return json!({"error": "forbidden", "channel": "waiting_room"}).to_string();
            }
            let Some(cabinet_id) = session.cabinet_id else {
                return json!({"error": "forbidden", "channel": "waiting_room"}).to_string();
            };

            if let Some(old) = bc_task.take() {
                old.abort();
            }

            let mut receiver = hub.subscribe(cabinet_id);
            let tx_clone = bc_tx.clone();
            *bc_task = Some(tokio::spawn(async move {
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
            }));

            json!({"op": "subscribed", "channel": "waiting_room"}).to_string()
        }

        _ => json!({"error": "unknown_op"}).to_string(),
    }
}
