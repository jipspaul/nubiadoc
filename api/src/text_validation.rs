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

/// `422 validation_error` si une chaîne quelconque du JSON (clé ou valeur,
/// à toute profondeur) contient un octet NUL, sinon `Ok(())`. Pour les
/// champs `payload: Value` libres (JSONB) où `reject_nul_byte` seul ne
/// couvre pas le contenu imbriqué (#4809).
pub fn reject_nul_byte_in_json(value: &serde_json::Value) -> Result<(), AppError> {
    match value {
        serde_json::Value::String(s) => reject_nul_byte(s),
        serde_json::Value::Array(items) => {
            for item in items {
                reject_nul_byte_in_json(item)?;
            }
            Ok(())
        }
        serde_json::Value::Object(map) => {
            for (key, val) in map {
                reject_nul_byte(key)?;
                reject_nul_byte_in_json(val)?;
            }
            Ok(())
        }
        _ => Ok(()),
    }
}

/// `422 validation_error` si `s` compte plus de `max_chars` caractères
/// Unicode (pas les octets — cf. `body.first_name.chars().count() > 100`,
/// `auth/mod.rs:4497`), sinon `Ok(())`. Les endpoints d'écriture clinique et
/// facturation bornaient déjà le vide (`trim().is_empty()`) mais jamais le
/// haut : un libellé de 20 000 caractères traversait jusqu'au PDF signé
/// (ordonnance, devis) sans césure ni retour à la ligne, illisible et hors
/// page (#7226, suite de #7138/#7041).
pub fn validate_max_len(s: &str, max_chars: usize) -> Result<(), AppError> {
    if s.chars().count() > max_chars {
        return Err(AppError::ValidationError);
    }
    Ok(())
}

/// Convertit un numéro français saisi au format national (`0X…`, espaces/points/tirets
/// tolérés — `06 12 34 00 86`) vers l'E.164 (`+33X…`) qu'attend `validate_phone_format`.
/// Aucun des trois formulaires appelants (tunnel SSR, profil patient, fiche cabinet)
/// n'indique le format E.164 à l'utilisateur ; en pratique tout visiteur français tape
/// du `0X…`, systématiquement rejeté avant ce correctif (#7436). La contrainte E.164
/// elle-même (#7081) n'est pas retirée : seule la saisie nationale est tolérée en plus,
/// tout le reste (déjà en E.164, ou pas un numéro français) traverse inchangé et sera
/// validé — ou rejeté — tel quel par `validate_phone_format`.
pub fn normalize_phone_format(phone: &str) -> String {
    let stripped: String = phone
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '.' && *c != '-')
        .collect();
    match stripped.strip_prefix('0') {
        Some(rest) if !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit()) => {
            format!("+33{rest}")
        }
        _ => stripped,
    }
}

/// `422 validation_error` si `phone` n'est pas un numéro E.164 valide (`+` suivi de
/// 7 à 14 chiffres), sinon `Ok(())`. Même borne que `PATCH /v1/account` — extraite
/// ici pour être partagée avec `POST /v1/cabinet/patients/quick` (#7079 : ce dernier
/// acceptait n'importe quelle chaîne, y compris du HTML, dans `phone`). Les appelants
/// doivent passer le résultat de `normalize_phone_format` (#7436), pas la saisie brute.
pub fn validate_phone_format(phone: &str) -> Result<(), AppError> {
    let digits = phone.strip_prefix('+').unwrap_or("");
    if digits.is_empty()
        || digits.len() < 7
        || digits.len() > 14
        || !digits.chars().all(|c| c.is_ascii_digit())
    {
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

    #[test]
    fn validates_max_len() {
        assert!(validate_max_len("détartrage", 20).is_ok());
        assert!(validate_max_len(&"a".repeat(20), 20).is_ok());
        assert!(validate_max_len(&"a".repeat(21), 20).is_err());
        assert!(validate_max_len(&"é".repeat(21), 20).is_err());
    }

    #[test]
    fn normalizes_french_national_format_to_e164() {
        assert_eq!(normalize_phone_format("0612340086"), "+33612340086");
        assert_eq!(normalize_phone_format("06 12 34 00 86"), "+33612340086");
        assert_eq!(normalize_phone_format("06.12.34.00.86"), "+33612340086");
        assert_eq!(normalize_phone_format("06-12-34-00-86"), "+33612340086");
        assert_eq!(normalize_phone_format("+33612340086"), "+33612340086");
        assert_eq!(normalize_phone_format("pas-un-telephone"), "pasuntelephone");
        assert!(validate_phone_format(&normalize_phone_format("0612340086")).is_ok());
        assert!(validate_phone_format(&normalize_phone_format("06 12 34 00 86")).is_ok());
    }

    #[test]
    fn validates_e164_phone_format() {
        assert!(validate_phone_format("+33612345678").is_ok());
        assert!(validate_phone_format("+1234567").is_ok());
        assert!(validate_phone_format("pas-un-telephone").is_err());
        assert!(validate_phone_format("<script>alert(1)</script>").is_err());
        assert!(validate_phone_format("+++++").is_err());
        assert!(validate_phone_format(&"0".repeat(300)).is_err());
        assert!(validate_phone_format("2099-13-45").is_err());
        assert!(validate_phone_format("+123").is_err());
    }
}
