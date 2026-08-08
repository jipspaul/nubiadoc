//! Handler `POST /v1/auth/mfa/verify`.

use axum::{extract::State, Json};
use serde::Deserialize;
use serde_json::{json, Value};
use totp_rs::{Algorithm, Secret, TOTP};

use crate::AppState;

use super::mfa_crypto::{encrypt_totp_secret, key_manager_from_env};
use super::{AppError, ProClaims};

/// Corps de la requête `POST /v1/auth/mfa/verify`.
#[derive(Deserialize)]
pub struct MfaVerifyBody {
    /// Secret TOTP Base32 retourné par `/mfa/enroll`.
    totp_secret: String,
    /// Code TOTP à 6 chiffres saisi par l'utilisateur.
    totp_code: String,
}

/// `POST /v1/auth/mfa/verify` — valide le code TOTP et active la MFA.
///
/// Le code TOTP est validé AVANT toute persistance (règle métier : ne pas activer
/// sur code invalide).
pub async fn mfa_verify(
    State(state): State<AppState>,
    claims: ProClaims,
    Json(body): Json<MfaVerifyBody>,
) -> Result<Json<Value>, AppError> {
    let secret_bytes = Secret::Encoded(body.totp_secret.clone())
        .to_bytes()
        .map_err(|_| AppError::ValidationError)?;

    let totp = TOTP::new(Algorithm::SHA1, 6, 1, 30, secret_bytes)
        .map_err(|_| AppError::ValidationError)?;

    let is_valid = totp
        .check_current(&body.totp_code)
        .map_err(|_| AppError::Internal)?;

    if !is_valid {
        return Err(AppError::ValidationError);
    }

    let key_manager = key_manager_from_env().map_err(|_| AppError::Internal)?;
    let (secret_ciphertext, secret_key_ref) = encrypt_totp_secret(&body.totp_secret, &key_manager)
        .await
        .map_err(|_| AppError::Internal)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    sqlx::query!(
        "DELETE FROM mfa_enrollment WHERE app_user_id = $1",
        claims.sub,
    )
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    sqlx::query!(
        "INSERT INTO mfa_enrollment (app_user_id, secret_ciphertext, secret_key_ref, method, verified)
         VALUES ($1, $2, $3, 'totp', true)",
        claims.sub,
        secret_ciphertext,
        secret_key_ref,
    )
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    sqlx::query!(
        "UPDATE app_user SET totp_enabled = true, updated_at = now() WHERE id = $1",
        claims.sub,
    )
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(json!({"message": "MFA activée."})))
}
