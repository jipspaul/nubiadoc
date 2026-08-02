//! Port : enveloppement/désenveloppement d'une clé de données (DEK) sous
//! une clé maître identifiée par un contexte applicatif (ex. `cabinet_id`).
//!
//! Deux implémentations : [`crate::LocalKeyManager`] (dérivation HKDF
//! locale, POC/dev) et [`crate::ScalewayKeyManager`] (KMS Scaleway réel).

use crate::CryptoError;

#[async_trait::async_trait]
pub trait KeyManager: Send + Sync {
    /// Enveloppe `dek` (32 octets, AES-256) sous la clé maître résolue pour
    /// `key_context`. Retourne `(wrapped_dek, key_ref)` : `key_ref`
    /// identifie quelle clé maître/version a servi, pour permettre la
    /// rotation sans avoir à la deviner au désenveloppement.
    async fn wrap_key(
        &self,
        dek: &[u8; 32],
        key_context: &str,
    ) -> Result<(Vec<u8>, String), CryptoError>;

    /// Désenveloppe `wrapped_dek` sous `key_context`/`key_ref`. Échoue si
    /// `key_context` ou `key_ref` ne correspondent pas à ceux utilisés au
    /// wrap (mauvais cabinet, mauvaise version de clé).
    async fn unwrap_key(
        &self,
        wrapped_dek: &[u8],
        key_context: &str,
        key_ref: &str,
    ) -> Result<[u8; 32], CryptoError>;
}
