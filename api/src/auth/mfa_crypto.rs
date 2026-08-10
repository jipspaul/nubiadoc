//! Utilitaire de chiffrement du secret TOTP (MFA) via KMS (`core-crypto`).
//!
//! Contexte : `mfa_enrollment` (migration `0046`) prévoit un stockage
//! chiffré du secret TOTP (`secret_ciphertext BYTEA` + `secret_key_ref`),
//! mais aucun call site ne l'utilisait — le secret était persisté en clair
//! dans `app_user.totp_secret` (#4650). Ce module fournit la primitive de
//! chiffrement/déchiffrement pour `mfa_enrollment.secret_ciphertext` /
//! `secret_key_ref`, sur le même pattern que `interop::patient` pour
//! `patient_account.ins_ciphertext`.
//!
//! Câblé par `mfa_verify.rs` (persistance à l'enrôlement) et `login.rs`
//! (déchiffrement à la vérification du code TOTP au login), cf. #4652.

use core_crypto::{decrypt_column, encrypt_column, CryptoError, KeyManager};

/// Contexte d'enveloppement des secrets MFA — `mfa_enrollment` est une
/// entité plateforme (liée à `app_user`, pas à un `cabinet_id`, cf.
/// `db/migrations/0046_create_mfa_enrollment.sql`), donc un contexte fixe
/// non cabinet-scopé (même convention que `PLATFORM_KEY_CONTEXT` dans
/// `interop::patient`).
pub const MFA_KEY_CONTEXT: &str = "mfa_totp";

/// Chiffre `totp_secret` (Base32 en clair) pour stockage dans
/// `mfa_enrollment.secret_ciphertext` / `secret_key_ref`.
pub async fn encrypt_totp_secret(
    totp_secret: &str,
    key_manager: &dyn KeyManager,
) -> Result<(Vec<u8>, String), CryptoError> {
    let encrypted = encrypt_column(totp_secret.as_bytes(), key_manager, MFA_KEY_CONTEXT).await?;
    Ok((encrypted.ciphertext, encrypted.key_ref))
}

/// Déchiffre `secret_ciphertext`/`secret_key_ref` (lus depuis
/// `mfa_enrollment`) pour retrouver le secret TOTP Base32 en clair.
pub async fn decrypt_totp_secret(
    secret_ciphertext: &[u8],
    secret_key_ref: &str,
    key_manager: &dyn KeyManager,
) -> Result<String, CryptoError> {
    let plaintext = decrypt_column(
        secret_ciphertext,
        key_manager,
        MFA_KEY_CONTEXT,
        secret_key_ref,
    )
    .await?;
    String::from_utf8(plaintext).map_err(|_| CryptoError::MalformedCiphertext)
}

#[cfg(test)]
mod tests {
    use super::*;
    use core_crypto::LocalKeyManager;

    #[tokio::test]
    async fn round_trips_a_totp_secret_through_encrypt_then_decrypt() {
        let km = LocalKeyManager::new([3u8; 32], "test-v1");
        let secret = "HGXBQD7ZPXEFT7ICVL7MP7SJGEFOM3QP";

        let (ciphertext, key_ref) = encrypt_totp_secret(secret, &km).await.unwrap();
        let decrypted = decrypt_totp_secret(&ciphertext, &key_ref, &km)
            .await
            .unwrap();

        assert_eq!(decrypted, secret);
    }

    #[tokio::test]
    async fn tampered_ciphertext_fails_to_decrypt() {
        let km = LocalKeyManager::new([3u8; 32], "test-v1");
        let (mut ciphertext, key_ref) = encrypt_totp_secret("SOMESECRET", &km).await.unwrap();
        let last = ciphertext.len() - 1;
        ciphertext[last] ^= 0xFF;

        let result = decrypt_totp_secret(&ciphertext, &key_ref, &km).await;

        assert!(result.is_err());
    }
}
