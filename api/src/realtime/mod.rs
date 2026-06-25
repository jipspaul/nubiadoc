//! WebSocket handshake `GET /v1/ws` — auth JWT + ping/pong keepalive (WS-A).
#![forbid(unsafe_code)]

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Query, State,
    },
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use jsonwebtoken::{decode, DecodingKey, Validation};
use serde::Deserialize;
use serde_json::json;
use std::time::Duration;
use tokio::time::timeout;
use uuid::Uuid;

use crate::AppState;

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
/// avant l'upgrade si le token est absent ou invalide. Boucle d'événements :
/// `{"op":"ping"}` → `{"op":"pong","ts":"<iso8601>"}` ; tout autre op →
/// `{"error":"unknown_op"}`. Timeout idle 60 s.
pub async fn ws_handshake(
    ws: WebSocketUpgrade,
    Query(query): Query<WsQuery>,
    headers: HeaderMap,
    State(state): State<AppState>,
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

    ws.on_upgrade(move |socket| handle_socket(socket, session))
}

async fn handle_socket(mut socket: WebSocket, session: WsSession) {
    tracing::debug!(
        user_id = %session.user_id,
        kind = %session.kind,
        cabinet_id = ?session.cabinet_id,
        account_id = ?session.account_id,
        "ws connected"
    );

    const IDLE: Duration = Duration::from_secs(60);

    loop {
        let msg = match timeout(IDLE, socket.recv()).await {
            Ok(Some(Ok(m))) => m,
            _ => break,
        };

        match msg {
            Message::Text(text) => {
                let reply =
                    match serde_json::from_str::<serde_json::Value>(text.as_str()) {
                        Ok(v)
                            if v.get("op").and_then(|o| o.as_str()) == Some("ping") =>
                        {
                            json!({
                                "op": "pong",
                                "ts": chrono::Utc::now().to_rfc3339()
                            })
                            .to_string()
                        }
                        _ => json!({"error": "unknown_op"}).to_string(),
                    };
                if socket.send(Message::Text(reply)).await.is_err() {
                    break;
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
    }
}
