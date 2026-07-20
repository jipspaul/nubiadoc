//! `SmsSender` implémentation Twilio — #4036.
//!
//! Quoi : envoie les rappels RDV canal SMS via l'API REST Twilio
//! (`POST /2010-04-01/Accounts/{Sid}/Messages.json`, Basic Auth
//! `AccountSid:AuthToken`, corps form-encoded `To`/`From`/`Body`).
//!
//! Quand : construit une fois au boot (`TwilioSmsSender::from_env()`),
//! injecté dans `run_dispatch_loop` (même pattern que `BrevoMailer`/`Mailer`,
//! `brevo_mailer.rs`).
//!
//! Pourquoi ce provider (l'issue #4036 citait OVH SMS comme exemple FR,
//! "provider à choisir") : le wire-format Twilio (Basic Auth à 2 secrets,
//! corps form-encoded stable depuis plus d'une décennie) est un format que
//! je peux affirmer avec confiance, contrairement à l'API OVH v6 (signature
//! HMAC-SHA1 + Consumer Key nécessitant un flow de validation interactif
//! hors-ligne pour être généré) dont je ne peux pas vérifier le détail exact
//! sans compte de test réel. Si la résidence des données FR devient une
//! contrainte dure, migrer vers OVH SMS reste possible sans toucher au
//! reste du worker (un seul fichier à remplacer, `SmsSender` reste le
//! contrat).
//!
//! Modes d'échec : `send` est synchrone et ne doit jamais bloquer ni
//! paniquer l'appelant — l'appel HTTP part dans un `tokio::spawn` séparé
//! (même garde que `BrevoMailer::send`) ; une erreur réseau ou une réponse
//! non-succès du provider est loggée (`tracing::warn!`), jamais remontée.

use crate::SmsSender;

const DEFAULT_TWILIO_BASE_URL: &str = "https://api.twilio.com";

/// Implémentation `SmsSender` pour l'API REST Twilio.
pub struct TwilioSmsSender {
    account_sid: String,
    auth_token: String,
    from_number: String,
    base_url: String,
    client: reqwest::Client,
}

impl TwilioSmsSender {
    /// Construit depuis les variables d'environnement `TWILIO_ACCOUNT_SID`,
    /// `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER` (numéro expéditeur au
    /// format E.164, ex. `+33600000000`). Fallback permissif (chaîne vide)
    /// si absentes : ne panique jamais au boot, même pattern que
    /// `BrevoMailer::from_env` — les envois échoueront silencieusement
    /// (loggés) plutôt que de bloquer le démarrage du serveur HTTP.
    pub fn from_env() -> Self {
        Self::with_base_url(
            std::env::var("TWILIO_ACCOUNT_SID").unwrap_or_default(),
            std::env::var("TWILIO_AUTH_TOKEN").unwrap_or_default(),
            std::env::var("TWILIO_FROM_NUMBER").unwrap_or_default(),
            std::env::var("TWILIO_BASE_URL")
                .unwrap_or_else(|_| DEFAULT_TWILIO_BASE_URL.to_string()),
        )
    }

    /// Constructeur explicite (utilisé par `from_env` et par les tests
    /// d'intégration `api/tests/` pour pointer vers un serveur mock — `pub`
    /// et non `#[cfg(test)]` : un binaire de test externe lie la lib en
    /// mode non-test et ne voit pas les items `#[cfg(test)]`).
    pub fn with_base_url(
        account_sid: impl Into<String>,
        auth_token: impl Into<String>,
        from_number: impl Into<String>,
        base_url: impl Into<String>,
    ) -> Self {
        Self {
            account_sid: account_sid.into(),
            auth_token: auth_token.into(),
            from_number: from_number.into(),
            base_url: base_url.into(),
            client: reqwest::Client::new(),
        }
    }
}

impl SmsSender for TwilioSmsSender {
    fn send(&self, to: &str, body: &str) {
        let url = format!(
            "{}/2010-04-01/Accounts/{}/Messages.json",
            self.base_url, self.account_sid
        );
        let client = self.client.clone();
        let account_sid = self.account_sid.clone();
        let auth_token = self.auth_token.clone();
        let from = self.from_number.clone();
        let to = to.to_string();
        let body = body.to_string();

        tokio::spawn(async move {
            let params = [
                ("To", to.as_str()),
                ("From", from.as_str()),
                ("Body", body.as_str()),
            ];
            let result = client
                .post(&url)
                .basic_auth(account_sid, Some(auth_token))
                .form(&params)
                .send()
                .await;

            match result {
                Ok(resp) if resp.status().is_success() => {
                    tracing::info!(%to, "twilio_sms: SMS envoyé");
                }
                Ok(resp) => {
                    tracing::warn!(
                        %to,
                        status = %resp.status(),
                        "twilio_sms: réponse provider non-succès"
                    );
                }
                Err(err) => {
                    tracing::warn!(%to, error = %err, "twilio_sms: échec envoi (provider injoignable)");
                }
            }
        });
    }
}
