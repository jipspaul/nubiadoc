//! Handler `POST /v1/auth/logout`.

use async_trait::async_trait;
use axum::{
    extract::{FromRequestParts, State},
    http::{request::Parts, HeaderMap, StatusCode},
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
    refresh_token: Option<String>,
}

/// `POST /v1/auth/logout` — révoque le(s) refresh token(s) de l'utilisateur authentifié.
///
/// - `refresh_token` dans le body → soft-delete de ce token (403 si cross-user, 204 si inconnu/déjà révoqué).
/// - Header `X-Revoke-All: true` → révoque tous les tokens actifs de l'utilisateur (force logout partout).
/// - Toujours `204 No Content` (pas d'énumération).
pub async fn logout(
    State(state): State<AppState>,
    claims: UserClaims,
    headers: HeaderMap,
    body: Option<Json<LogoutBody>>,
) -> Result<StatusCode, AppError> {
    let revoke_all = headers
        .get("X-Revoke-All")
        .and_then(|v| v.to_str().ok())
        .map(|v| v.eq_ignore_ascii_case("true"))
        .unwrap_or(false);

    // refresh_token a FORCE RLS : token_user_update exige app.current_user_id.
    // On ouvre une transaction et on pose le GUC avant tout DML.
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if revoke_all {
        let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(claims.sub.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        sqlx::query(
            "UPDATE refresh_token SET revoked_at = now() \
             WHERE app_user_id = $1 AND revoked_at IS NULL",
        )
        .bind(claims.sub)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;

        tracing::info!(user_id = %claims.sub, action = "logout_revoke_all");
    } else if let Some(token) = body.and_then(|b| b.0.refresh_token) {
        let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(claims.sub.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        let row = sqlx::query(
            "SELECT app_user_id FROM refresh_token \
             WHERE token_hash = encode(digest($1, 'sha256'), 'hex')",
        )
        .bind(&token)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        if let Some(r) = row {
            let owner_id: Uuid = r.try_get("app_user_id").map_err(|_| AppError::Internal)?;
            if owner_id != claims.sub {
                tx.rollback().await.map_err(|_| AppError::Internal)?;
                return Err(AppError::Forbidden);
            }
            sqlx::query(
                "UPDATE refresh_token SET revoked_at = now() \
                 WHERE token_hash = encode(digest($1, 'sha256'), 'hex') \
                   AND revoked_at IS NULL",
            )
            .bind(&token)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

            tracing::info!(user_id = %claims.sub, action = "logout_token_revoked");
        }
        tx.commit().await.map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok(StatusCode::NO_CONTENT)
}
