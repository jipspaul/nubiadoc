//! Handler `POST /v1/auth/mfa/disable`.

use argon2::{
    password_hash::{PasswordHash, PasswordVerifier},
    Argon2,
};
use axum::{extract::State, Json};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;

use crate::AppState;

use super::{AppError, ProClaims};

/// Corps de la requête `POST /v1/auth/mfa/disable`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MfaDisableBody {
    /// Mot de passe courant, redemandé pour confirmer la désactivation
    /// (un JWT volé/laissé ouvert ne doit pas suffire à couper le second
    /// facteur).
    password: String,
}

/// `POST /v1/auth/mfa/disable` — désactive la MFA TOTP du compte pro authentifié.
///
/// Seule voie de désactivation hors reset de mot de passe complet (#7328) :
/// jusqu'ici, activer la MFA via `/mfa/verify` était irréversible sans passer
/// par `POST /v1/auth/password/reset`, qui exige l'accès à la boîte mail et
/// change le mot de passe au passage — inutilisable sur un compte partagé
/// (démo, cabinet). Redemande le mot de passe courant (même garde qu'un
/// reset) avant de supprimer l'enrôlement.
pub async fn mfa_disable(
    State(state): State<AppState>,
    claims: ProClaims,
    Json(body): Json<MfaDisableBody>,
) -> Result<Json<Value>, AppError> {
    let mut tx = state.db.begin().await.map_err(|e| db_error(&e, "begin"))?;
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|e| db_error(&e, "set_config app.current_user_id"))?;

    let row = sqlx::query("SELECT password_hash, totp_enabled FROM app_user WHERE id = $1")
        .bind(claims.sub)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|e| db_error(&e, "select app_user"))?
        .ok_or(AppError::Unauthenticated)?;

    let password_hash: Option<String> = row
        .try_get("password_hash")
        .map_err(|e| db_error(&e, "read password_hash"))?;
    let totp_enabled: bool = row
        .try_get("totp_enabled")
        .map_err(|e| db_error(&e, "read totp_enabled"))?;

    let password_hash = password_hash.ok_or(AppError::Unauthenticated)?;
    let parsed_hash = PasswordHash::new(&password_hash).map_err(|_| AppError::Unauthenticated)?;
    Argon2::default()
        .verify_password(body.password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::Unauthenticated)?;

    if !totp_enabled {
        return Err(AppError::InvalidStatus);
    }

    sqlx::query("DELETE FROM mfa_enrollment WHERE app_user_id = $1 AND method = 'totp'")
        .bind(claims.sub)
        .execute(&mut *tx)
        .await
        .map_err(|e| db_error(&e, "delete mfa_enrollment"))?;
    sqlx::query("UPDATE app_user SET totp_enabled = false, updated_at = now() WHERE id = $1")
        .bind(claims.sub)
        .execute(&mut *tx)
        .await
        .map_err(|e| db_error(&e, "update app_user.totp_enabled"))?;
    tx.commit().await.map_err(|e| db_error(&e, "commit"))?;

    tracing::info!(user_id = %claims.sub, "mfa_disable: MFA TOTP désactivée");
    Ok(Json(json!({"message": "MFA désactivée."})))
}

/// Erreur SQL → `500` logué avec l'étape en cause (jamais un 500 muet).
fn db_error(e: &sqlx::Error, step: &'static str) -> AppError {
    tracing::error!(error = %e, step, "mfa_disable: échec base de données");
    AppError::Internal
}
