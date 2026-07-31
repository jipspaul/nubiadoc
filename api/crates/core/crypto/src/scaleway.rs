//! [`KeyManager`] Scaleway Key Manager (production) : enveloppe/désenveloppe
//! la DEK via l'API Encrypt/Decrypt de Scaleway KMS — une clé maître par
//! cabinet (résolution `key_context` → `key_id` déléguée à un
//! [`KeyResolver`] fourni par l'appelant, cf. `docs/05` §3).
//!
//! Contrat API vérifié contre la référence officielle Scaleway
//! (`https://www.scaleway.com/en/developers/api/key-manager/`, schema
//! `v1alpha1`, 2026-07-31) :
//! - `POST /key-manager/v1alpha1/regions/{region}/keys/{key_id}/encrypt`
//!   body `{"plaintext": "<base64>"}` → `{"key_id", "ciphertext": "<base64>"}`.
//! - `POST /key-manager/v1alpha1/regions/{region}/keys/{key_id}/decrypt`
//!   body `{"ciphertext": "<base64>"}` → `{"key_id", "plaintext": "<base64>"}`.
//! - Authentification : header `X-Auth-Token`.
//!
//! Pas de SDK Rust officiel Scaleway pour ce service — appel HTTP direct
//! via `reqwest`, même pattern déjà pratiqué dans ce backend pour d'autres
//! intégrations tierces sans SDK Rust (Yousign, cf.
//! `docs/14-decision-terminal-paiement-cb.md` pour Stripe Terminal).
//!
//! Non testé contre l'API Scaleway réelle (pas de compte/clé KMS
//! disponible dans cet environnement) — testé par mock HTTP (`wiremock`)
//! contre le contrat ci-dessus. À valider en conditions réelles avant mise
//! en production (`docs/05` §3, barrière G3 `docs/07` §11).

use base64::{engine::general_purpose::STANDARD as BASE64, Engine};
use serde::{Deserialize, Serialize};

use crate::{CryptoError, KeyManager};

/// Résout un `key_context` (ex. `cabinet_id`) vers l'ID de clé KMS Scaleway
/// à utiliser. La politique de mapping (une clé par cabinet, ou une clé
/// plateforme partagée pour les données non cabinet-scopées) reste hors de
/// ce crate — implémentée par l'appelant (`AppState`), typiquement adossée
/// à une table `cabinet_kms_key` ou une convention de nommage de clé.
pub trait KeyResolver: Send + Sync {
    fn resolve(&self, key_context: &str) -> Result<String, CryptoError>;
}

const DEFAULT_API_ROOT: &str = "https://api.scaleway.com";

pub struct ScalewayKeyManager<R: KeyResolver> {
    http: reqwest::Client,
    api_token: String,
    region: String,
    resolver: R,
    /// Racine de l'API — `https://api.scaleway.com` en production, surchargée
    /// vers un serveur `wiremock` local dans les tests (`with_api_root`).
    api_root: String,
}

impl<R: KeyResolver> ScalewayKeyManager<R> {
    pub fn new(
        http: reqwest::Client,
        api_token: impl Into<String>,
        region: impl Into<String>,
        resolver: R,
    ) -> Self {
        Self {
            http,
            api_token: api_token.into(),
            region: region.into(),
            resolver,
            api_root: DEFAULT_API_ROOT.to_string(),
        }
    }

    /// Surcharge la racine de l'API (tests uniquement — pointe vers un
    /// `wiremock::MockServer` au lieu de `api.scaleway.com`).
    #[cfg(test)]
    fn with_api_root(mut self, api_root: impl Into<String>) -> Self {
        self.api_root = api_root.into();
        self
    }

    fn base_url(&self, key_id: &str) -> String {
        format!(
            "{}/key-manager/v1alpha1/regions/{}/keys/{}",
            self.api_root, self.region, key_id
        )
    }
}

#[derive(Serialize)]
struct EncryptRequest<'a> {
    plaintext: &'a str,
}

#[derive(Deserialize)]
struct EncryptResponse {
    ciphertext: String,
}

#[derive(Serialize)]
struct DecryptRequest<'a> {
    ciphertext: &'a str,
}

#[derive(Deserialize)]
struct DecryptResponse {
    plaintext: String,
}

#[async_trait::async_trait]
impl<R: KeyResolver> KeyManager for ScalewayKeyManager<R> {
    async fn wrap_key(
        &self,
        dek: &[u8; 32],
        key_context: &str,
    ) -> Result<(Vec<u8>, String), CryptoError> {
        let key_id = self.resolver.resolve(key_context)?;
        let body = EncryptRequest {
            plaintext: &BASE64.encode(dek),
        };

        let response = self
            .http
            .post(format!("{}/encrypt", self.base_url(&key_id)))
            .header("X-Auth-Token", &self.api_token)
            .json(&body)
            .send()
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "Scaleway KMS encrypt: échec réseau");
                CryptoError::KeyWrap
            })?
            .error_for_status()
            .map_err(|e| {
                tracing::error!(error = %e, "Scaleway KMS encrypt: réponse non-2xx");
                CryptoError::KeyWrap
            })?
            .json::<EncryptResponse>()
            .await
            .map_err(|_| CryptoError::KeyWrap)?;

        let wrapped = BASE64
            .decode(response.ciphertext)
            .map_err(|_| CryptoError::KeyWrap)?;

        Ok((wrapped, format!("scaleway:{key_id}")))
    }

    async fn unwrap_key(
        &self,
        wrapped_dek: &[u8],
        key_context: &str,
        key_ref: &str,
    ) -> Result<[u8; 32], CryptoError> {
        let key_id = self.resolver.resolve(key_context)?;
        let expected_ref = format!("scaleway:{key_id}");
        if key_ref != expected_ref {
            return Err(CryptoError::KeyUnwrap);
        }

        let body = DecryptRequest {
            ciphertext: &BASE64.encode(wrapped_dek),
        };

        let response = self
            .http
            .post(format!("{}/decrypt", self.base_url(&key_id)))
            .header("X-Auth-Token", &self.api_token)
            .json(&body)
            .send()
            .await
            .map_err(|e| {
                tracing::error!(error = %e, "Scaleway KMS decrypt: échec réseau");
                CryptoError::KeyUnwrap
            })?
            .error_for_status()
            .map_err(|e| {
                tracing::error!(error = %e, "Scaleway KMS decrypt: réponse non-2xx");
                CryptoError::KeyUnwrap
            })?
            .json::<DecryptResponse>()
            .await
            .map_err(|_| CryptoError::KeyUnwrap)?;

        let dek = BASE64
            .decode(response.plaintext)
            .map_err(|_| CryptoError::KeyUnwrap)?;

        dek.try_into().map_err(|_| CryptoError::KeyUnwrap)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use wiremock::matchers::{header, method, path};
    use wiremock::{Mock, MockServer, ResponseTemplate};

    struct FixedResolver(&'static str);
    impl KeyResolver for FixedResolver {
        fn resolve(&self, _key_context: &str) -> Result<String, CryptoError> {
            Ok(self.0.to_string())
        }
    }

    #[tokio::test]
    async fn wrap_key_posts_base64_plaintext_and_decodes_base64_ciphertext() {
        let server = MockServer::start().await;
        let key_id = "11111111-1111-1111-1111-111111111111";
        let dek = [9u8; 32];
        let fake_wrapped = b"fake-wrapped-dek-bytes".to_vec();

        Mock::given(method("POST"))
            .and(path(format!(
                "/key-manager/v1alpha1/regions/fr-par/keys/{key_id}/encrypt"
            )))
            .and(header("X-Auth-Token", "test-token"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "key_id": key_id,
                "ciphertext": BASE64.encode(&fake_wrapped),
            })))
            .mount(&server)
            .await;

        let km = test_manager(&server, key_id, "test-token");
        let (wrapped, key_ref) = km.wrap_key(&dek, "cabinet-A").await.unwrap();

        assert_eq!(wrapped, fake_wrapped);
        assert_eq!(key_ref, format!("scaleway:{key_id}"));
    }

    #[tokio::test]
    async fn unwrap_key_rejects_a_key_ref_from_a_different_key_id() {
        let server = MockServer::start().await;
        let km = test_manager(&server, "aaaa", "test-token");

        let result = km
            .unwrap_key(b"whatever", "cabinet-A", "scaleway:some-other-key-id")
            .await;

        assert_eq!(result, Err(CryptoError::KeyUnwrap));
    }

    #[tokio::test]
    async fn wrap_key_maps_non_2xx_response_to_key_wrap_error() {
        let server = MockServer::start().await;
        let key_id = "22222222-2222-2222-2222-222222222222";

        Mock::given(method("POST"))
            .and(path(format!(
                "/key-manager/v1alpha1/regions/fr-par/keys/{key_id}/encrypt"
            )))
            .respond_with(ResponseTemplate::new(403))
            .mount(&server)
            .await;

        let km = test_manager(&server, key_id, "test-token");
        let result = km.wrap_key(&[1u8; 32], "cabinet-A").await;

        assert_eq!(result, Err(CryptoError::KeyWrap));
    }

    fn test_manager(
        server: &MockServer,
        key_id: &'static str,
        token: &str,
    ) -> ScalewayKeyManager<FixedResolver> {
        ScalewayKeyManager::new(
            reqwest::Client::new(),
            token,
            "fr-par",
            FixedResolver(key_id),
        )
        .with_api_root(server.uri())
    }
}
