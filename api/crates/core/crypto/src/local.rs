//! [`KeyManager`] local (POC/dev, `KMS_DRIVER=local` — cf.
//! `infra/poc/compose.yml`) : dérive une clé de wrap par contexte via
//! HKDF-SHA256 depuis une clé maître unique en mémoire (chargée par
//! l'appelant depuis `KMS_MASTER_KEY`), puis enveloppe la DEK par
//! AES-256-GCM avec cette clé dérivée.
//!
//! AUCUNE protection HSM/KMS réelle : la clé maître vit en mémoire process,
//! dérivée localement — usage POC/dev/staging uniquement. En production,
//! utiliser [`crate::ScalewayKeyManager`].

use ring::aead;
use ring::hkdf;
use ring::rand::{SecureRandom, SystemRandom};

use crate::{CryptoError, KeyManager};

const WRAP_NONCE_LEN: usize = 12;
const HKDF_INFO: &[u8] = b"nubia-core-crypto-local-wrap-v1";

pub struct LocalKeyManager {
    master_key: [u8; 32],
    key_version: String,
}

impl LocalKeyManager {
    /// `master_key` : 32 octets (ex. décodés depuis `KMS_MASTER_KEY`,
    /// base64, résolu par l'appelant — ce crate ne lit aucune variable
    /// d'environnement lui-même). `key_version` : étiquette incluse dans
    /// `key_ref`, à incrémenter lors d'une rotation de `KMS_MASTER_KEY`.
    pub fn new(master_key: [u8; 32], key_version: impl Into<String>) -> Self {
        Self {
            master_key,
            key_version: key_version.into(),
        }
    }

    fn key_ref(&self) -> String {
        format!("local:{}", self.key_version)
    }

    /// Dérive une clé de wrap AES-256 spécifique à `key_context` via
    /// HKDF-SHA256(salt=key_context, ikm=master_key) — deux contextes
    /// différents ne peuvent jamais dériver la même clé de wrap.
    fn derive_wrap_key(&self, key_context: &str) -> Result<aead::LessSafeKey, CryptoError> {
        let salt = hkdf::Salt::new(hkdf::HKDF_SHA256, key_context.as_bytes());
        let prk = salt.extract(&self.master_key);
        let okm = prk
            .expand(&[HKDF_INFO], hkdf::HKDF_SHA256)
            .map_err(|_| CryptoError::KeyWrap)?;
        let mut derived = [0u8; 32];
        okm.fill(&mut derived).map_err(|_| CryptoError::KeyWrap)?;
        let unbound =
            aead::UnboundKey::new(&aead::AES_256_GCM, &derived).map_err(|_| CryptoError::KeyWrap)?;
        Ok(aead::LessSafeKey::new(unbound))
    }
}

#[async_trait::async_trait]
impl KeyManager for LocalKeyManager {
    async fn wrap_key(
        &self,
        dek: &[u8; 32],
        key_context: &str,
    ) -> Result<(Vec<u8>, String), CryptoError> {
        let wrap_key = self.derive_wrap_key(key_context)?;
        let rng = SystemRandom::new();
        let mut nonce_bytes = [0u8; WRAP_NONCE_LEN];
        rng.fill(&mut nonce_bytes).map_err(|_| CryptoError::Rng)?;
        let nonce = aead::Nonce::assume_unique_for_key(nonce_bytes);

        let mut in_out = dek.to_vec();
        wrap_key
            .seal_in_place_append_tag(nonce, aead::Aad::empty(), &mut in_out)
            .map_err(|_| CryptoError::KeyWrap)?;

        let mut wrapped = Vec::with_capacity(WRAP_NONCE_LEN + in_out.len());
        wrapped.extend_from_slice(&nonce_bytes);
        wrapped.extend_from_slice(&in_out);
        Ok((wrapped, self.key_ref()))
    }

    async fn unwrap_key(
        &self,
        wrapped_dek: &[u8],
        key_context: &str,
        key_ref: &str,
    ) -> Result<[u8; 32], CryptoError> {
        if key_ref != self.key_ref() {
            return Err(CryptoError::KeyUnwrap);
        }
        if wrapped_dek.len() < WRAP_NONCE_LEN {
            return Err(CryptoError::MalformedCiphertext);
        }
        let (nonce_bytes, aead_bytes) = wrapped_dek.split_at(WRAP_NONCE_LEN);
        let wrap_key = self.derive_wrap_key(key_context)?;
        let nonce_arr: [u8; WRAP_NONCE_LEN] = nonce_bytes
            .try_into()
            .map_err(|_| CryptoError::MalformedCiphertext)?;
        let nonce = aead::Nonce::assume_unique_for_key(nonce_arr);

        let mut in_out = aead_bytes.to_vec();
        let plain = wrap_key
            .open_in_place(nonce, aead::Aad::empty(), &mut in_out)
            .map_err(|_| CryptoError::KeyUnwrap)?;

        plain.try_into().map_err(|_| CryptoError::KeyUnwrap)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn wrap_then_unwrap_returns_the_original_dek() {
        let km = LocalKeyManager::new([1u8; 32], "v1");
        let dek = [42u8; 32];

        let (wrapped, key_ref) = km.wrap_key(&dek, "cabinet-A").await.unwrap();
        let unwrapped = km.unwrap_key(&wrapped, "cabinet-A", &key_ref).await.unwrap();

        assert_eq!(unwrapped, dek);
    }

    #[tokio::test]
    async fn different_master_keys_derive_different_wrap_keys() {
        let km_a = LocalKeyManager::new([1u8; 32], "v1");
        let km_b = LocalKeyManager::new([2u8; 32], "v1");
        let dek = [42u8; 32];

        let (wrapped, key_ref) = km_a.wrap_key(&dek, "cabinet-A").await.unwrap();
        let result = km_b.unwrap_key(&wrapped, "cabinet-A", &key_ref).await;

        assert_eq!(result, Err(CryptoError::KeyUnwrap));
    }

    #[tokio::test]
    async fn stale_key_ref_is_rejected() {
        let km = LocalKeyManager::new([1u8; 32], "v2");
        let dek = [42u8; 32];
        let (wrapped, _) = km.wrap_key(&dek, "cabinet-A").await.unwrap();

        let result = km.unwrap_key(&wrapped, "cabinet-A", "local:v1").await;

        assert_eq!(result, Err(CryptoError::KeyUnwrap));
    }
}
