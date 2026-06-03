use std::sync::Arc;

use axum::{
    routing::{get, post},
    Json, Router,
};
use serde_json::{json, Value};

pub mod auth;

/// Trait d'envoi d'email — swappable (stub en test, Brevo/SMTP en prod).
pub trait Mailer: Send + Sync {
    /// Envoie le lien de reset. Ne doit jamais bloquer ni paniquer.
    fn send_password_reset(&self, to: &str, token: &str);
}

/// Implémentation no-op pour les tests et le dev local.
pub struct StubMailer;

impl Mailer for StubMailer {
    fn send_password_reset(&self, _to: &str, _token: &str) {}
}

/// État partagé injecté dans les handlers via `State<AppState>`.
#[derive(Clone)]
pub struct AppState {
    /// Pool runtime (rôle nubia_app, RLS active). Jamais le pool owner.
    pub pool: sqlx::PgPool,
    pub mailer: Arc<dyn Mailer>,
}

/// Routeur santé/métriques sans état — utilisé directement dans les tests existants.
pub fn router() -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/health/live", get(health_live))
        .route("/v1/health/ready", get(health_ready))
        .route("/v1/metrics", get(metrics))
}

/// Application complète : santé + auth. Utilisé en production et dans les tests d'intégration auth.
pub fn app(state: AppState) -> Router {
    let auth = Router::new()
        .route("/v1/auth/password/forgot", post(auth::forgot_password))
        .with_state(state);

    router().merge(auth)
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
