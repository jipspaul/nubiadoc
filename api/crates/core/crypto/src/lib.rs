//! Chiffrement colonne par enveloppe (KMS Scaleway / local POC).
//!
//! Scaffold — l'implémentation arrive avec NUB-T3.

use thiserror::Error;

/// Erreur de chiffrement / déchiffrement.
#[derive(Debug, Error)]
pub enum CryptoError {
    #[error("chiffrement non implémenté")]
    NotImplemented,
}
