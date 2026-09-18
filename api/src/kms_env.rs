//! Résolution de la clé maître KMS locale (`KMS_MASTER_KEY`, 32 octets en
//! base64) — point unique pour tous les call sites qui construisent un
//! [`LocalKeyManager`] (`auth::mfa_verify`, `auth::login`, `data_import`,
//! `interop::patient`, `hl7v2::adt`).
//!
//! Contexte (#6980 / #7216) : chaque module dupliquait un
//! `key_manager_from_env()` qui aplatissait « variable absente », « pas du
//! base64 » et « mauvaise longueur » en un même `Internal` muet. Sur le LXC
//! de test, `KMS_MASTER_KEY` n'était jamais transmise au conteneur
//! (`infra/deploy/deploy.sh`, même trou de plomberie que #5688/#6250), donc
//! `POST /v1/auth/mfa/verify` répondait `500 internal_error` sur tout code
//! TOTP **valide** — et personne ne pouvait activer la MFA — sans qu'aucun
//! log ne nomme la cause.
//!
//! Deux garde-fous :
//! - [`check_env`] est appelé au démarrage (`main.rs`) : une clé absente ou
//!   mal formée fait échouer le boot avec un message explicite, plutôt
//!   qu'un 500 découvert à l'usage sur la dernière marche du parcours MFA ;
//! - les handlers mappent [`KmsConfigError`] sur une erreur HTTP explicite
//!   (`503 kms_not_configured`, cf. `AppError::KmsNotConfigured`) et loguent
//!   la cause — défense en profondeur pour les routeurs construits sans
//!   passer par `main.rs` (tests d'intégration).
//!
//! Jamais de fallback en clair ni de clé par défaut : sans clé valide, rien
//! n'est chiffré (donc rien n'est persisté), fail-closed.

use base64::{engine::general_purpose::STANDARD, Engine};
use core_crypto::LocalKeyManager;

/// Nom de la variable d'environnement portant la clé maître (base64, 32 octets).
pub const MASTER_KEY_VAR: &str = "KMS_MASTER_KEY";
/// Nom de la variable d'environnement portant l'étiquette de version de clé
/// (incluse dans `key_ref`, à incrémenter lors d'une rotation). Défaut `v1`.
pub const KEY_VERSION_VAR: &str = "KMS_KEY_VERSION";

const MASTER_KEY_LEN: usize = 32;

/// Pourquoi la clé maître KMS n'est pas exploitable. Le message `Display`
/// est destiné aux logs serveur et au message de refus de démarrage — il
/// ne contient jamais la valeur de la variable.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum KmsConfigError {
    #[error("{MASTER_KEY_VAR} absente de l'environnement")]
    Missing,
    #[error("{MASTER_KEY_VAR} vide")]
    Empty,
    #[error("{MASTER_KEY_VAR} n'est pas du base64 standard valide")]
    NotBase64,
    #[error("{MASTER_KEY_VAR} décode sur {0} octets ({MASTER_KEY_LEN} attendus)")]
    BadLength(usize),
}

/// Décode une valeur brute de `KMS_MASTER_KEY` en clé de 32 octets.
pub fn parse_master_key(raw: &str) -> Result<[u8; MASTER_KEY_LEN], KmsConfigError> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(KmsConfigError::Empty);
    }
    let decoded = STANDARD
        .decode(trimmed)
        .map_err(|_| KmsConfigError::NotBase64)?;
    let len = decoded.len();
    decoded
        .try_into()
        .map_err(|_| KmsConfigError::BadLength(len))
}

fn master_key_from_env() -> Result<[u8; MASTER_KEY_LEN], KmsConfigError> {
    let raw = std::env::var(MASTER_KEY_VAR).map_err(|_| KmsConfigError::Missing)?;
    parse_master_key(&raw)
}

/// Construit le [`LocalKeyManager`] (POC/dev, `KMS_DRIVER=local`) depuis
/// `KMS_MASTER_KEY` / `KMS_KEY_VERSION`.
pub fn key_manager_from_env() -> Result<LocalKeyManager, KmsConfigError> {
    let key = master_key_from_env()?;
    Ok(LocalKeyManager::new(
        key,
        std::env::var(KEY_VERSION_VAR).unwrap_or_else(|_| "v1".to_string()),
    ))
}

/// Vérification fail-fast au démarrage : la clé doit être présente et bien
/// formée, sinon le process ne doit pas servir de trafic (cf. `main.rs`).
pub fn check_env() -> Result<(), KmsConfigError> {
    master_key_from_env().map(|_| ())
}

/// Message d'aide affiché quand le démarrage est refusé — comment générer
/// une clé conforme.
pub const GENERATE_HINT: &str =
    "générer une clé : `head -c 32 /dev/urandom | base64` (ou `openssl rand -base64 32`)";

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_32_byte_base64_key() {
        let raw = STANDARD.encode([9u8; 32]);
        assert_eq!(parse_master_key(&raw), Ok([9u8; 32]));
        // Espaces/retour à la ligne de fin (secret collé depuis un fichier) tolérés.
        assert_eq!(parse_master_key(&format!("{raw}\n")), Ok([9u8; 32]));
    }

    #[test]
    fn rejects_empty_value() {
        assert_eq!(parse_master_key(""), Err(KmsConfigError::Empty));
        assert_eq!(parse_master_key("   \n"), Err(KmsConfigError::Empty));
    }

    #[test]
    fn rejects_non_base64() {
        assert_eq!(
            parse_master_key("pas-du-base64!"),
            Err(KmsConfigError::NotBase64)
        );
    }

    #[test]
    fn rejects_wrong_length() {
        let raw = STANDARD.encode([1u8; 16]);
        assert_eq!(parse_master_key(&raw), Err(KmsConfigError::BadLength(16)));
    }

    #[test]
    fn error_messages_never_leak_the_value() {
        let msg = KmsConfigError::BadLength(16).to_string();
        assert!(msg.contains("KMS_MASTER_KEY"));
        assert!(msg.contains("32 attendus"));
    }
}
