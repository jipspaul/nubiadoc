//! Handler `POST /v1/auth/mfa/verify`.

use axum::{extract::State, Json};
use base64::{engine::general_purpose::STANDARD, Engine};
use core_crypto::LocalKeyManager;
use serde::Deserialize;
use serde_json::{json, Value};
use totp_rs::{Algorithm, Secret, TOTP};

use crate::AppState;

use super::mfa_crypto::encrypt_totp_secret;
use super::{AppError, ProClaims};

/// Construit le [`LocalKeyManager`] (POC/dev) depuis `KMS_MASTER_KEY`
/// (32 octets, base64) — même convention que `interop::patient`. Échoue en
/// `AppError::Internal` (jamais de fallback en clair) si `KMS_MASTER_KEY`
/// est absente/mal formée.
fn key_manager_from_env() -> Result<LocalKeyManager, AppError> {
    let raw = std::env::var("KMS_MASTER_KEY").map_err(|_| AppError::Internal)?;
    let decoded = STANDARD
        .decode(raw.trim())
        .map_err(|_| AppError::Internal)?;
    let key: [u8; 32] = decoded.try_into().map_err(|_| AppError::Internal)?;
    Ok(LocalKeyManager::new(
        key,
        std::env::var("KMS_KEY_VERSION").unwrap_or_else(|_| "v1".to_string()),
    ))
}

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

    let key_manager = key_manager_from_env()?;
    let (secret_ciphertext, secret_key_ref) =
        encrypt_totp_secret(&body.totp_secret, &key_manager)
            .await
            .map_err(|_| AppError::Internal)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    // Le secret TOTP est désormais chiffré au repos dans `mfa_enrollment`
    // (migration 0046/0047) — `app_user.totp_secret` n'est plus alimenté par
    // ce chemin (#4652). Un ré-enrôlement remplace l'enrôlement existant.
    sqlx::query("DELETE FROM mfa_enrollment WHERE app_user_id = $1 AND method = 'totp'")
        .bind(claims.sub)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    sqlx::query(
        "INSERT INTO mfa_enrollment (app_user_id, secret_ciphertext, secret_key_ref, method, verified) \
         VALUES ($1, $2, $3, 'totp', true)",
    )
    .bind(claims.sub)
    .bind(secret_ciphertext)
    .bind(secret_key_ref)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    sqlx::query("UPDATE app_user SET totp_enabled = true, updated_at = now() WHERE id = $1")
        .bind(claims.sub)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(json!({"message": "MFA activée."})))
}
