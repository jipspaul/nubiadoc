//! Handler `POST /v1/auth/mfa/enroll`.

use axum::Json;
use serde::Serialize;
use totp_rs::Secret;

use super::{AppError, ProClaims};

/// Réponse de `POST /v1/auth/mfa/enroll`.
#[derive(Serialize)]
pub struct MfaEnrollResponse {
    totp_secret: String,
    otpauth_url: String,
}

/// `POST /v1/auth/mfa/enroll` — démarre l'enrôlement TOTP (pro uniquement).
///
/// Génère un secret TOTP aléatoire et retourne l'URL `otpauth://` pour affichage QR.
/// Le secret n'est PAS persisté ici — il le sera lors de la vérification via `/mfa/verify`.
pub async fn mfa_enroll(_claims: ProClaims) -> Result<Json<MfaEnrollResponse>, AppError> {
    let secret = Secret::generate_secret();
    let totp_secret = secret.to_encoded().to_string();
    let otpauth_url = format!(
        "otpauth://totp/Nubia%20Health?secret={}&issuer=Nubia%20Health&algorithm=SHA1&digits=6&period=30",
        totp_secret
    );
    Ok(Json(MfaEnrollResponse {
        totp_secret,
        otpauth_url,
    }))
}
