use std::sync::Arc;

use async_trait::async_trait;
use axum::{
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
    Extension, Json, Router,
};
use serde_json::json;
use sqlx::PgPool;
use tower_http::cors::{Any, CorsLayer};
use uuid::Uuid;

pub use brevo_mailer::BrevoMailer;
pub use quote_relance_dispatch::{
    dispatch_quote_relances, run_quote_relance_loop, QuoteRelanceDispatchError,
    QuoteRelanceDispatchSummary,
};
pub use realtime::channels;
pub use realtime::user_notifications_key;
pub use realtime::WsHub;

/// Construit le `WsPushDispatcher` (mod `realtime` privé) — utilisé par `main`.
pub fn realtime_push_dispatcher(
    hub: std::sync::Arc<WsHub>,
    db: sqlx::PgPool,
) -> realtime::WsPushDispatcher {
    realtime::WsPushDispatcher::new(hub, db)
}
pub use reminder_dispatch::{
    dispatch_pending_reminders, run_dispatch_loop, ReminderDispatchError, ReminderDispatchSummary,
};
pub use scaleway_storage_signer::ScalewayStorageSigner;
pub use twilio_sms::TwilioSmsSender;
pub use visit_offer_expiry::{
    dispatch_visit_offer_expiry, run_visit_offer_expiry_loop, VisitOfferExpiryError,
    VisitOfferExpirySummary,
};
pub use yousign_client::YousignClient;

mod appointment_motifs;
mod appointment_series;
mod appointments_actions;
mod appointments_checkin;
mod appointments_create;
mod appointments_preparation;
mod appointments_read;
mod appointments_read_extras;
mod appointments_response;
mod audit_log;
mod auth;
mod bank_deposit_slip;
mod billing;
mod billing_payments;
mod bookings;
mod brevo_mailer;
mod cabinet_cash_collection;
mod cabinet_cash_register;
mod cabinet_conversation_convert;
mod cabinet_document_download;
mod cabinet_info;
mod cabinet_messaging;
mod cabinet_payments_manual;
mod cabinet_payouts;
mod cabinet_quote_item_parts;
mod cabinet_quotes;
mod cabinet_quotes_export;
mod cabinet_quotes_patch;
mod cabinet_secretariats;
mod cabinet_stats;
mod cabinet_team_messages;
mod ccam_acts;
mod ccam_stock_mappings;
mod clinical;
mod consultation_act_create;
mod consultation_act_stock;
mod consultation_acts;
mod consultation_clinique_read;
mod consultation_context;
mod consultations;
mod cr_templates;
mod dashboard;
mod dental_chart;
mod devices;
mod documents;
mod health;
pub mod hl7v2;
mod implant_passport;
mod interop;
mod lab_work_orders;
mod marketplace;
mod medical_questionnaire;
mod medical_record;
mod messaging;
mod ngap_acts;
mod notifications;
mod notify;
mod nurse;
mod orthodontics;
mod patient_alerts;
mod patient_detail;
mod patient_guardianship;
mod patient_merge;
mod patient_satisfaction;
mod patient_tags;
mod payment_schedules;
mod periodontal_chart;
mod permissions;
mod pharmacy;
mod practitioner_favorite_acts;
mod prescription_list;
mod prescription_renew;
mod prescription_send;
mod prescription_templates;
mod prescriptions;
mod provider_secretariat;
mod provider_unavailability;
mod quote_relance_dispatch;
mod quote_relances;
mod quote_signature;
mod realtime;
mod recall_campaigns;
mod reminder_dispatch;
mod reminders;
mod reviews;
mod routes;
mod scaleway_storage_signer;
mod scheduling;
mod sterilization;
mod stock_items;
mod support;
mod text_validation;
mod treatment_phases;
mod treatment_plans;
mod twilio_sms;
mod visit_offer_expiry;
mod waiting_list;
pub mod web_tunnel;
mod webhooks;
mod yousign_client;

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

/// Trait d'upload d'objets binaires (documents chiffrés) — swappable (in-memory
/// en test, Scaleway/MinIO en prod). Distinct de `StorageClient` (signature
/// d'URL) : ce trait couvre l'écriture effective de l'objet, corrigeant le
/// stub historique où `storage_key` référençait une clé jamais uploadée
/// (issue #4626 — ordonnance signée inutilisable en production).
#[async_trait::async_trait]
pub trait ObjectStorage: Send + Sync {
    /// Uploade `bytes` sous `key` avec le `content_type` donné.
    async fn upload(&self, key: &str, content_type: &str, bytes: Vec<u8>) -> Result<(), String>;
}

/// Implémentation en mémoire pour les tests et le dev local — pas de dépendance
/// réseau, mais l'upload est réellement effectué (contrairement au stub
/// historique qui ne faisait qu'inventer un UUID sans jamais écrire l'objet).
#[derive(Default)]
pub struct InMemoryObjectStorage {
    objects: std::sync::Mutex<std::collections::HashMap<String, (String, Vec<u8>)>>,
}

#[async_trait::async_trait]
impl ObjectStorage for InMemoryObjectStorage {
    async fn upload(&self, key: &str, content_type: &str, bytes: Vec<u8>) -> Result<(), String> {
        self.objects
            .lock()
            .map_err(|_| "lock poisoned".to_string())?
            .insert(key.to_string(), (content_type.to_string(), bytes));
        Ok(())
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

/// Trait d'envoi de SMS — swappable (stub en test, Twilio en prod). #4036.
pub trait SmsSender: Send + Sync {
    /// Envoie un SMS. Ne doit jamais bloquer ni paniquer.
    fn send(&self, to: &str, body: &str);
}

/// Implémentation no-op pour les tests et le dev local.
pub struct StubSmsSender;

impl SmsSender for StubSmsSender {
    fn send(&self, _to: &str, _body: &str) {}
}

/// Trait d'enqueue de jobs apalis — swappable (stub en test, apalis en prod).
pub trait JobDispatcher: Send + Sync {
    /// Enfile un job de vérification ANS. Fire-and-forget : ne bloque pas.
    fn enqueue_verify_provider(&self, verification_id: Uuid);
    /// Enfile un job de notification cabinet suite à une demande de rappel patient.
    fn enqueue_notify_callback(&self, appointment_id: Uuid, cabinet_id: Uuid);
    /// Enfile l'envoi du push FCM d'une notification in-app (payload sans PII :
    /// le contenu réel est chargé authentifié à l'ouverture). Fire-and-forget.
    fn enqueue_push_notification(&self, app_user_id: Uuid, notification_id: Uuid);
    /// Enfile une notification interop (Subscription FHIR, lot A7) suite à
    /// l'écriture d'une ressource FHIR (`Appointment` aujourd'hui). Fire-and-forget.
    ///
    /// Hook posé pour un futur dispatcher apalis réel — aucune implémentation
    /// non-stub de `JobDispatcher` n'existe dans ce dépôt à ce jour (`grep -rn
    /// "impl JobDispatcher"` ne renvoie que `StubJobDispatcher`). La livraison
    /// réelle (lookup abonnements + POST signé HMAC + `interop_delivery`) est
    /// donc effectuée de façon synchrone best-effort par
    /// `interop::subscription::dispatch_notification`, PAS par cette méthode
    /// (raccourci documenté, cf. doc de module `interop/subscription.rs`).
    fn enqueue_interop_notification(
        &self,
        cabinet_id: Uuid,
        resource_type: &str,
        resource_id: Uuid,
    );
}

/// Implémentation no-op pour les tests et le dev local.
pub struct StubJobDispatcher;

impl JobDispatcher for StubJobDispatcher {
    fn enqueue_verify_provider(&self, _verification_id: Uuid) {}
    fn enqueue_notify_callback(&self, _appointment_id: Uuid, _cabinet_id: Uuid) {}
    fn enqueue_push_notification(&self, _app_user_id: Uuid, _notification_id: Uuid) {}
    fn enqueue_interop_notification(
        &self,
        _cabinet_id: Uuid,
        _resource_type: &str,
        _resource_id: Uuid,
    ) {
    }
}

/// Secret Stripe pour la vérification HMAC-SHA256 des webhooks.
///
/// Injecté via `Extension<StripeWebhookSecret>`. Vide en dev/test (tous les
/// appels webhook seront rejetés sauf si le test fournit le bon secret).
#[derive(Clone)]
pub struct StripeWebhookSecret(pub String);

/// Secret Yousign pour la vérification HMAC-SHA256 des webhooks.
///
/// Injecté via `Extension<YousignWebhookSecret>`. Vide en dev/test.
#[derive(Clone)]
pub struct YousignWebhookSecret(pub String);

pub use webhooks::gocardless::GocardlessWebhookSecret;

/// Clé serveur pour la dérivation déterministe des secrets d'abonnement
/// interop (`HMAC-SHA256(INTEROP_SIGNING_KEY, subscription_id)`, lot A7) et
/// la signature des livraisons sortantes (`interop::subscription`). Dédiée —
/// jamais partagée avec `jwt_secret` (séparation des clés : algorithmes/usages
/// différents). Vide en dev/test : la livraison interop est alors ignorée
/// fail-closed plutôt que signée avec une clé devinable (cf.
/// `interop::subscription::dispatch_notification`).
#[derive(Clone)]
pub struct InteropSigningKey(pub String);

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

/// Trait de signature eIDAS (Yousign) — swappable (stub en test, Yousign en prod).
pub trait SignatureClient: Send + Sync {
    /// Initie une signature eIDAS pour une prescription et retourne la référence
    /// externe du provider (ex. Yousign procedure id). Stub : retourne un UUID.
    fn create_signature(&self, prescription_id: uuid::Uuid) -> String;
}

/// Implémentation stub : retourne un UUID fixe, pour les tests et le dev local.
pub struct StubSignatureClient;

impl SignatureClient for StubSignatureClient {
    fn create_signature(&self, prescription_id: uuid::Uuid) -> String {
        format!("stub-sig-{}", prescription_id)
    }
}

/// Session de signature retournée par [`QuoteSignatureClient::create_session`]
/// (#4064). `redirect_url` (parcours web) et/ou `embed_token` (parcours
/// intégré) — le contrat documenté (doc12 §10) autorise l'un ou l'autre.
pub struct QuoteSignatureSession {
    pub external_id: String,
    pub redirect_url: Option<String>,
    pub embed_token: Option<String>,
}

/// Échec de [`QuoteSignatureClient::create_session`] (#4064, #5688).
///
/// `NotConfigured` distingue explicitement « provider non provisionné »
/// (`YOUSIGN_API_KEY` absente — état structurel connu tant qu'aucun compte
/// Yousign n'existe, cf. `deploy.yml`) d'une vraie panne/refus provider
/// (`Failure`) : ces deux cas remontaient auparavant au même `502
/// upstream_unavailable`, ce qui faisait passer une lacune de configuration
/// (non-transitoire, n'implique aucun incident Yousign) pour une panne
/// provider en production auprès du monitoring/QA (#5688).
pub enum QuoteSignatureError {
    NotConfigured,
    Failure(String),
}

impl std::fmt::Display for QuoteSignatureError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NotConfigured => write!(f, "yousign: provider non configuré"),
            Self::Failure(msg) => write!(f, "{msg}"),
        }
    }
}

/// Client de démarrage de signature eIDAS pour un **devis** — swappable
/// (stub en test, Yousign réel en prod, `yousign_client.rs`). #4064.
///
/// Distinct de [`SignatureClient`] (prescriptions, `fire-and-forget`-style
/// synchrone) : ce trait est `async` et appelé de façon **synchrone dans le
/// handler HTTP** — le patient attend `redirect_url`/`embed_token` dans la
/// même réponse (`202`), la confirmation `signed` arrivant plus tard par
/// webhook (`webhooks::yousign`).
#[async_trait]
pub trait QuoteSignatureClient: Send + Sync {
    /// Démarre une session de signature pour `quote_id`. `Err` = provider
    /// non configuré/injoignable/refus — jamais de panic, jamais de valeur
    /// fabriquée.
    async fn create_session(
        &self,
        quote_id: Uuid,
    ) -> Result<QuoteSignatureSession, QuoteSignatureError>;
}

/// Implémentation stub : session fixe, pour les tests et le dev local sans
/// clé Yousign.
pub struct StubQuoteSignatureClient;

#[async_trait]
impl QuoteSignatureClient for StubQuoteSignatureClient {
    async fn create_session(
        &self,
        quote_id: Uuid,
    ) -> Result<QuoteSignatureSession, QuoteSignatureError> {
        Ok(QuoteSignatureSession {
            external_id: format!("stub-sig-{quote_id}"),
            redirect_url: Some(format!("https://signature.stub/{quote_id}")),
            embed_token: None,
        })
    }
}

/// Client de souscription Alma pour un échéancier de paiement fractionné
/// (`payment_schedule.provider = 'alma'`, #4163) — swappable (stub en test,
/// SDK Alma réel en prod, différenciant explicitement classé « Could »
/// §4.4, pas une brique de parité). Appelé synchroniquement à la création
/// de l'échéancier ; `Err` = Alma refuse/injoignable → la création échoue
/// entièrement (pas d'échéancier fantôme non souscrit chez le provider).
#[async_trait]
pub trait AlmaClient: Send + Sync {
    /// Souscrit l'échéancier `schedule_id` auprès d'Alma pour
    /// `total_amount_cents`. Retourne la référence externe (subscription id).
    async fn subscribe(&self, schedule_id: Uuid, total_amount_cents: i64)
        -> Result<String, String>;
}

/// Implémentation stub : référence fixe, pour les tests et le dev local sans
/// clé Alma.
pub struct StubAlmaClient;

#[async_trait]
impl AlmaClient for StubAlmaClient {
    async fn subscribe(
        &self,
        schedule_id: Uuid,
        _total_amount_cents: i64,
    ) -> Result<String, String> {
        Ok(format!("stub-alma-{schedule_id}"))
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
    build_router(
        state,
        Arc::new(StubJobDispatcher),
        Arc::new(StubStorageSigner),
        Arc::new(WsHub::new()),
        Arc::new(StubQuoteSignatureClient),
        Arc::new(StubAlmaClient),
    )
}

/// Variante de [`app`] permettant d'injecter un dispatcher personnalisé (prod, tests avancés).
pub fn app_with_dispatcher(
    state: AppState,
    dispatcher: Arc<dyn JobDispatcher>,
    signer: Arc<dyn StorageSigner>,
) -> Router {
    build_router(
        state,
        dispatcher,
        signer,
        Arc::new(WsHub::new()),
        Arc::new(StubQuoteSignatureClient),
        Arc::new(StubAlmaClient),
    )
}

/// Variante pour les tests qui injectent un hub WS précis (broadcast tests).
pub fn app_with_hub(state: AppState, hub: Arc<WsHub>) -> Router {
    build_router(
        state,
        Arc::new(StubJobDispatcher),
        Arc::new(StubStorageSigner),
        hub,
        Arc::new(StubQuoteSignatureClient),
        Arc::new(StubAlmaClient),
    )
}

/// Variante pour les tests qui injectent un `QuoteSignatureClient` personnalisé
/// (#4064 : pointer vers un serveur HTTP mock plutôt que le stub).
pub fn app_with_quote_signature_client(
    state: AppState,
    quote_signature_client: Arc<dyn QuoteSignatureClient>,
) -> Router {
    build_router(
        state,
        Arc::new(StubJobDispatcher),
        Arc::new(StubStorageSigner),
        Arc::new(WsHub::new()),
        quote_signature_client,
        Arc::new(StubAlmaClient),
    )
}

/// Variante pour la production : `QuoteSignatureClient` **et** `StorageSigner`
/// personnalisés (#4717 — `StubStorageSigner` câblé en dur en production
/// générait des URL vers `storage.example.com`, un domaine fantôme jamais
/// résolu en DNS public, rendant tout export/téléchargement de document
/// non-fonctionnel pour l'utilisateur final).
pub fn app_with_quote_signature_client_and_signer(
    state: AppState,
    quote_signature_client: Arc<dyn QuoteSignatureClient>,
    signer: Arc<dyn StorageSigner>,
) -> Router {
    app_prod(
        state,
        quote_signature_client,
        signer,
        Arc::new(WsHub::new()),
        Arc::new(StubJobDispatcher),
    )
}

/// Variante production complète : hub WS et `JobDispatcher` fournis par
/// l'appelant, pour que le dispatcher publie sur le MÊME hub que les sockets
/// (`WsPushDispatcher`, canal `notifications`). Les autres builders délèguent
/// ici avec des stubs — aucun test existant ne change.
pub fn app_prod(
    state: AppState,
    quote_signature_client: Arc<dyn QuoteSignatureClient>,
    signer: Arc<dyn StorageSigner>,
    hub: Arc<WsHub>,
    dispatcher: Arc<dyn JobDispatcher>,
) -> Router {
    build_router(
        state,
        dispatcher,
        signer,
        hub,
        quote_signature_client,
        Arc::new(StubAlmaClient),
    )
}

/// Variante pour les tests qui injectent un `AlmaClient` personnalisé (#4163 :
/// vérifier que la souscription est bien appelée à la création d'un
/// échéancier `provider='alma'`).
pub fn app_with_alma_client(state: AppState, alma_client: Arc<dyn AlmaClient>) -> Router {
    build_router(
        state,
        Arc::new(StubJobDispatcher),
        Arc::new(StubStorageSigner),
        Arc::new(WsHub::new()),
        Arc::new(StubQuoteSignatureClient),
        alma_client,
    )
}

fn build_router(
    state: AppState,
    dispatcher: Arc<dyn JobDispatcher>,
    signer: Arc<dyn StorageSigner>,
    hub: Arc<WsHub>,
    quote_signature_client: Arc<dyn QuoteSignatureClient>,
    alma_client: Arc<dyn AlmaClient>,
) -> Router {
    let router = Router::new();
    let router = routes::misc::add(router);
    let router = routes::auth_account::add(router);
    let router = routes::appointments::add(router);
    let router = routes::documents_messaging::add(router);
    let router = routes::clinical::add(router);
    let router = routes::cabinet_messaging::add(router);
    let router = routes::scheduling::add(router);
    let router = routes::billing::add(router);
    let router = routes::marketplace::add(router);
    let router = routes::notifications_devices::add(router);
    let router = routes::cr_prescriptions::add(router);
    let router = routes::pharmacy_routes::add(router);
    let router = routes::nurse_routes::add(router);
    let router = routes::secretariats::add(router);
    let router = routes::webhooks_interop::add(router);

    router
        .layer(Extension(hub))
        .layer(Extension(
            Arc::new(StubStorageClient) as Arc<dyn StorageClient>
        ))
        .layer(Extension(
            Arc::new(InMemoryObjectStorage::default()) as Arc<dyn ObjectStorage>
        ))
        .layer(Extension(dispatcher))
        .layer(Extension(signer))
        .layer(Extension(
            Arc::new(StubSignatureClient) as Arc<dyn SignatureClient>
        ))
        .layer(Extension(quote_signature_client))
        .layer(Extension(alma_client))
        .layer(Extension(StripeWebhookSecret(
            std::env::var("STRIPE_WEBHOOK_SECRET").unwrap_or_default(),
        )))
        .layer(Extension(YousignWebhookSecret(
            std::env::var("YOUSIGN_WEBHOOK_SECRET").unwrap_or_default(),
        )))
        .layer(Extension(webhooks::gocardless::GocardlessWebhookSecret(
            std::env::var("GOCARDLESS_WEBHOOK_SECRET").unwrap_or_default(),
        )))
        .layer(Extension(InteropSigningKey(
            std::env::var("INTEROP_SIGNING_KEY").unwrap_or_default(),
        )))
        .layer(axum::middleware::map_response(
            normalize_extractor_rejections,
        ))
        .layer(dev_cors_layer())
        .with_state(state)
}

/// Uniformise le contrat d'erreur (#3518).
///
/// Les extracteurs axum (`Path<Uuid>`, `Json<T>`, …) renvoient par défaut leur
/// rejet en **texte brut** exposant les internes du parseur/serde (ex.
/// « Invalid URL: UUID parsing failed… », « Failed to deserialize the JSON
/// body… »). On réécrit ces réponses en l'enveloppe JSON standard
/// `{"code": …}` cohérente avec `AppError`, sans toucher aux handlers.
///
/// Les réponses déjà en `application/json` (donc celles émises par `AppError`)
/// sont laissées intactes : seul le corps `text/plain` des rejets par défaut
/// est normalisé. Le code HTTP d'origine est préservé.
async fn normalize_extractor_rejections(resp: Response) -> Response {
    let status = resp.status();
    // On ne cible que les statuts émis par les rejets d'extracteurs.
    let is_extractor_status = matches!(
        status,
        StatusCode::BAD_REQUEST
            | StatusCode::UNPROCESSABLE_ENTITY
            | StatusCode::UNSUPPORTED_MEDIA_TYPE
            | StatusCode::LENGTH_REQUIRED
            | StatusCode::PAYLOAD_TOO_LARGE
    );
    if !is_extractor_status {
        return resp;
    }
    // Réponse déjà JSON (contrat respecté, typiquement `AppError`) → on ne touche pas.
    let already_json = resp
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v.starts_with("application/json"));
    if already_json {
        return resp;
    }
    let code = if status == StatusCode::UNPROCESSABLE_ENTITY {
        "validation_error"
    } else {
        "bad_request"
    };
    (status, Json(json!({ "code": code }))).into_response()
}

/// CORS permissif — strictement réservé au dev/POC local (web-console sur :4321,
/// API sur :3000). En prod, restreindre à l'origine exacte du front (NUB-T2).
fn dev_cors_layer() -> CorsLayer {
    CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any)
}
