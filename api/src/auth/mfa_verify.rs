//! Handler `POST /v1/auth/mfa/verify`.

use axum::{extract::State, Json};
use serde::Deserialize;
use serde_json::{json, Value};
use totp_rs::{Algorithm, Secret, TOTP};

use crate::{kms_env, AppState};

use super::mfa_crypto::encrypt_totp_secret;
use super::{AppError, ProClaims};

/// Corps de la requête `POST /v1/auth/mfa/verify`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MfaVerifyBody {
    /// Secret TOTP Base32 retourné par `/mfa/enroll`.
    totp_secret: String,
    /// Code TOTP à 6 chiffres saisi par l'utilisateur.
    totp_code: String,
}

/// `POST /v1/auth/mfa/verify` — valide le code TOTP et active la MFA.
///
/// Le code TOTP est validé AVANT toute persistance (règle métier : ne pas activer
/// sur code invalide) : secret illisible (pas du Base32) ou code faux/expiré
/// → `422 validation_error`, rien n'est écrit.
///
/// Contrat d'erreur après validation (#6980, #7216) : chaque étape qui
/// échoue est loguée avec sa cause (`tracing::error!`) — avant, huit
/// `map_err(|_| AppError::Internal)` d'affilée rendaient un 500 muet, et la
/// cause réelle (`KMS_MASTER_KEY` jamais transmise au conteneur par
/// `infra/deploy/deploy.sh`) est restée invisible pendant que la MFA était
/// inactivable pour tous les comptes pro. Une clé KMS absente/mal formée
/// répond désormais `503 kms_not_configured` (cf. `crate::kms_env`).
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

    let is_valid = totp.check_current(&body.totp_code).map_err(|e| {
        tracing::error!(error = %e, "mfa_verify: horloge système illisible");
        AppError::Internal
    })?;

    if !is_valid {
        return Err(AppError::ValidationError);
    }

    let key_manager = kms_env::key_manager_from_env().map_err(|e| {
        tracing::error!(
            error = %e,
            user_id = %claims.sub,
            "mfa_verify: clé KMS inexploitable, enrôlement refusé (fail-closed)"
        );
        AppError::KmsNotConfigured
    })?;
    let (secret_ciphertext, secret_key_ref) = encrypt_totp_secret(&body.totp_secret, &key_manager)
        .await
        .map_err(|e| {
            tracing::error!(error = %e, user_id = %claims.sub, "mfa_verify: chiffrement du secret TOTP échoué");
            AppError::Internal
        })?;

    let mut tx = state.db.begin().await.map_err(|e| db_error(&e, "begin"))?;
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|e| db_error(&e, "set_config app.current_user_id"))?;
    // Le secret TOTP est désormais chiffré au repos dans `mfa_enrollment`
    // (migration 0046/0047) — `app_user.totp_secret` n'est plus alimenté par
    // ce chemin (#4652). Un ré-enrôlement remplace l'enrôlement existant.
    sqlx::query("DELETE FROM mfa_enrollment WHERE app_user_id = $1 AND method = 'totp'")
        .bind(claims.sub)
        .execute(&mut *tx)
        .await
        .map_err(|e| db_error(&e, "delete mfa_enrollment"))?;
    sqlx::query(
        "INSERT INTO mfa_enrollment (app_user_id, secret_ciphertext, secret_key_ref, method, verified) \
         VALUES ($1, $2, $3, 'totp', true)",
    )
    .bind(claims.sub)
    .bind(secret_ciphertext)
    .bind(secret_key_ref)
    .execute(&mut *tx)
    .await
    .map_err(|e| db_error(&e, "insert mfa_enrollment"))?;
    sqlx::query("UPDATE app_user SET totp_enabled = true, updated_at = now() WHERE id = $1")
        .bind(claims.sub)
        .execute(&mut *tx)
        .await
        .map_err(|e| db_error(&e, "update app_user.totp_enabled"))?;
    tx.commit().await.map_err(|e| db_error(&e, "commit"))?;

    tracing::info!(user_id = %claims.sub, "mfa_verify: MFA TOTP activée");
    Ok(Json(json!({"message": "MFA activée."})))
}

/// Erreur SQL → `500` logué avec l'étape en cause (jamais un 500 muet).
fn db_error(e: &sqlx::Error, step: &'static str) -> AppError {
    tracing::error!(error = %e, step, "mfa_verify: échec base de données");
    AppError::Internal
}
