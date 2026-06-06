//! Handler `POST /v1/auth/password/reset`.

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
    Argon2,
};
use axum::{extract::State, http::StatusCode, Json};
use chrono::Utc;
use serde::Deserialize;
use sqlx::Row;
use uuid::Uuid;

use crate::AppState;

use super::AppError;

/// Corps de la requête `POST /v1/auth/password/reset`.
#[derive(Deserialize)]
pub struct ResetPasswordBody {
    token: String,
    new_password: String,
}

/// `POST /v1/auth/password/reset` — finalise le reset via un token à usage unique.
///
/// Vérifie le token (SHA-256) : inconnu → `404`, expiré → `410`, valide → change
/// `password_hash` (argon2id), révoque tous les refresh tokens de l'utilisateur
/// (forcé logout), invalide le token (`NULL`). Retourne `204`.
pub async fn reset_password(
    State(state): State<AppState>,
    Json(body): Json<ResetPasswordBody>,
) -> Result<StatusCode, AppError> {
    if body.new_password.len() < 8 || !body.new_password.chars().any(|c| c.is_ascii_digit()) {
        return Err(AppError::PasswordPolicy);
    }

    // Recherche le token sans filtrer sur l'expiration pour distinguer les cas.
    let row = sqlx::query(
        "SELECT id, password_reset_expires_at FROM app_user \
         WHERE password_reset_token = encode(digest($1, 'sha256'), 'hex')",
    )
    .bind(&body.token)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::NotFound)?;

    let expires_at: chrono::DateTime<Utc> = row
        .try_get("password_reset_expires_at")
        .map_err(|_| AppError::Internal)?;
    if expires_at <= Utc::now() {
        return Err(AppError::LinkExpired);
    }

    let user_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    let salt = SaltString::generate(&mut OsRng);
    let password_hash = Argon2::default()
        .hash_password(body.new_password.as_bytes(), &salt)
        .map_err(|_| AppError::Internal)?
        .to_string();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE app_user \
         SET password_hash = $1, \
             password_reset_token = NULL, \
             password_reset_expires_at = NULL, \
             updated_at = now() \
         WHERE id = $2",
    )
    .bind(&password_hash)
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Révoque toutes les sessions actives (forcé logout sur tous les appareils).
    sqlx::query(
        "UPDATE refresh_token SET revoked_at = now() \
         WHERE app_user_id = $1 AND revoked_at IS NULL",
    )
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(user_id = %user_id, "password reset and sessions revoked");

    Ok(StatusCode::NO_CONTENT)
}
