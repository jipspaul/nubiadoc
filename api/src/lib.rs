use std::sync::Arc;

use axum::{
    routing::{get, patch, post, put},
    Extension, Router,
};
use sqlx::PgPool;
use tower_http::cors::{Any, CorsLayer};
use uuid::Uuid;

mod appointments;
mod auth;
mod billing;
mod cabinet_messaging;
mod clinical;
mod dashboard;
mod documents;
mod health;
mod marketplace;
mod messaging;
mod scheduling;
mod treatment_plans;

/// Trait de génération d'URL signées Object Storage — swappable (stub en test, MinIO/Scaleway en prod).
pub trait StorageClient: Send + Sync {
    /// Retourne une URL signée valable `expires_in_secs` secondes.
    fn sign_url(&self, key: &str, expires_in_secs: u64) -> String;
}

/// Implémentation no-op pour les tests et le dev local.
pub struct StubStorageClient;

impl StorageClient for StubStorageClient {
    fn sign_url(&self, key: &str, expires_in_secs: u64) -> String {
        format!("https://storage.stub/{key}?expires={expires_in_secs}")
    }
}

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

/// Trait de signature d'URL Object Storage — swappable (stub en test, Scaleway en prod).
pub trait StorageSigner: Send + Sync {
    /// Génère une URL signée fraîche pour la clé de stockage donnée.
    /// Retourne `None` si le lien est expiré ou inaccessible (`→ 410`).
    fn sign(&self, storage_key: &str) -> Option<String>;
}

/// Implémentation stub : URL fixe, pour les tests et le dev local.
pub struct StubStorageSigner;

impl StorageSigner for StubStorageSigner {
    fn sign(&self, storage_key: &str) -> Option<String> {
        Some(format!(
            "https://storage.example.com/{}?token=stub",
            storage_key
        ))
    }
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
        .route("/v1/health", get(health::health))
        .route("/v1/health/live", get(health::health_live))
        .route("/v1/health/ready", get(health::health_ready))
        .route("/v1/metrics", get(health::metrics))
}

/// Application complète : santé + auth. Utilisé en production et dans les tests d'intégration auth.
///
/// Le `JobDispatcher` est injecté comme `Extension` (stub no-op par défaut).
/// Pour la production avec un dispatcher réel, utiliser [`app_with_dispatcher`].
pub fn app(state: AppState) -> Router {
    app_with_dispatcher(
        state,
        Arc::new(StubJobDispatcher),
        Arc::new(StubStorageSigner),
    )
}

/// Variante de [`app`] permettant d'injecter un dispatcher personnalisé (prod, tests avancés).
pub fn app_with_dispatcher(
    state: AppState,
    dispatcher: Arc<dyn JobDispatcher>,
    signer: Arc<dyn StorageSigner>,
) -> Router {
    Router::new()
        .route("/v1/health", get(health::health))
        .route("/v1/health/live", get(health::health_live))
        .route("/v1/health/ready", get(health::health_ready_db))
        .route("/v1/metrics", get(health::metrics))
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
        .route(
            "/v1/appointments",
            get(appointments::list_appointments).post(appointments::create_appointment),
        )
        .route(
            "/v1/appointments/:id",
            get(appointments::get_appointment).patch(appointments::patch_appointment),
        )
        .route(
            "/v1/appointments/:id/cancel",
            post(appointments::cancel_appointment),
        )
        .route(
            "/v1/appointments/:id/checkin",
            post(appointments::checkin_appointment),
        )
        .route(
            "/v1/appointments/:id/callback-request",
            post(appointments::callback_appointment),
        )
        .route(
            "/v1/appointments/:id/directions",
            get(appointments::get_appointment_directions),
        )
        .route(
            "/v1/appointments/:id/preparation",
            get(appointments::get_appointment_preparation),
        )
        .route(
            "/v1/documents",
            get(documents::list_documents).post(documents::upload_document),
        )
        .route("/v1/documents/:id", get(documents::get_document))
        .route(
            "/v1/documents/:id/download",
            get(documents::download_document),
        )
        .route(
            "/v1/conversations",
            get(messaging::list_conversations).post(messaging::create_conversation),
        )
        .route(
            "/v1/conversations/:id/messages",
            get(messaging::get_conversation_messages).post(messaging::send_message),
        )
        .route(
            "/v1/cabinet/patients",
            get(clinical::list_cabinet_patients).post(clinical::create_cabinet_patient),
        )
        .route(
            "/v1/cabinet/conversations",
            get(cabinet_messaging::list_cabinet_conversations),
        )
        .route("/v1/cabinet/agenda", get(scheduling::get_cabinet_agenda))
        .route(
            "/v1/cabinet/waiting-room",
            get(scheduling::get_waiting_room),
        )
        .route(
            "/v1/cabinet/appointments",
            get(scheduling::get_cabinet_appointments),
        )
        .route(
            "/v1/cabinet/appointments/:id/confirm",
            post(scheduling::confirm_appointment),
        )
        .route(
            "/v1/cabinet/appointments/:id",
            patch(scheduling::patch_cabinet_appointment),
        )
        .route(
            "/v1/cabinet/waiting-room/call-next",
            post(scheduling::call_next_patient),
        )
        .route(
            "/v1/cabinet/waiting-list",
            get(scheduling::get_waiting_list),
        )
        .route(
            "/v1/cabinet/waiting-list/:id/offer",
            post(scheduling::offer_waiting_list_slot),
        )
        .route("/v1/dashboard", get(dashboard::get_dashboard))
        .route(
            "/v1/treatment-plans",
            get(treatment_plans::list_treatment_plans),
        )
        .route("/v1/quotes", get(billing::list_quotes))
        .route(
            "/v1/payments/intent",
            axum::routing::post(billing::create_payment_intent),
        )
        .route("/v1/professions", get(marketplace::list_professions))
        .route("/v1/specialties", get(marketplace::list_specialties))
        .route("/v1/acts", get(marketplace::list_acts))
        .route("/v1/search/suggest", get(marketplace::suggest_search))
        .route("/v1/search/providers", get(marketplace::search_providers))
        .route("/v1/account/consents", get(auth::get_account_consents))
        .route(
            "/v1/account/consents/:purpose",
            put(auth::put_account_consent),
        )
        .layer(Extension(
            Arc::new(StubStorageClient) as Arc<dyn StorageClient>
        ))
        .layer(Extension(dispatcher))
        .layer(Extension(signer))
        .layer(dev_cors_layer())
        .with_state(state)
}

/// CORS permissif — strictement réservé au dev/POC local (web-console sur :4321,
/// API sur :3000). En prod, restreindre à l'origine exacte du front (NUB-T2).
fn dev_cors_layer() -> CorsLayer {
    CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any)
}
