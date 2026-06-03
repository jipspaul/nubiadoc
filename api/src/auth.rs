//! Handlers d'authentification.

use async_trait::async_trait;
use axum::{
    extract::{FromRequestParts, State},
    http::{request::Parts, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use jsonwebtoken::{decode, DecodingKey, Validation};
use serde::{Deserialize, Serialize};
use serde_json::json;
use totp_rs::{Algorithm, Secret, TOTP};
use uuid::Uuid;

use crate::AppState;

/// Claims JWT portées par les utilisateurs pro.
#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct ProClaims {
    /// Identifiant de l'utilisateur (`app_user.id`).
    sub: Uuid,
    /// Type de compte : "pro".
    kind: String,
    exp: u64,
}

/// Erreur HTTP renvoyée au client.
pub(crate) enum AppError {
    Unauthorized,
    ValidationError,
    Internal,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        match self {
            AppError::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                Json(json!({"code": "unauthorized"})),
            )
                .into_response(),
            AppError::ValidationError => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"code": "validation_error"})),
            )
                .into_response(),
            AppError::Internal => (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({"code": "internal_error"})),
            )
                .into_response(),
        }
    }
}

/// Lit le JWT dans `Authorization: Bearer <token>`, vérifie la signature et `kind == "pro"`.
#[async_trait]
impl FromRequestParts<AppState> for ProClaims {
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

        let data =
            decode::<ProClaims>(token, &key, &validation).map_err(|_| AppError::Unauthorized)?;

        if data.claims.kind != "pro" {
            return Err(AppError::Unauthorized);
        }

        Ok(data.claims)
    }
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
) -> Result<Json<serde_json::Value>, AppError> {
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

    sqlx::query!(
        "UPDATE app_user SET mfa_secret = $1, mfa_enabled = true, updated_at = now() WHERE id = $2",
        body.totp_secret,
        claims.sub,
    )
    .execute(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(Json(json!({"message": "MFA activée."})))
}
