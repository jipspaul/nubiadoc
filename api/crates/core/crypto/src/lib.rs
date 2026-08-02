//! Chiffrement colonne par enveloppe (KMS Scaleway / local POC).
//!
//! Quoi : chiffre/déchiffre une valeur (`bytea` stocké en base) par
//! enveloppe — une clé de données (DEK) aléatoire par valeur chiffre le
//! contenu en AES-256-GCM, la DEK elle-même est enveloppée ("wrap") par une
//! clé maître gérée par un [`KeyManager`] pluggable. Couvre tout champ
//! `*_ciphertext`/`*_key_ref` du modèle (`clinical_note`, `medical_record`,
//! `message`, `patient_account.nss/ins`…) — cf. `docs/05-modele-de-donnees.md` §3.
//!
//! Quand : à l'écriture/lecture de ces colonnes, une fois branché dans les
//! handlers (`api/src/*.rs`) — ce crate fournit la primitive, PAS le
//! câblage : les call sites qui utilisent aujourd'hui le stub
//! `STUB_ENC:`/`STUB_DEC:` (`clinical.rs`, `medical_record.rs`,
//! `messaging.rs`, `documents.rs`, `auth/mod.rs`…) restent inchangés par ce
//! commit — migrer chaque call site est un chantier séparé (données
//! existantes en stub à re-chiffrer, un PR par domaine).
//!
//! Pourquoi cette approche : chiffrement enveloppe (DEK par valeur, wrap
//! par une clé maître par contexte) plutôt qu'un chiffrement direct par la
//! clé maître — la clé maître n'est jamais utilisée pour chiffrer des
//! données en volume (seulement pour wrapper de petites DEK de 32 octets),
//! et la rotation de clé maître se fait en ré-enveloppant les DEK sans
//! re-chiffrer chaque valeur. Pattern KMS standard (AWS/GCP/Scaleway
//! envelope encryption). Backend AEAD `ring` (déjà résolu dans le
//! workspace via rustls/tokio-rustls, cf. `integrations-hl7v2/Cargo.toml`
//! pour le choix face à `aws-lc-rs`) plutôt qu'une dépendance `aes-gcm`
//! séparée.
//!
//! Modes d'échec : [`CryptoError`] — jamais de panic, jamais de fallback
//! silencieux vers du texte en clair. Un ciphertext altéré, une clé
//! erronée ou un `key_context` incohérent (ex. tenter de déchiffrer sous
//! le mauvais cabinet) échouent explicitement (tag AEAD invalide).

mod key_manager;
mod local;
mod scaleway;

pub use key_manager::KeyManager;
pub use local::LocalKeyManager;
pub use scaleway::{KeyResolver, ScalewayKeyManager};

use ring::aead;
use ring::rand::{SecureRandom, SystemRandom};
use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum CryptoError {
    #[error("échec de génération aléatoire")]
    Rng,
    #[error("échec de chiffrement")]
    Encrypt,
    #[error("échec de déchiffrement (clé/ciphertext invalide ou altéré)")]
    Decrypt,
    #[error("échec d'enveloppement de clé (KMS)")]
    KeyWrap,
    #[error("échec de désenveloppement de clé (KMS)")]
    KeyUnwrap,
    #[error("ciphertext mal formé (longueur/format invalide)")]
    MalformedCiphertext,
}

const DEK_LEN: usize = 32; // AES-256
const NONCE_LEN: usize = 12; // GCM standard (96 bits)

/// Résultat d'un chiffrement colonne.
///
/// - `ciphertext` : à stocker dans la colonne `bytea` (ex. `content_ciphertext`).
/// - `key_ref` : à stocker dans la colonne `text` associée (ex.
///   `content_key_ref`) — identifie QUELLE clé maître/version a servi à
///   envelopper la DEK (pour la rotation), jamais la clé elle-même : la DEK
///   enveloppée est packée à l'intérieur de `ciphertext`.
pub struct Encrypted {
    pub ciphertext: Vec<u8>,
    pub key_ref: String,
}

/// Chiffre `plaintext` par enveloppe sous `key_context` (ex. `cabinet_id`,
/// ou `"platform"` pour une donnée non cabinet-scopée comme
/// `patient_account.nss_ciphertext`).
///
/// Format de `Encrypted::ciphertext` : `nonce(12) || wrapped_dek_len(u16 BE)
/// || wrapped_dek || aead_ciphertext_of(plaintext, DEK, nonce)`.
pub async fn encrypt_column(
    plaintext: &[u8],
    key_manager: &dyn KeyManager,
    key_context: &str,
) -> Result<Encrypted, CryptoError> {
    let rng = SystemRandom::new();

    let mut dek_bytes = [0u8; DEK_LEN];
    rng.fill(&mut dek_bytes).map_err(|_| CryptoError::Rng)?;

    let mut nonce_bytes = [0u8; NONCE_LEN];
    rng.fill(&mut nonce_bytes).map_err(|_| CryptoError::Rng)?;

    let unbound_key =
        aead::UnboundKey::new(&aead::AES_256_GCM, &dek_bytes).map_err(|_| CryptoError::Encrypt)?;
    let key = aead::LessSafeKey::new(unbound_key);
    let nonce = aead::Nonce::assume_unique_for_key(nonce_bytes);

    let mut in_out = plaintext.to_vec();
    key.seal_in_place_append_tag(nonce, aead::Aad::empty(), &mut in_out)
        .map_err(|_| CryptoError::Encrypt)?;

    let wrap_result = key_manager.wrap_key(&dek_bytes, key_context).await;
    dek_bytes.iter_mut().for_each(|b| *b = 0); // best-effort zeroize
    let (wrapped_dek, key_ref) = wrap_result.map_err(|_| CryptoError::KeyWrap)?;

    if wrapped_dek.len() > u16::MAX as usize {
        return Err(CryptoError::KeyWrap);
    }
    let mut stored = Vec::with_capacity(NONCE_LEN + 2 + wrapped_dek.len() + in_out.len());
    stored.extend_from_slice(&nonce_bytes);
    stored.extend_from_slice(&(wrapped_dek.len() as u16).to_be_bytes());
    stored.extend_from_slice(&wrapped_dek);
    stored.extend_from_slice(&in_out);

    Ok(Encrypted {
        ciphertext: stored,
        key_ref,
    })
}

/// Déchiffre un ciphertext produit par [`encrypt_column`]. `key_context`
/// doit être identique à celui utilisé au chiffrement (ex. le `cabinet_id`
/// courant) — un contexte différent échoue en [`CryptoError::KeyUnwrap`],
/// jamais de désenveloppement silencieux sous un mauvais contexte.
pub async fn decrypt_column(
    ciphertext: &[u8],
    key_manager: &dyn KeyManager,
    key_context: &str,
    key_ref: &str,
) -> Result<Vec<u8>, CryptoError> {
    if ciphertext.len() < NONCE_LEN + 2 {
        return Err(CryptoError::MalformedCiphertext);
    }
    let (nonce_bytes, rest) = ciphertext.split_at(NONCE_LEN);
    let (wrapped_len_bytes, rest) = rest.split_at(2);
    let wrapped_len = u16::from_be_bytes([wrapped_len_bytes[0], wrapped_len_bytes[1]]) as usize;
    if rest.len() < wrapped_len {
        return Err(CryptoError::MalformedCiphertext);
    }
    let (wrapped_dek, aead_ciphertext) = rest.split_at(wrapped_len);

    let dek_bytes = key_manager
        .unwrap_key(wrapped_dek, key_context, key_ref)
        .await
        .map_err(|_| CryptoError::KeyUnwrap)?;

    let unbound_key =
        aead::UnboundKey::new(&aead::AES_256_GCM, &dek_bytes).map_err(|_| CryptoError::Decrypt)?;
    let key = aead::LessSafeKey::new(unbound_key);
    let nonce_arr: [u8; NONCE_LEN] = nonce_bytes
        .try_into()
        .map_err(|_| CryptoError::MalformedCiphertext)?;
    let nonce = aead::Nonce::assume_unique_for_key(nonce_arr);

    let mut in_out = aead_ciphertext.to_vec();
    let plaintext = key
        .open_in_place(nonce, aead::Aad::empty(), &mut in_out)
        .map_err(|_| CryptoError::Decrypt)?;

    Ok(plaintext.to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn round_trips_through_local_key_manager() {
        let km = LocalKeyManager::new([7u8; 32], "test-v1");
        let plaintext = b"donnee clinique sensible";

        let enc = encrypt_column(plaintext, &km, "cabinet-A").await.unwrap();
        let dec = decrypt_column(&enc.ciphertext, &km, "cabinet-A", &enc.key_ref)
            .await
            .unwrap();

        assert_eq!(dec, plaintext);
    }

    #[tokio::test]
    async fn wrong_key_context_fails_to_decrypt() {
        let km = LocalKeyManager::new([7u8; 32], "test-v1");
        let enc = encrypt_column(b"secret", &km, "cabinet-A").await.unwrap();

        let result = decrypt_column(&enc.ciphertext, &km, "cabinet-B", &enc.key_ref).await;

        assert_eq!(result, Err(CryptoError::KeyUnwrap));
    }

    #[tokio::test]
    async fn tampered_ciphertext_fails_to_decrypt() {
        let km = LocalKeyManager::new([7u8; 32], "test-v1");
        let mut enc = encrypt_column(b"secret", &km, "cabinet-A").await.unwrap();
        let last = enc.ciphertext.len() - 1;
        enc.ciphertext[last] ^= 0xFF; // flip a bit in the AEAD tag/ciphertext

        let result = decrypt_column(&enc.ciphertext, &km, "cabinet-A", &enc.key_ref).await;

        assert_eq!(result, Err(CryptoError::Decrypt));
    }

    #[tokio::test]
    async fn malformed_ciphertext_is_rejected_without_panicking() {
        let km = LocalKeyManager::new([7u8; 32], "test-v1");

        let result = decrypt_column(&[0u8; 3], &km, "cabinet-A", "local:test-v1").await;

        assert_eq!(result, Err(CryptoError::MalformedCiphertext));
    }

    #[tokio::test]
    async fn two_encryptions_of_the_same_plaintext_differ() {
        // Nonce aléatoire par appel : deux chiffrements de la même valeur ne
        // doivent jamais produire le même ciphertext (sinon fuite d'égalité).
        let km = LocalKeyManager::new([7u8; 32], "test-v1");
        let a = encrypt_column(b"secret", &km, "cabinet-A").await.unwrap();
        let b = encrypt_column(b"secret", &km, "cabinet-A").await.unwrap();

        assert_ne!(a.ciphertext, b.ciphertext);
    }
}
