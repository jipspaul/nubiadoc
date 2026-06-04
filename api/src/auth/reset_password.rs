//! Handler `POST /v1/auth/password/reset`.

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
    Argon2,
};
use axum::{extract::State, Json};
use serde::Deserialize;
use serde_json::{json, Value};
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
/// Vérifie le token (SHA-256, non expiré), met à jour `password_hash`,
/// puis invalide le token (`NULL`). Token inexistant ou expiré → `422`.
pub async fn reset_password(
    State(state): State<AppState>,
    Json(body): Json<ResetPasswordBody>,
) -> Result<Json<Value>, AppError> {
    if body.new_password.len() < 8 || !body.new_password.chars().any(|c| c.is_ascii_digit()) {
        return Err(AppError::PasswordPolicy);
    }

    let row = sqlx::query(
        "SELECT id FROM app_user \
         WHERE password_reset_token = encode(digest($1, 'sha256'), 'hex') \
           AND password_reset_expires_at > now()",
    )
    .bind(&body.token)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::InvalidToken)?;
    let user_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    let salt = SaltString::generate(&mut OsRng);
    let password_hash = Argon2::default()
        .hash_password(body.new_password.as_bytes(), &salt)
        .map_err(|_| AppError::Internal)?
        .to_string();

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
    .execute(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(Json(json!({"message": "Mot de passe réinitialisé."})))
}
