//! Routes santé/metrics/websocket. Extrait de `lib.rs::build_router` (refactor taille).

use axum::{routing::get, Router};

use crate::{health, realtime, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route("/v1/health", get(health::health))
        .route("/v1/health/live", get(health::health_live))
        .route("/v1/health/ready", get(health::health_ready_db))
        .route("/v1/health/db", get(health::health_db))
        .route("/v1/metrics", get(health::metrics))
        .route("/v1/ws", get(realtime::ws_handshake))
}
