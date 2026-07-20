//! Implémentation `Mailer` réelle via l'API transactionnelle Brevo
//! (anciennement Sendinblue) — #4035.
//!
//! Quoi : `BrevoMailer` remplace `StubMailer` (no-op) en production. Même
//! trait `Mailer`, signature inchangée (sync, ne renvoie rien).
//!
//! Pourquoi fire-and-forget en `tokio::spawn` : le trait `Mailer` documente
//! "ne doit jamais bloquer ni paniquer" — un appel HTTP est intrinsèquement
//! async et faillible. Chaque envoi est donc délégué à une task tokio
//! indépendante ; un échec (réseau, 4xx/5xx Brevo) est loggé, jamais remonté
//! à l'appelant (même philosophie que `JobDispatcher::enqueue_*`).
//!
//! Secrets : `BREVO_API_KEY` lu depuis l'environnement (Secret k8s syncé
//! Infisical, jamais en dur — cf. CLAUDE.md règle secrets). `base_url` est
//! injectable (pas seulement l'API Brevo réelle) pour permettre aux tests de
//! pointer vers un serveur mock (wiremock) sans appeler le vrai provider.
//!
//! Modes d'échec : `BREVO_API_KEY` absent → la requête part quand même (Brevo
//! répondra 401, loggé côté warn) plutôt que de paniquer au démarrage — un
//! provider mail cassé ne doit jamais empêcher le boot de l'API.

use crate::Mailer;

const DEFAULT_BREVO_BASE_URL: &str = "https://api.brevo.com";

pub struct BrevoMailer {
    api_key: String,
    sender_email: String,
    sender_name: String,
    app_base_url: String,
    base_url: String,
    client: reqwest::Client,
}

impl BrevoMailer {
    /// Construit depuis l'environnement (usage production, cf. `main.rs`).
    /// `BREVO_API_KEY`/`BREVO_SENDER_EMAIL`/`BREVO_SENDER_NAME`/`APP_BASE_URL`
    /// — valeurs par défaut permissives (jamais de panic au démarrage) plutôt
    /// que `.expect()` sur une config mail non bloquante pour le reste de l'API.
    pub fn from_env() -> Self {
        Self {
            api_key: std::env::var("BREVO_API_KEY").unwrap_or_default(),
            sender_email: std::env::var("BREVO_SENDER_EMAIL")
                .unwrap_or_else(|_| "no-reply@nubia.invalid".to_string()),
            sender_name: std::env::var("BREVO_SENDER_NAME").unwrap_or_else(|_| "Nubia".to_string()),
            app_base_url: std::env::var("APP_BASE_URL")
                .unwrap_or_else(|_| "https://app.nubia.invalid".to_string()),
            base_url: DEFAULT_BREVO_BASE_URL.to_string(),
            client: reqwest::Client::new(),
        }
    }

    /// Construction explicite — utilisée par les tests pour injecter l'URI
    /// d'un serveur mock à la place de l'API Brevo réelle. `#[cfg(test)]`
    /// serait invisible depuis `api/tests/` (binaire séparé, lib compilée
    /// hors mode test) : ce constructeur reste donc `pub` sans restriction,
    /// c'est une simple flexibilité de configuration, pas une surface de
    /// sécurité (aucun secret ni bypass RLS).
    pub fn with_base_url(
        api_key: impl Into<String>,
        sender_email: impl Into<String>,
        sender_name: impl Into<String>,
        app_base_url: impl Into<String>,
        base_url: impl Into<String>,
    ) -> Self {
        Self {
            api_key: api_key.into(),
            sender_email: sender_email.into(),
            sender_name: sender_name.into(),
            app_base_url: app_base_url.into(),
            base_url: base_url.into(),
            client: reqwest::Client::new(),
        }
    }

    fn send(&self, to: &str, subject: &str, html_content: String) {
        let payload = serde_json::json!({
            "sender": { "email": self.sender_email, "name": self.sender_name },
            "to": [{ "email": to }],
            "subject": subject,
            "htmlContent": html_content,
        });
        let url = format!("{}/v3/smtp/email", self.base_url);
        let client = self.client.clone();
        let api_key = self.api_key.clone();
        tokio::spawn(async move {
            let result = client
                .post(&url)
                .header("api-key", api_key)
                .header("content-type", "application/json")
                .json(&payload)
                .send()
                .await;
            match result {
                Ok(resp) if resp.status().is_success() => {
                    tracing::info!("brevo_mailer: email envoyé");
                }
                Ok(resp) => {
                    tracing::warn!(
                        status = %resp.status(),
                        "brevo_mailer: envoi refusé par le provider"
                    );
                }
                Err(err) => {
                    tracing::warn!(error = %err, "brevo_mailer: échec réseau à l'envoi");
                }
            }
        });
    }
}

impl Mailer for BrevoMailer {
    fn send_password_reset(&self, to: &str, token: &str) {
        let link = format!("{}/reset-password?token={}", self.app_base_url, token);
        self.send(
            to,
            "Réinitialisez votre mot de passe",
            format!(
                "<p>Cliquez sur ce lien pour réinitialiser votre mot de passe : \
                 <a href=\"{link}\">{link}</a></p>\
                 <p>Ce lien expire prochainement. Si vous n'êtes pas à l'origine de \
                 cette demande, ignorez cet email.</p>"
            ),
        );
    }

    fn send_invite(&self, to: &str, token: &str) {
        let link = format!("{}/set-password?token={}", self.app_base_url, token);
        self.send(
            to,
            "Vous avez été invité·e à rejoindre votre cabinet",
            format!(
                "<p>Cliquez sur ce lien pour définir votre mot de passe et accéder \
                 à votre espace : <a href=\"{link}\">{link}</a></p>"
            ),
        );
    }
}
