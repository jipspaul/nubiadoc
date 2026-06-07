//! Handler `POST /v1/auth/login`.

use argon2::{
    password_hash::{PasswordHash, PasswordVerifier},
    Argon2,
};
use axum::extract::{Json, State};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::Deserialize;
use sqlx::Row;
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use totp_rs::{Algorithm, Secret, TOTP};
use uuid::Uuid;

use crate::AppState;

use super::{AppError, LoginResponse, PatientClaims, ProClaims, ProRegisterClaims};

const RATE_MAX_ATTEMPTS: u32 = 10;
const RATE_WINDOW: Duration = Duration::from_secs(300);

static LOGIN_RATE: LazyLock<Mutex<HashMap<String, (u32, Instant)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn is_rate_limited(email: &str) -> bool {
    let mut map = LOGIN_RATE.lock().unwrap_or_else(|e| e.into_inner());
    let now = Instant::now();
    let entry = map.entry(email.to_lowercase()).or_insert((0, now));
    if now.duration_since(entry.1) >= RATE_WINDOW {
        *entry = (1, now);
        false
    } else {
        entry.0 += 1;
        entry.0 > RATE_MAX_ATTEMPTS
    }
}

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
    if is_rate_limited(&body.email) {
        return Err(AppError::TooManyRequests);
    }

    let mut auth_tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_login_email', $1, true)")
        .bind(&body.email)
        .execute(&mut *auth_tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, password_hash, kind, totp_enabled, totp_secret \
         FROM app_user WHERE email = $1",
    )
    .bind(&body.email)
    .fetch_optional(&mut *auth_tx)
    .await
    .map_err(|_| AppError::Internal)?;

    auth_tx.rollback().await.map_err(|_| AppError::Internal)?;

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
        // patient_account a FORCE RLS avec account_auth_select. La policy
        // utilise un GUC dédié (app.current_login_user_id) introduit par la
        // migration 0069, posé UNIQUEMENT dans cette transaction de login.
        let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
        sqlx::query("SELECT set_config('app.current_login_user_id', $1, true)")
            .bind(user_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        let acct_row = sqlx::query("SELECT id FROM patient_account WHERE app_user_id = $1")
            .bind(user_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;

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
        // Re-resolve cabinet_id + role from cabinet_membership.
        // user_active_membership() est SECURITY DEFINER (migration 0083), contourne la RLS
        // cabinet-scoped pour bootstrapper le tenant sans GUC préalable.
        let mut tx2 = state.db.begin().await.map_err(|_| AppError::Internal)?;
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(user_id.to_string())
            .execute(&mut *tx2)
            .await
            .map_err(|_| AppError::Internal)?;
        let membership_row = sqlx::query("SELECT cabinet_id, role FROM user_active_membership($1)")
            .bind(user_id)
            .fetch_optional(&mut *tx2)
            .await
            .map_err(|_| AppError::Internal)?;
        tx2.commit().await.map_err(|_| AppError::Internal)?;

        match membership_row {
            Some(r) => {
                let cabinet_id: Uuid = r.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
                let role: String = r.try_get("role").map_err(|_| AppError::Internal)?;
                encode(
                    &Header::default(),
                    &ProRegisterClaims {
                        sub: user_id,
                        kind: "pro".to_string(),
                        cabinet_id,
                        role,
                        exp,
                    },
                    &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
                )
                .map_err(|_| AppError::Internal)?
            }
            None => encode(
                &Header::default(),
                &ProClaims {
                    sub: user_id,
                    kind: "pro".to_string(),
                    exp,
                },
                &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
            )
            .map_err(|_| AppError::Internal)?,
        }
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
