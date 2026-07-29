//! Garde partagée : Postgres `text`/`jsonb` refusent l'octet NUL (`0x00`),
//! mais une `String` Rust peut le contenir (passe `trim().is_empty()` sans
//! problème). Un champ texte utilisateur non filtré échoue au `bind()` SQL
//! avec une erreur masquée en `AppError::Internal` (500) au lieu du `422`
//! attendu sur un input malformé (#4394/#4397/#4410 : même défaut répété sur
//! une dizaine d'endpoints, lecture comme écriture).
//!
//! À appeler sur tout champ texte utilisateur (query param ou body) avant
//! son utilisation dans une requête SQL.

use crate::auth::AppError;

/// `422 validation_error` si `s` contient un octet NUL, sinon `Ok(())`.
pub fn reject_nul_byte(s: &str) -> Result<(), AppError> {
    if s.contains('\0') {
        return Err(AppError::ValidationError);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_nul_byte_anywhere_in_string() {
        assert!(reject_nul_byte("ab\0cd").is_err());
        assert!(reject_nul_byte("\0").is_err());
        assert!(reject_nul_byte("trailing\0").is_err());
    }

    #[test]
    fn accepts_strings_without_nul_byte() {
        assert!(reject_nul_byte("").is_ok());
        assert!(reject_nul_byte("détartrage").is_ok());
        assert!(reject_nul_byte("normal text 123").is_ok());
    }
}
