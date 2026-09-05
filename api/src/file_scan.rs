//! Garde partagée d'analyse antivirale des uploads (stub EICAR).
//!
//! Quoi : détection de la signature de test EICAR dans le contenu binaire
//! d'un fichier uploadé, refusée en `422` avant toute écriture en base.
//! Quand : à appeler par CHAQUE endpoint d'upload qui écrit dans `document`
//! (coffre-fort `POST /documents`, carte mutuelle `POST /account/coverage/card`,
//! futurs uploads) — #4756 : la défense était asymétrique entre deux endpoints
//! écrivant dans la même table.
//! Pourquoi cette approche : le vrai scan antivirus est un stub à ce stade
//! (`scan_status = 'pending'`, ADR post-levée) ; la signature EICAR est le
//! standard de l'industrie pour tester le chemin de refus de bout en bout.
//! Modes d'échec : détection par fenêtre glissante — un fichier découpant la
//! signature sur plusieurs chunks n'est pas détecté (accepté : EICAR spécifie
//! la chaîne contiguë en tête de fichier).

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
