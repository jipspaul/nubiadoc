//! `StorageSigner` self-hébergé — sert les objets `ObjectStorage` (en
//! pratique `PostgresObjectStorage`, cf. `build_router` et #6453) via une URL
//! HMAC-signée, expirante, pointant sur `GET /v1/storage/local/*key` de cette
//! même API.
//!
//! Fallback pour les déploiements où `ScalewayStorageSigner` n'est pas
//! configuré (`SCW_ACCESS_KEY`/`SCW_SECRET_KEY`/`SCW_BUCKET` absentes) : le
//! plombage CI -> conteneur de ces variables (#6250) ne suffit pas tant
//! qu'aucun compte Scaleway n'a réellement été provisionné côté secrets
//! Forgejo — `signer.sign()` restait alors `None` indéfiniment, donc `GET
//! /v1/documents/:id` et `/download` répondaient `502 upstream_unavailable`
//! pour 100% des documents (#6425, récidive de #6250). Ce signer garantit un
//! coffre-fort lisible dès le boot, sans dépendance à un compte tiers non
//! configuré. `ScalewayStorageSigner` reste préféré dès que les `SCW_*` sont
//! renseignées (choix fait dans `main.rs`, pas ici).

use axum::{
    extract::{Extension, Path, Query},
    http::{header, StatusCode},
    response::{IntoResponse, Response},
};
use hmac::{Hmac, Mac};
use serde::Deserialize;
use sha2::Sha256;
use std::sync::Arc;

use crate::{ObjectStorage, StorageSigner};

type HmacSha256 = Hmac<Sha256>;

const DEFAULT_BASE_URL: &str = "http://127.0.0.1:3000";
const DEFAULT_SIGNING_KEY: &str = "dev-only-not-for-prod";
const TTL_SECS: i64 = 900;

pub struct LocalStorageSigner {
    base_url: String,
    signing_key: String,
}

impl LocalStorageSigner {
    /// `PUBLIC_API_BASE` (défaut `http://127.0.0.1:3000`, déjà calculé côté
    /// déploiement — cf. `infra/deploy/deploy.sh`) et `STORAGE_SIGNING_KEY`
    /// (défaut `dev-only-not-for-prod`, même convention que `JWT_SECRET`).
    pub fn from_env() -> Self {
        Self {
            base_url: std::env::var("PUBLIC_API_BASE")
                .unwrap_or_else(|_| DEFAULT_BASE_URL.to_string()),
            signing_key: std::env::var("STORAGE_SIGNING_KEY")
                .unwrap_or_else(|_| DEFAULT_SIGNING_KEY.to_string()),
        }
    }

    fn signature(&self, key: &str, expires_at: i64) -> String {
        let mut mac = HmacSha256::new_from_slice(self.signing_key.as_bytes())
            .expect("HMAC accepte n'importe quelle clé");
        mac.update(format!("{key}:{expires_at}").as_bytes());
        hex::encode(mac.finalize().into_bytes())
    }

    /// Revalide une signature reçue par `serve_local_object` — comparaison à
    /// temps constant, même pattern que les vérificateurs webhook
    /// (`webhooks/stripe.rs`, `webhooks/yousign.rs`).
    fn verify(&self, key: &str, expires_at: i64, signature: &str) -> bool {
        if chrono::Utc::now().timestamp() > expires_at {
            return false;
        }
        let expected = self.signature(key, expires_at);
        expected.len() == signature.len()
            && expected
                .bytes()
                .zip(signature.bytes())
                .fold(0u8, |acc, (a, b)| acc | (a ^ b))
                == 0
    }
}

impl StorageSigner for LocalStorageSigner {
    fn sign(&self, storage_key: &str) -> Option<String> {
        let expires_at = (chrono::Utc::now() + chrono::Duration::seconds(TTL_SECS)).timestamp();
        let sig = self.signature(storage_key, expires_at);
        Some(format!(
            "{}/v1/storage/local/{}?expires={}&sig={}",
            self.base_url, storage_key, expires_at, sig
        ))
    }
}

#[derive(Deserialize)]
pub struct LocalStorageQuery {
    expires: i64,
    sig: String,
}

/// `GET /v1/storage/local/*key` — sert l'objet signé par [`LocalStorageSigner`].
///
/// Pas d'auth par token porteur : la signature HMAC + expiration en tient
/// lieu, comme une URL S3 présignée réelle. Signature invalide/expirée ->
/// `403`. Objet jamais uploadé -> `404`.
pub async fn serve_local_object(
    Extension(signer): Extension<Arc<LocalStorageSigner>>,
    Extension(storage): Extension<Arc<dyn ObjectStorage>>,
    Path(key): Path<String>,
    Query(query): Query<LocalStorageQuery>,
) -> Response {
    if !signer.verify(&key, query.expires, &query.sig) {
        return StatusCode::FORBIDDEN.into_response();
    }

    match storage.download(&key).await {
        Some((content_type, bytes)) => (
            StatusCode::OK,
            [(header::CONTENT_TYPE, content_type)],
            bytes,
        )
            .into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sign_produces_a_local_url_with_expiry_and_signature() {
        let signer = LocalStorageSigner {
            base_url: "http://127.0.0.1:3000".to_string(),
            signing_key: "test-key".to_string(),
        };
        let url = signer.sign("ordonnance/abc.pdf").unwrap();
        assert!(url.starts_with("http://127.0.0.1:3000/v1/storage/local/ordonnance/abc.pdf?"));
        assert!(url.contains("expires="));
        assert!(url.contains("sig="));
    }

    #[test]
    fn verify_accepts_a_freshly_signed_url() {
        let signer = LocalStorageSigner {
            base_url: "http://127.0.0.1:3000".to_string(),
            signing_key: "test-key".to_string(),
        };
        let expires_at = (chrono::Utc::now() + chrono::Duration::seconds(60)).timestamp();
        let sig = signer.signature("some-key", expires_at);
        assert!(signer.verify("some-key", expires_at, &sig));
    }

    #[test]
    fn verify_rejects_a_tampered_signature() {
        let signer = LocalStorageSigner {
            base_url: "http://127.0.0.1:3000".to_string(),
            signing_key: "test-key".to_string(),
        };
        let expires_at = (chrono::Utc::now() + chrono::Duration::seconds(60)).timestamp();
        assert!(!signer.verify("some-key", expires_at, "deadbeef"));
    }

    #[test]
    fn verify_rejects_an_expired_url() {
        let signer = LocalStorageSigner {
            base_url: "http://127.0.0.1:3000".to_string(),
            signing_key: "test-key".to_string(),
        };
        let expires_at = (chrono::Utc::now() - chrono::Duration::seconds(1)).timestamp();
        let sig = signer.signature("some-key", expires_at);
        assert!(!signer.verify("some-key", expires_at, &sig));
    }
}
