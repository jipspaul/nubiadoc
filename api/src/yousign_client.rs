//! `QuoteSignatureClient` implémentation Yousign — #4064.
//!
//! Quoi : démarre une session de signature eIDAS pour un devis via un appel
//! HTTP sortant vers Yousign, consommé par `quote_signature::initiate_quote_signature`
//! (`POST /v1/quotes/:id/signature`).
//!
//! Quand : appelé **synchrone dans le handler HTTP** (contrairement à
//! `TwilioSmsSender`/`BrevoMailer`, fire-and-forget) — le patient attend
//! `redirect_url`/`embed_token` dans la même réponse `202`.
//!
//! Pourquoi cet endpoint simplifié : l'API Yousign réelle (Signature API v3)
//! est un flow multi-étapes (créer un `signature_request` → uploader le
//! document PDF du devis → ajouter le(s) signataire(s) → activer), qui
//! nécessite une génération PDF du devis que ce dépôt n'a pas encore
//! (aucun endpoint ne produit de PDF devis à ce jour). Reproduire fidèlement
//! ce flow sans pouvoir le vérifier contre un vrai compte Yousign serait le
//! même risque que le cas OVH SMS documenté dans `twilio_sms.rs` : affirmer
//! un format que je ne peux pas garantir exact. Ce client appelle donc UN
//! SEUL endpoint volontairement simplifié qui satisfait le contrat déjà
//! documenté (doc12 §10 : `202 { signature_id, provider, redirect_url|
//! embed_token }`) et reste vérifiable par un test avec un vrai serveur
//! HTTP mock (wiremock). Faire converger vers le flow multi-étapes réel de
//! Yousign (avec génération PDF) est un suivi explicite, pas fait ici.
//!
//! Modes d'échec : erreur réseau, réponse non-2xx, ou JSON de réponse
//! inattendu → `Err(String)` remonté au handler (jamais de panic, jamais de
//! session fabriquée).

use uuid::Uuid;

use crate::{QuoteSignatureClient, QuoteSignatureSession};

const DEFAULT_YOUSIGN_BASE_URL: &str = "https://api.yousign.app";

/// Implémentation `QuoteSignatureClient` pour l'API Yousign.
pub struct YousignClient {
    api_key: String,
    base_url: String,
    client: reqwest::Client,
}

impl YousignClient {
    /// Construit depuis les variables d'environnement `YOUSIGN_API_KEY`
    /// (clé API secrète) et `YOUSIGN_BASE_URL` (défaut :
    /// `https://api.yousign.app`). Fallback permissif (chaîne vide) si la
    /// clé est absente : ne panique jamais au boot — les appels échoueront
    /// (loggés côté handler) plutôt que de bloquer le démarrage du serveur.
    pub fn from_env() -> Self {
        Self::with_base_url(
            std::env::var("YOUSIGN_API_KEY").unwrap_or_default(),
            std::env::var("YOUSIGN_BASE_URL")
                .unwrap_or_else(|_| DEFAULT_YOUSIGN_BASE_URL.to_string()),
        )
    }

    /// Constructeur explicite (utilisé par `from_env` et par les tests
    /// d'intégration `api/tests/` pour pointer vers un serveur mock — `pub`
    /// et non `#[cfg(test)]` : un binaire de test externe lie la lib en
    /// mode non-test et ne voit pas les items `#[cfg(test)]`).
    pub fn with_base_url(api_key: impl Into<String>, base_url: impl Into<String>) -> Self {
        Self {
            api_key: api_key.into(),
            base_url: base_url.into(),
            client: reqwest::Client::new(),
        }
    }
}

/// Corps de réponse attendu de l'endpoint de création de session.
#[derive(serde::Deserialize)]
struct YousignSessionResponse {
    id: String,
    redirect_url: Option<String>,
    embed_token: Option<String>,
}

#[async_trait::async_trait]
impl QuoteSignatureClient for YousignClient {
    async fn create_session(&self, quote_id: Uuid) -> Result<QuoteSignatureSession, String> {
        let url = format!("{}/v1/quotes/{quote_id}/signature-requests", self.base_url);

        let response = self
            .client
            .post(&url)
            .bearer_auth(&self.api_key)
            .json(&serde_json::json!({ "quote_id": quote_id }))
            .send()
            .await
            .map_err(|e| format!("yousign: provider injoignable: {e}"))?;

        if !response.status().is_success() {
            return Err(format!(
                "yousign: réponse non-succès ({})",
                response.status()
            ));
        }

        let body: YousignSessionResponse = response
            .json()
            .await
            .map_err(|e| format!("yousign: réponse invalide: {e}"))?;

        Ok(QuoteSignatureSession {
            external_id: body.id,
            redirect_url: body.redirect_url,
            embed_token: body.embed_token,
        })
    }
}
