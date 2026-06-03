use axum::{
    routing::{get, post},
    Json, Router,
};
use serde_json::{json, Value};
use sqlx::PgPool;

mod auth;

/// État partagé entre les handlers qui ont besoin de la DB et du secret JWT.
#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub jwt_secret: String,
}

/// Routeur complet avec état (DB + JWT) — utilisé en production et dans les tests d'intégration.
pub fn app(state: AppState) -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/health/live", get(health_live))
        .route("/v1/health/ready", get(health_ready))
        .route("/v1/metrics", get(metrics))
        .route("/v1/auth/mfa/verify", post(auth::mfa_verify))
        .with_state(state)
}

/// Routeur sans état — conservé pour les tests des endpoints statiques existants.
pub fn router() -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/health/live", get(health_live))
        .route("/v1/health/ready", get(health_ready))
        .route("/v1/metrics", get(metrics))
}

async fn health() -> Json<Value> {
    Json(json!({"status": "ok"}))
}

async fn health_live() -> Json<Value> {
    Json(json!({"status": "alive"}))
}

async fn health_ready() -> Json<Value> {
    Json(json!({"status": "ready", "deps": {}}))
}

async fn metrics() -> &'static str {
    "# HELP api_up 1\n# TYPE api_up gauge\napi_up 1\n"
}
