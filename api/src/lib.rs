use std::sync::Arc;

use axum::{
    routing::{get, patch, post, put},
    Extension, Json, Router,
};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

mod appointments;
mod auth;
mod dashboard;

/// Trait d'envoi d'email — swappable (stub en test, Brevo/SMTP en prod).
pub trait Mailer: Send + Sync {
    /// Envoie le lien de reset. Ne doit jamais bloquer ni paniquer.
    fn send_password_reset(&self, to: &str, token: &str);
    /// Envoie le lien d'invitation (set-password) à un nouveau collaborateur.
    fn send_invite(&self, to: &str, token: &str);
}

/// Implémentation no-op pour les tests et le dev local.
pub struct StubMailer;

impl Mailer for StubMailer {
    fn send_password_reset(&self, _to: &str, _token: &str) {}
    fn send_invite(&self, _to: &str, _token: &str) {}
}

/// Trait d'enqueue de jobs apalis — swappable (stub en test, apalis en prod).
pub trait JobDispatcher: Send + Sync {
    /// Enfile un job de vérification ANS. Fire-and-forget : ne bloque pas.
    fn enqueue_verify_provider(&self, verification_id: Uuid);
}

/// Implémentation no-op pour les tests et le dev local.
pub struct StubJobDispatcher;

impl JobDispatcher for StubJobDispatcher {
    fn enqueue_verify_provider(&self, _verification_id: Uuid) {}
}

/// État partagé injecté dans les handlers via `State<AppState>`.
#[derive(Clone)]
pub struct AppState {
    /// Pool runtime (rôle nubia_app, RLS active). Jamais le pool owner.
    pub db: PgPool,
    pub jwt_secret: String,
    pub mailer: Arc<dyn Mailer>,
}

/// Routeur sans état — conservé pour les tests des endpoints statiques existants.
pub fn router() -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/health/live", get(health_live))
        .route("/v1/health/ready", get(health_ready))
        .route("/v1/metrics", get(metrics))
}

/// Application complète : santé + auth. Utilisé en production et dans les tests d'intégration auth.
///
/// Le `JobDispatcher` est injecté comme `Extension` (stub no-op par défaut).
/// Pour la production avec un dispatcher réel, utiliser [`app_with_dispatcher`].
pub fn app(state: AppState) -> Router {
    app_with_dispatcher(state, Arc::new(StubJobDispatcher))
}

/// Variante de [`app`] permettant d'injecter un dispatcher personnalisé (prod, tests avancés).
pub fn app_with_dispatcher(state: AppState, dispatcher: Arc<dyn JobDispatcher>) -> Router {
    Router::new()
        .route("/v1/health", get(health))
        .route("/v1/health/live", get(health_live))
        .route("/v1/health/ready", get(health_ready))
        .route("/v1/metrics", get(metrics))
        .route("/v1/auth/register", post(auth::register::register))
        .route("/v1/auth/login", post(auth::login::login))
        .route("/v1/auth/refresh", post(auth::refresh::refresh))
        .route("/v1/auth/logout", post(auth::logout::logout))
        .route("/v1/auth/mfa/enroll", post(auth::mfa_enroll::mfa_enroll))
        .route("/v1/auth/mfa/verify", post(auth::mfa_verify::mfa_verify))
        .route(
            "/v1/auth/password/forgot",
            post(auth::forgot_password::forgot_password),
        )
        .route(
            "/v1/auth/password/reset",
            post(auth::reset_password::reset_password),
        )
        .route("/v1/me", get(auth::me))
        .route("/v1/pro/register", post(auth::pro_register))
        .route(
            "/v1/pro/verification",
            get(auth::get_pro_verification).post(auth::pro_verification),
        )
        .route(
            "/v1/cabinet",
            get(auth::get_cabinet).patch(auth::patch_cabinet),
        )
        .route("/v1/cabinet/provider", patch(auth::patch_cabinet_provider))
        .route(
            "/v1/cabinet/provider/listing",
            put(auth::put_cabinet_provider_listing),
        )
        .route(
            "/v1/cabinet/members",
            get(auth::get_cabinet_members).post(auth::post_cabinet_members),
        )
        .route(
            "/v1/cabinet/members/:user_id",
            patch(auth::patch_cabinet_member).delete(auth::delete_cabinet_member),
        )
        .route(
            "/v1/account",
            get(auth::get_account).patch(auth::patch_account),
        )
        .route(
            "/v1/account/coverage",
            get(auth::get_account_coverage).patch(auth::patch_account_coverage),
        )
        .route("/v1/account/coverage/card", post(auth::post_coverage_card))
        .route(
            "/v1/account/notification-preferences",
            get(auth::get_account_notification_preferences)
                .patch(auth::patch_account_notification_preferences),
        )
        .route(
            "/v1/account/dependents",
            get(auth::get_account_dependents).post(auth::post_account_dependents),
        )
        .route(
            "/v1/account/dependents/:id",
            get(auth::get_account_dependent_by_id)
                .patch(auth::patch_account_dependent)
                .delete(auth::delete_account_dependent),
        )
        .route("/v1/appointments", get(appointments::list_appointments))
        .route("/v1/appointments/:id", get(appointments::get_appointment))
        .route("/v1/dashboard", get(dashboard::get_dashboard))
        .route("/v1/account/consents", get(auth::get_account_consents))
        .route(
            "/v1/account/consents/:purpose",
            put(auth::put_account_consent),
        )
        .layer(Extension(dispatcher))
        .with_state(state)
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
