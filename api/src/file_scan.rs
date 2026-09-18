//! Garde partagée des uploads : signature EICAR (stub antivirus) + nombre
//! magique du contenu (défense contre un `Content-Type` mensonger).
//!
//! Quoi : détection de la signature de test EICAR dans le contenu binaire
//! d'un fichier uploadé, refusée en `422` avant toute écriture en base ;
//! confrontation du nombre magique en tête de fichier au MIME *déclaré* par
//! le client, refusée en `422` en cas de désaccord.
//! Quand : à appeler par CHAQUE endpoint d'upload qui écrit dans `document`
//! (coffre-fort `POST /documents`, carte mutuelle `POST /account/coverage/card`,
//! dossier cabinet `POST /cabinet/patients/:id/documents`) — #4756 : la
//! défense était asymétrique entre deux endpoints écrivant dans la même
//! table ; #7302 : le seul contrôle de type portait sur le `Content-Type`
//! déclaré par le client, jamais sur le contenu — un exécutable renommé en
//! `.png` était accepté et re-servi sous ce faux type.
//! Pourquoi cette approche : le vrai scan antivirus est un stub à ce stade
//! (`scan_status = 'pending'`, ADR post-levée) ; la signature EICAR est le
//! standard de l'industrie pour tester le chemin de refus de bout en bout.
//! Le sniffing par nombre magique reste volontairement limité aux trois MIME
//! acceptés par ces endpoints (PDF/JPEG/PNG) — pas un détecteur générique.
//! Modes d'échec : détection EICAR par fenêtre glissante — un fichier
//! découpant la signature sur plusieurs chunks n'est pas détecté (accepté :
//! EICAR spécifie la chaîne contiguë en tête de fichier).

use crate::auth::AppError;

/// Signature EICAR (68 octets) — chaîne standard de test antivirus.
const EICAR_SIGNATURE: &[u8] =
    b"X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*";

/// `422 validation_error` si `bytes` contient la signature EICAR, sinon `Ok(())`.
pub fn reject_eicar(bytes: &[u8]) -> Result<(), AppError> {
    if bytes
        .windows(EICAR_SIGNATURE.len())
        .any(|w| w == EICAR_SIGNATURE)
    {
        return Err(AppError::ValidationError);
    }
    Ok(())
}

/// Déduit le MIME réel de `bytes` à partir de son nombre magique, parmi les
/// seuls types acceptés par les endpoints d'upload (PDF/JPEG/PNG). `None` si
/// aucune signature connue ne correspond en tête de fichier.
fn sniff_mime(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(b"%PDF-") {
        Some("application/pdf")
    } else if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some("image/jpeg")
    } else if bytes.starts_with(&[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
        Some("image/png")
    } else {
        None
    }
}

/// `422 validation_error` si le nombre magique de `bytes` ne correspond pas
/// à `declared_mime` (le `Content-Type` annoncé par le client dans le champ
/// multipart) — #7302 : sans cette garde, n'importe quel octet passait sous
/// n'importe lequel des MIME de l'allowlist.
pub fn verify_content_matches_declared_mime(
    bytes: &[u8],
    declared_mime: &str,
) -> Result<(), AppError> {
    match sniff_mime(bytes) {
        Some(sniffed) if sniffed == declared_mime => Ok(()),
        _ => Err(AppError::ValidationError),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_bytes_whose_magic_number_matches_the_declared_mime() {
        assert!(verify_content_matches_declared_mime(b"%PDF-1.4 ...", "application/pdf").is_ok());
        assert!(verify_content_matches_declared_mime(
            &[0xFF, 0xD8, 0xFF, 0xE0, 0, 0],
            "image/jpeg"
        )
        .is_ok());
        assert!(verify_content_matches_declared_mime(
            &[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0],
            "image/png"
        )
        .is_ok());
    }

    #[test]
    fn rejects_a_pe_executable_declared_as_png() {
        // En-tête DOS/PE ("MZ") — cf. #7302, l'exécutable de la repro.
        let pe_header = [0x4D, 0x5A, 0x90, 0x00, 0x00, 0x00];
        assert!(matches!(
            verify_content_matches_declared_mime(&pe_header, "image/png"),
            Err(AppError::ValidationError)
        ));
    }

    #[test]
    fn rejects_when_the_magic_number_does_not_match_the_declared_mime() {
        // Octets PNG réels mais déclarés comme PDF.
        let png_header = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        assert!(matches!(
            verify_content_matches_declared_mime(&png_header, "application/pdf"),
            Err(AppError::ValidationError)
        ));
    }
}
