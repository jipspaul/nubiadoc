//! Handler `POST /v1/auth/logout`.

use async_trait::async_trait;
use axum::{
    extract::{FromRequestParts, State},
    http::{request::Parts, StatusCode},
    Json,
};
use jsonwebtoken::{decode, DecodingKey, Validation};
use serde::Deserialize;
use sqlx::Row;
use uuid::Uuid;

use crate::AppState;

use super::AppError;

/// Claims JWT génériques — valides pour les tokens patient et pro.
#[derive(Debug, Deserialize)]
pub(crate) struct UserClaims {
    pub(crate) sub: Uuid,
}

/// Lit le JWT dans `Authorization: Bearer <token>`, vérifie la signature.
/// Accepte les tokens patient et pro.
#[async_trait]
impl FromRequestParts<AppState> for UserClaims {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let auth = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or(AppError::Unauthorized)?;

        let token = auth.strip_prefix("Bearer ").ok_or(AppError::Unauthorized)?;

        let key = DecodingKey::from_secret(state.jwt_secret.as_bytes());
        let mut validation = Validation::default();
        validation.validate_exp = true;

        decode::<UserClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)
    }
}

/// Corps de la requête `POST /v1/auth/logout`.
#[derive(Deserialize)]
pub struct LogoutBody {
    refresh_token: String,
}

/// `POST /v1/auth/logout` — révoque le refresh token de l'utilisateur authentifié.
///
/// Soft-delete : SET `revoked_at = NOW()`. Vérifie que `refresh_token.app_user_id == claims.sub`
/// pour interdire la révocation cross-user (`403`). Idempotent si le token est
/// inconnu ou déjà révoqué (`204` dans les deux cas).
pub async fn logout(
    State(state): State<AppState>,
    claims: UserClaims,
    Json(body): Json<LogoutBody>,
) -> Result<StatusCode, AppError> {
    let row = sqlx::query(
        "SELECT app_user_id FROM refresh_token \
         WHERE token_hash = encode(digest($1, 'sha256'), 'hex')",
    )
    .bind(&body.refresh_token)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(r) = row {
        let owner_id: Uuid = r.try_get("app_user_id").map_err(|_| AppError::Internal)?;
        if owner_id != claims.sub {
            return Err(AppError::Forbidden);
        }
        sqlx::query(
            "UPDATE refresh_token SET revoked_at = now() \
             WHERE token_hash = encode(digest($1, 'sha256'), 'hex') \
               AND revoked_at IS NULL",
        )
        .bind(&body.refresh_token)
        .execute(&state.db)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    Ok(StatusCode::NO_CONTENT)
}
