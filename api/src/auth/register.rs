//! Handler `POST /v1/auth/register`.

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
    Argon2,
};
use axum::{
    extract::{Json, State},
    http::StatusCode,
};
use chrono::Utc;
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use crate::AppState;

use super::{is_unique_violation, AppError, PatientClaims, ProRegisterClaims};

const RATE_MAX_ATTEMPTS: u32 = 5;
const RATE_WINDOW: Duration = Duration::from_secs(600);

static REGISTER_RATE: LazyLock<Mutex<HashMap<String, (u32, Instant)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn is_rate_limited(email: &str) -> bool {
    let mut map = REGISTER_RATE.lock().unwrap_or_else(|e| e.into_inner());
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

/// Corps de la requête `POST /v1/auth/register`.
#[derive(Deserialize)]
pub struct RegisterBody {
    email: String,
    password: String,
    accept_cgu: bool,
    cgu_version: String,
    /// Token d'invitation envoyé par email lors de `POST /v1/cabinet/members`.
    /// Si présent, finalise le compte secrétariat invité au lieu de créer un compte patient.
    invitation_token: Option<String>,
}

#[derive(Serialize)]
pub(crate) struct RegisterResponse {
    account_id: Uuid,
    access_token: String,
    refresh_token: String,
}

/// `POST /v1/auth/register` — crée un compte patient (app_user + patient_account +
/// consent_record) en transaction atomique, puis émet les tokens.
/// Si `invitation_token` est présent, finalise le compte secrétariat invité au lieu.
pub async fn register(
    State(state): State<AppState>,
    Json(body): Json<RegisterBody>,
) -> Result<(StatusCode, Json<RegisterResponse>), AppError> {
    if is_rate_limited(&body.email) {
        return Err(AppError::TooManyRequests(600));
    }
    if !body.accept_cgu {
        return Err(AppError::CguRequired);
    }
    if body.password.len() < 8 || !body.password.chars().any(|c| c.is_ascii_digit()) {
        return Err(AppError::PasswordPolicy);
    }

    if let Some(ref invite_token) = body.invitation_token {
        return register_invited(state, invite_token, &body.password).await;
    }

    let salt = SaltString::generate(&mut OsRng);
    let password_hash = Argon2::default()
        .hash_password(body.password.as_bytes(), &salt)
        .map_err(|_| AppError::Internal)?
        .to_string();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Pré-génère les UUIDs pour éviter RETURNING sur tables avec FORCE RLS.
    // app_user et patient_account ont FORCE RLS : RETURNING id serait bloqué
    // par user_self_select / account_self_select (GUC non encore positionné).
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, $3, 'patient')",
    )
    .bind(user_id)
    .bind(&body.email)
    .bind(&password_hash)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        if is_unique_violation(&e) {
            AppError::EmailTaken
        } else {
            AppError::Internal
        }
    })?;

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES ($1, $2, '', '')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO consent_record (app_user_id, purpose, granted, granted_at, cgu_version) \
         VALUES ($1, 'soins', true, now(), $2)",
    )
    .bind(user_id)
    .bind(&body.cgu_version)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let raw_token = Uuid::new_v4().to_string();
    sqlx::query(
        r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
           VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
    )
    .bind(user_id)
    .bind(&raw_token)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + 900;
    let claims = PatientClaims {
        sub: user_id,
        kind: "patient".to_string(),
        account_id,
        exp,
    };
    let access_token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|_| AppError::Internal)?;

    Ok((
        StatusCode::CREATED,
        Json(RegisterResponse {
            account_id,
            access_token,
            refresh_token: raw_token,
        }),
    ))
}

/// Finalise le compte d'un secrétariat invité : valide le token d'invitation,
/// pose le mot de passe, et émet un JWT pro avec cabinet_id + role.
async fn register_invited(
    state: AppState,
    invite_token: &str,
    password: &str,
) -> Result<(StatusCode, Json<RegisterResponse>), AppError> {
    // Calcule le hash SHA-256 du token brut via le même mécanisme que reset_password.
    // Pose app.current_reset_token_hash pour activer la policy user_reset_token_select.
    let token_hash = {
        let mut h_tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
        let h_row = sqlx::query("SELECT encode(digest($1, 'sha256'), 'hex') AS h")
            .bind(invite_token)
            .fetch_one(&mut *h_tx)
            .await
            .map_err(|_| AppError::Internal)?;
        let _ = h_tx.rollback().await;
        h_row
            .try_get::<String, _>("h")
            .map_err(|_| AppError::Internal)?
    };

    // Recherche l'utilisateur invité par token (policy user_reset_token_select).
    let mut lookup_tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_reset_token_hash', $1, true)")
        .bind(&token_hash)
        .execute(&mut *lookup_tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let row = sqlx::query(
        "SELECT id, password_reset_expires_at FROM app_user \
         WHERE password_reset_token = $1",
    )
    .bind(&token_hash)
    .fetch_optional(&mut *lookup_tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let _ = lookup_tx.rollback().await;

    let row = row.ok_or(AppError::InvitationInvalid)?;

    let expires_at: chrono::DateTime<chrono::Utc> = row
        .try_get("password_reset_expires_at")
        .map_err(|_| AppError::Internal)?;
    if expires_at <= chrono::Utc::now() {
        return Err(AppError::InvitationInvalid);
    }

    let user_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    let salt = SaltString::generate(&mut OsRng);
    let password_hash = Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map_err(|_| AppError::Internal)?
        .to_string();

    let raw_refresh = Uuid::new_v4().to_string();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // app_user a FORCE RLS user_self_select : pose current_user_id avant tout DML.
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

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

    sqlx::query(
        r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
           VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
    )
    .bind(user_id)
    .bind(&raw_refresh)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Récupère le membership via user_all_memberships (SECURITY DEFINER, contourne la RLS).
    let mut m_tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    let m_row = sqlx::query(
        "SELECT cabinet_id, role, secretariat_id FROM user_all_memberships($1) LIMIT 1",
    )
    .bind(user_id)
    .fetch_optional(&mut *m_tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let _ = m_tx.rollback().await;

    let m_row = m_row.ok_or(AppError::Internal)?;
    let cabinet_id: Uuid = m_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let role: String = m_row.try_get("role").map_err(|_| AppError::Internal)?;
    let secretariat_id: Option<Uuid> = m_row
        .try_get("secretariat_id")
        .map_err(|_| AppError::Internal)?;

    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + 900;
    let claims = ProRegisterClaims {
        sub: user_id,
        kind: "pro".to_string(),
        cabinet_id,
        role,
        secretariat_id,
        exp,
    };
    let access_token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %user_id,
        cabinet_id = %cabinet_id,
        "invited secretary registered"
    );

    Ok((
        StatusCode::CREATED,
        Json(RegisterResponse {
            account_id: user_id,
            access_token,
            refresh_token: raw_refresh,
        }),
    ))
}
