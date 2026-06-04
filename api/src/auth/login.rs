//! Handler `POST /v1/auth/login`.

use argon2::{
    password_hash::{PasswordHash, PasswordVerifier},
    Argon2,
};
use axum::extract::{Json, State};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::Deserialize;
use sqlx::Row;
use std::time::{SystemTime, UNIX_EPOCH};
use totp_rs::{Algorithm, Secret, TOTP};
use uuid::Uuid;

use crate::AppState;

use super::{AppError, LoginResponse, PatientClaims, ProClaims};

/// Corps de la requête `POST /v1/auth/login`.
#[derive(Deserialize)]
pub struct LoginBody {
    email: String,
    password: String,
    mfa_code: Option<String>,
}

/// `POST /v1/auth/login` — authentifie un patient ou un pro, émet access + refresh tokens.
///
/// Réponse neutre sur credentials incorrects (anti-énumération §1.8).
/// Si le compte pro a `totp_enabled = true` et qu'aucun `mfa_code` n'est fourni → `401 mfa_required`.
pub async fn login(
    State(state): State<AppState>,
    Json(body): Json<LoginBody>,
) -> Result<Json<LoginResponse>, AppError> {
    let row = sqlx::query(
        "SELECT id, password_hash, kind, totp_enabled, totp_secret \
         FROM app_user WHERE email = $1",
    )
    .bind(&body.email)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::Unauthenticated)?;

    let user_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let password_hash: String = row
        .try_get("password_hash")
        .map_err(|_| AppError::Internal)?;
    let kind: String = row.try_get("kind").map_err(|_| AppError::Internal)?;
    let totp_enabled: bool = row
        .try_get("totp_enabled")
        .map_err(|_| AppError::Internal)?;
    let totp_secret: Option<String> = row.try_get("totp_secret").map_err(|_| AppError::Internal)?;

    let parsed_hash = PasswordHash::new(&password_hash).map_err(|_| AppError::Internal)?;
    Argon2::default()
        .verify_password(body.password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::Unauthenticated)?;

    if kind == "pro" && totp_enabled {
        match &body.mfa_code {
            None => return Err(AppError::MfaRequired),
            Some(code) => {
                let secret = totp_secret.ok_or(AppError::Internal)?;
                let secret_bytes = Secret::Encoded(secret)
                    .to_bytes()
                    .map_err(|_| AppError::Unauthenticated)?;
                let totp = TOTP::new(Algorithm::SHA1, 6, 1, 30, secret_bytes)
                    .map_err(|_| AppError::Unauthenticated)?;
                if !totp.check_current(code).map_err(|_| AppError::Internal)? {
                    return Err(AppError::Unauthenticated);
                }
            }
        }
    }

    const EXPIRES_IN: u64 = 900;
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + EXPIRES_IN;

    let access_token = if kind == "patient" {
        let acct_row = sqlx::query("SELECT id FROM patient_account WHERE app_user_id = $1")
            .bind(user_id)
            .fetch_optional(&state.db)
            .await
            .map_err(|_| AppError::Internal)?;

        let account_id: Uuid = acct_row
            .map(|r| r.try_get("id"))
            .transpose()
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::Internal)?;

        encode(
            &Header::default(),
            &PatientClaims {
                sub: user_id,
                kind: "patient".to_string(),
                account_id,
                exp,
            },
            &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
        )
        .map_err(|_| AppError::Internal)?
    } else {
        encode(
            &Header::default(),
            &ProClaims {
                sub: user_id,
                kind: "pro".to_string(),
                exp,
            },
            &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
        )
        .map_err(|_| AppError::Internal)?
    };

    let raw_token = Uuid::new_v4().to_string();
    sqlx::query(
        r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
           VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
    )
    .bind(user_id)
    .bind(&raw_token)
    .execute(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(Json(LoginResponse {
        access_token,
        refresh_token: raw_token,
        token_type: "Bearer".to_string(),
        expires_in: EXPIRES_IN,
    }))
}
