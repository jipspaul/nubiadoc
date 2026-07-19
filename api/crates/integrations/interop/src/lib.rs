//! Socle auth partenaire (lot A1) : modèle de scopes OAuth2 (`client_credentials`)
//! et helpers argon2 pour le hachage des secrets `interop_client_secret`.
//!
//! Volontairement sans dépendance Axum : une future brique HL7v2 (hors HTTP,
//! écoute TCP/MLLP) pourra réutiliser cette couche service sans tirer un
//! framework web. La couche HTTP (extracteur JWT, handler token endpoint)
//! vit dans `api/src/interop/`.

#![forbid(unsafe_code)]

use std::fmt;
use std::str::FromStr;

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use thiserror::Error;

/// Scope OAuth2 partenaire — périmètre lot A1 uniquement. Les ressources
/// FHIR (Patient/Appointment/Slot/...) associées à chaque scope sont
/// implémentées par des lots séparés qui dépendent de ce socle.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Scope {
    AppointmentsRead,
    AppointmentsWrite,
    PatientsRead,
    DirectoryRead,
    SlotsRead,
    SubscriptionsWrite,
}

impl Scope {
    /// Tous les scopes connus — utile pour valider/lister côté provisioning.
    pub const ALL: [Scope; 6] = [
        Scope::AppointmentsRead,
        Scope::AppointmentsWrite,
        Scope::PatientsRead,
        Scope::DirectoryRead,
        Scope::SlotsRead,
        Scope::SubscriptionsWrite,
    ];

    /// Représentation OAuth2 canonique (`resource:action`).
    pub fn as_str(&self) -> &'static str {
        match self {
            Scope::AppointmentsRead => "appointments:read",
            Scope::AppointmentsWrite => "appointments:write",
            Scope::PatientsRead => "patients:read",
            Scope::DirectoryRead => "directory:read",
            Scope::SlotsRead => "slots:read",
            Scope::SubscriptionsWrite => "subscriptions:write",
        }
    }
}

impl fmt::Display for Scope {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Scope inconnu rencontré lors du parsing d'une chaîne `scope` OAuth2.
#[derive(Debug, Error, Clone, PartialEq, Eq)]
#[error("scope inconnu : {0}")]
pub struct UnknownScope(pub String);

impl FromStr for Scope {
    type Err = UnknownScope;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "appointments:read" => Ok(Scope::AppointmentsRead),
            "appointments:write" => Ok(Scope::AppointmentsWrite),
            "patients:read" => Ok(Scope::PatientsRead),
            "directory:read" => Ok(Scope::DirectoryRead),
            "slots:read" => Ok(Scope::SlotsRead),
            "subscriptions:write" => Ok(Scope::SubscriptionsWrite),
            other => Err(UnknownScope(other.to_string())),
        }
    }
}

/// Parse une chaîne de scopes séparés par des espaces (format OAuth2 standard,
/// RFC 6749 §3.3). Un seul scope inconnu fait échouer tout le parsing —
/// fail-closed : on ne veut jamais accorder silencieusement un sous-ensemble.
pub fn parse_scopes(raw: &str) -> Result<Vec<Scope>, UnknownScope> {
    raw.split_whitespace().map(Scope::from_str).collect()
}

/// Sérialise une liste de scopes au format OAuth2 (espace-séparé).
pub fn scopes_to_string(scopes: &[Scope]) -> String {
    scopes
        .iter()
        .map(Scope::as_str)
        .collect::<Vec<_>>()
        .join(" ")
}

/// Erreur de hachage d'un secret client.
#[derive(Debug, Error)]
pub enum SecretError {
    #[error("échec du hachage du secret")]
    HashFailed,
}

/// Hache un `client_secret` partenaire avec argon2 — jamais stocké en clair
/// (colonne `interop_client_secret.secret_hash`).
pub fn hash_secret(secret: &str) -> Result<String, SecretError> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(secret.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|_| SecretError::HashFailed)
}

/// Vérifie un `client_secret` contre un hash argon2 stocké.
///
/// Retourne `false` (jamais d'erreur) si le hash stocké est malformé —
/// fail-closed : un hash corrompu en base ne doit jamais être traité comme
/// une authentification réussie.
pub fn verify_secret(secret: &str, stored_hash: &str) -> bool {
    let Ok(parsed) = PasswordHash::new(stored_hash) else {
        return false;
    };
    Argon2::default()
        .verify_password(secret.as_bytes(), &parsed)
        .is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_and_verify_roundtrip() {
        let hash = hash_secret("s3cr3t-partner-key").expect("hash should succeed");
        assert!(verify_secret("s3cr3t-partner-key", &hash));
    }

    #[test]
    fn verify_secret_rejects_wrong_secret() {
        let hash = hash_secret("correct-secret").expect("hash should succeed");
        assert!(!verify_secret("wrong-secret", &hash));
    }

    #[test]
    fn verify_secret_rejects_malformed_hash() {
        assert!(!verify_secret("anything", "not-a-valid-argon2-hash"));
    }

    #[test]
    fn parse_scopes_roundtrip() {
        let scopes = parse_scopes("appointments:read directory:read").unwrap();
        assert_eq!(scopes, vec![Scope::AppointmentsRead, Scope::DirectoryRead]);
        assert_eq!(
            scopes_to_string(&scopes),
            "appointments:read directory:read"
        );
    }

    #[test]
    fn parse_scopes_rejects_unknown_scope() {
        let err = parse_scopes("appointments:read bogus:scope").unwrap_err();
        assert_eq!(err, UnknownScope("bogus:scope".to_string()));
    }

    #[test]
    fn parse_scopes_empty_string_yields_empty_vec() {
        assert_eq!(parse_scopes("").unwrap(), Vec::<Scope>::new());
    }

    #[test]
    fn scope_subset_check() {
        let granted = parse_scopes("appointments:read directory:read").unwrap();
        let requested_ok = parse_scopes("appointments:read").unwrap();
        assert!(requested_ok.iter().all(|s| granted.contains(s)));

        let requested_escalation = parse_scopes("appointments:write").unwrap();
        assert!(!requested_escalation.iter().all(|s| granted.contains(s)));
    }
}
