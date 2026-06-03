use axum::{routing::get, Json, Router};
use serde_json::{json, Value};

/// Construit le routeur Axum — séparé de `main` pour les tests d'intégration.
pub fn router() -> Router {
    Router::new().route("/v1/health", get(health))
}

async fn health() -> Json<Value> {
    Json(json!({"status": "ok"}))
}
