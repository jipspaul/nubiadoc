//! `JobDispatcher` réel FCM (HTTP v1 + compte de service) — #6321.
//!
//! Quoi : `FcmJobDispatcher` décore un autre `JobDispatcher` (`inner`,
//! typiquement `WsPushDispatcher` sur le routeur HTTP ou `StubJobDispatcher`
//! sur les workers `tokio::spawn` de `main.rs`). `enqueue_push_notification`
//! délègue d'abord à `inner` (comportement inchangé — push WS temps réel côté
//! `WsPushDispatcher`, no-op côté `StubJobDispatcher`) puis, si
//! `FIREBASE_SERVICE_ACCOUNT` est configuré, envoie en plus un vrai push FCM
//! à CHAQUE device actif du destinataire. Les autres méthodes du trait sont
//! de purs pass-through vers `inner` : seul le push est concerné par cette
//! issue (cf. doc de `JobDispatcher::enqueue_interop_notification` pour le
//! raccourci équivalent côté interop).
//!
//! OAuth2 : JWT RS256 signé avec la clé privée du compte de service (claims
//! standard "service account to service account" Google), échangé contre un
//! access token auprès de `token_uri` (grant_type
//! `urn:ietf:params:oauth:grant-type:jwt-bearer`). Seul le scope
//! `firebase.messaging` est demandé — c'est le seul nécessaire à
//! `POST /v1/projects/<project_id>/messages:send`.
//!
//! Anti-PII : même contrat que `notify.rs`/`realtime::WsPushDispatcher` — le
//! payload ne contient jamais le contenu métier, seulement le titre déjà
//! générique stocké en clair et `data{kind, notification_id, deeplink}` (le
//! contenu réel est chargé authentifié à l'ouverture de l'app).
//!
//! Purge : une réponse FCM `UNREGISTERED`/`INVALID_ARGUMENT` signifie que le
//! token n'est plus valide (app désinstallée, token FCM tourné côté OS) — le
//! device est soft-deleted (`deleted_at`, même colonne que
//! `DELETE /v1/devices/:token`) pour ne pas retenter indéfiniment un token mort.
//!
//! Fallback : sans `FIREBASE_SERVICE_ACCOUNT` (dev local, LXC de déploiement
//! sans ce secret), aucun appel réseau FCM/OAuth2 n'est tenté — seul `inner`
//! s'exécute, comportement strictement identique à avant cette issue.

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde::Deserialize;
use serde_json::json;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::JobDispatcher;

const FCM_SCOPE: &str = "https://www.googleapis.com/auth/firebase.messaging";
const DEFAULT_FCM_BASE_URL: &str = "https://fcm.googleapis.com";
const DEFAULT_TOKEN_URI: &str = "https://oauth2.googleapis.com/token";

/// Sous-ensemble du JSON de compte de service Google nécessaire à l'OAuth2
/// (même secret `FIREBASE_SERVICE_ACCOUNT` qu'utilisé par mobile-distribute
/// en CI). `token_uri` par défaut à l'endpoint Google réel — surchargeable
/// pour pointer un serveur mock dans les tests d'intégration.
#[derive(Clone, Deserialize)]
struct ServiceAccount {
    project_id: String,
    client_email: String,
    private_key: String,
    #[serde(default = "default_token_uri")]
    token_uri: String,
}

fn default_token_uri() -> String {
    DEFAULT_TOKEN_URI.to_string()
}

pub struct FcmJobDispatcher {
    inner: Arc<dyn JobDispatcher>,
    db: PgPool,
    service_account: Option<ServiceAccount>,
    fcm_base_url: String,
    client: reqwest::Client,
}

impl FcmJobDispatcher {
    /// Construit depuis `FIREBASE_SERVICE_ACCOUNT` (JSON du compte de
    /// service). Absent ou invalide → `service_account` reste `None` :
    /// fallback silencieux sur `inner` uniquement (cf. doc de module), jamais
    /// de panic au démarrage.
    pub fn new(inner: Arc<dyn JobDispatcher>, db: PgPool) -> Self {
        let service_account = std::env::var("FIREBASE_SERVICE_ACCOUNT")
            .ok()
            .and_then(|raw| serde_json::from_str(&raw).ok());
        Self {
            inner,
            db,
            service_account,
            fcm_base_url: DEFAULT_FCM_BASE_URL.to_string(),
            client: reqwest::Client::new(),
        }
    }

    /// Constructeur explicite pour les tests d'intégration (`api/tests/`) :
    /// permet d'injecter un compte de service (dont potentiellement un
    /// `token_uri` de mock) et une base URL FCM de mock, plutôt que les
    /// endpoints Google réels (même pattern que
    /// `BrevoMailer::with_base_url`/`TwilioSmsSender::with_base_url`).
    pub fn with_service_account_json(
        inner: Arc<dyn JobDispatcher>,
        db: PgPool,
        service_account_json: &str,
        fcm_base_url: impl Into<String>,
    ) -> Self {
        let service_account = serde_json::from_str(service_account_json).ok();
        Self {
            inner,
            db,
            service_account,
            fcm_base_url: fcm_base_url.into(),
            client: reqwest::Client::new(),
        }
    }
}

impl JobDispatcher for FcmJobDispatcher {
    // Hors périmètre #6321 : ces trois jobs gardent le comportement de
    // `inner` (stub ou toute autre implémentation future) sans y toucher.
    fn enqueue_verify_provider(&self, verification_id: Uuid) {
        self.inner.enqueue_verify_provider(verification_id);
    }

    fn enqueue_notify_callback(&self, appointment_id: Uuid, cabinet_id: Uuid) {
        self.inner
            .enqueue_notify_callback(appointment_id, cabinet_id);
    }

    fn enqueue_interop_notification(
        &self,
        cabinet_id: Uuid,
        resource_type: &str,
        resource_id: Uuid,
    ) {
        self.inner
            .enqueue_interop_notification(cabinet_id, resource_type, resource_id);
    }

    fn enqueue_push_notification(&self, app_user_id: Uuid, notification_id: Uuid) {
        // Comportement existant inchangé (push WS temps réel / no-op stub).
        self.inner
            .enqueue_push_notification(app_user_id, notification_id);

        let Some(service_account) = self.service_account.clone() else {
            return;
        };
        let db = self.db.clone();
        let client = self.client.clone();
        let fcm_base_url = self.fcm_base_url.clone();
        tokio::spawn(async move {
            send_fcm_push(
                &client,
                &db,
                &service_account,
                &fcm_base_url,
                app_user_id,
                notification_id,
            )
            .await;
        });
    }
}

/// Échange le JWT signé du compte de service contre un access token OAuth2
/// (`grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`). `None` sur
/// toute erreur (clé invalide, réseau, réponse non-succès) — jamais de panic.
async fn fetch_access_token(
    client: &reqwest::Client,
    service_account: &ServiceAccount,
) -> Option<String> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?.as_secs();
    let claims = json!({
        "iss": service_account.client_email,
        "scope": FCM_SCOPE,
        "aud": service_account.token_uri,
        "iat": now,
        "exp": now + 3600,
    });
    let key = EncodingKey::from_rsa_pem(service_account.private_key.as_bytes()).ok()?;
    let assertion = jsonwebtoken::encode(&Header::new(Algorithm::RS256), &claims, &key).ok()?;

    let resp = client
        .post(&service_account.token_uri)
        .form(&[
            ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
            ("assertion", assertion.as_str()),
        ])
        .send()
        .await
        .ok()?;

    if !resp.status().is_success() {
        tracing::warn!(status = %resp.status(), "fcm: échec récupération de l'access token OAuth2");
        return None;
    }
    let body: serde_json::Value = resp.json().await.ok()?;
    body.get("access_token")?.as_str().map(str::to_string)
}

/// `true` si le corps d'erreur FCM v1 signale un token mort (`UNREGISTERED`)
/// ou un argument invalide (`INVALID_ARGUMENT`, ex. token malformé) — le
/// status peut être porté directement par `error.status` ou, pour
/// `UNREGISTERED`, niché dans `error.details[].errorCode` (le status racine
/// est alors `NOT_FOUND`), cf. doc FCM HTTP v1 des erreurs.
fn is_dead_token_error(body: &serde_json::Value) -> bool {
    let top_status = body["error"]["status"].as_str().unwrap_or_default();
    if top_status == "UNREGISTERED" || top_status == "INVALID_ARGUMENT" {
        return true;
    }
    body["error"]["details"].as_array().is_some_and(|details| {
        details.iter().any(|detail| {
            matches!(
                detail["errorCode"].as_str(),
                Some("UNREGISTERED") | Some("INVALID_ARGUMENT")
            )
        })
    })
}

/// Soft-delete le device mort (même effet que `DELETE /v1/devices/:token`).
/// GUC RLS posé sur `app_user_id` (déjà validé par l'appelant, cf.
/// `send_fcm_push`) — `device_owner` (migration 0052) exige
/// `app.current_user_id = app_user_id`.
async fn purge_device(db: &PgPool, app_user_id: Uuid, device_id: Uuid) {
    let Ok(mut tx) = db.begin().await else { return };
    if sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(app_user_id.to_string())
        .execute(&mut *tx)
        .await
        .is_err()
    {
        return;
    }
    let _ =
        sqlx::query("UPDATE device SET deleted_at = now() WHERE id = $1 AND deleted_at IS NULL")
            .bind(device_id)
            .execute(&mut *tx)
            .await;
    let _ = tx.commit().await;
}

/// Charge la notification et les devices actifs du destinataire, puis
/// envoie un push FCM HTTP v1 à chacun. Best-effort intégral (même
/// philosophie que `WsPushDispatcher::enqueue_push_notification`) : DB
/// indisponible, ligne absente, aucun device actif ou OAuth2 en échec ⇒
/// no-op silencieux, jamais remonté à l'appelant fire-and-forget.
async fn send_fcm_push(
    client: &reqwest::Client,
    db: &PgPool,
    service_account: &ServiceAccount,
    fcm_base_url: &str,
    app_user_id: Uuid,
    notification_id: Uuid,
) {
    let Ok(mut tx) = db.begin().await else { return };
    if sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(app_user_id.to_string())
        .execute(&mut *tx)
        .await
        .is_err()
    {
        return;
    }

    let notification_row = sqlx::query(
        "SELECT kind, title, data FROM notification WHERE id = $1 AND app_user_id = $2",
    )
    .bind(notification_id)
    .bind(app_user_id)
    .fetch_optional(&mut *tx)
    .await;

    let device_rows = sqlx::query(
        "SELECT id, fcm_token FROM device WHERE app_user_id = $1 AND deleted_at IS NULL",
    )
    .bind(app_user_id)
    .fetch_all(&mut *tx)
    .await;

    let _ = tx.rollback().await; // lecture seule

    let Ok(Some(notification_row)) = notification_row else {
        return;
    };
    let Ok(device_rows) = device_rows else { return };
    if device_rows.is_empty() {
        return;
    }

    let kind: String = notification_row.try_get("kind").unwrap_or_default();
    let title: String = notification_row.try_get("title").unwrap_or_default();
    let data: serde_json::Value = notification_row.try_get("data").unwrap_or(json!({}));
    let deeplink = crate::notifications::derive_deep_link(&kind, &data).unwrap_or_default();

    let Some(access_token) = fetch_access_token(client, service_account).await else {
        return;
    };

    let url = format!(
        "{}/v1/projects/{}/messages:send",
        fcm_base_url, service_account.project_id
    );

    for device_row in device_rows {
        let (Ok(device_id), Ok(fcm_token)) = (
            device_row.try_get::<Uuid, _>("id"),
            device_row.try_get::<String, _>("fcm_token"),
        ) else {
            continue;
        };

        let payload = json!({
            "message": {
                "token": fcm_token,
                "notification": { "title": title },
                "data": {
                    "kind": kind,
                    "notification_id": notification_id.to_string(),
                    "deeplink": deeplink,
                }
            }
        });

        let result = client
            .post(&url)
            .bearer_auth(&access_token)
            .json(&payload)
            .send()
            .await;

        match result {
            Ok(resp) if resp.status().is_success() => {
                tracing::info!(%app_user_id, %device_id, "fcm: push envoyé");
            }
            Ok(resp) => {
                let status = resp.status();
                let body: serde_json::Value = resp.json().await.unwrap_or(json!({}));
                if is_dead_token_error(&body) {
                    purge_device(db, app_user_id, device_id).await;
                    tracing::info!(%device_id, "fcm: token mort purgé (UNREGISTERED/INVALID_ARGUMENT)");
                } else {
                    tracing::warn!(%device_id, %status, "fcm: réponse provider non-succès");
                }
            }
            Err(err) => {
                tracing::warn!(%device_id, error = %err, "fcm: échec réseau à l'envoi");
            }
        }
    }
}
