use axum::{extract::State, http::StatusCode, Json};
use serde_json::{json, Value};

use crate::AppState;

pub(crate) async fn health() -> Json<Value> {
    Json(json!({"status": "ok"}))
}

pub(crate) async fn health_live() -> Json<Value> {
    Json(json!({"status": "alive"}))
}

/// Version statique — utilisée par le routeur sans état (tests stateless).
pub(crate) async fn health_ready() -> Json<Value> {
    Json(json!({"status": "ready", "deps": {}}))
}

/// Vérification DB — retourne 200 si `SELECT 1` réussit, 503 sinon.
pub(crate) async fn health_ready_db(State(state): State<AppState>) -> (StatusCode, Json<Value>) {
    if sqlx::query("SELECT 1").execute(&state.db).await.is_ok() {
        (
            StatusCode::OK,
            Json(json!({"status": "ready", "deps": {"db": "ok"}})),
        )
    } else {
        (
            StatusCode::SERVICE_UNAVAILABLE,
            Json(json!({"status": "degraded", "deps": {"db": "error"}})),
        )
    }
}

pub(crate) async fn metrics() -> &'static str {
    "# HELP api_up 1\n# TYPE api_up gauge\napi_up 1\n"
}
