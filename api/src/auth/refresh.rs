//! Handler `POST /v1/auth/refresh`.

use axum::extract::{Json, State};
use chrono::Utc;
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::Deserialize;
use sqlx::Row;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use crate::AppState;

use super::{AppError, LoginResponse, PatientClaims, ProClaims};

/// Corps de la requête `POST /v1/auth/refresh`.
#[derive(Deserialize)]
pub struct RefreshBody {
    refresh_token: String,
}

/// `POST /v1/auth/refresh` — rotation du refresh token.
///
/// Échange un refresh token valide contre un nouveau access token + nouveau refresh token.
/// L'ancien token est révoqué atomiquement dans la même transaction (rotation).
/// Token inconnu ou expiré → `401`.
/// Token révoqué (replay) → `401` + révocation de toute la chaîne de l'utilisateur.
pub async fn refresh(
    State(state): State<AppState>,
    Json(body): Json<RefreshBody>,
) -> Result<Json<LoginResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Cherche le token sans filtrer sur revoked_at/expires_at pour distinguer les cas.
    let row = sqlx::query(
        "SELECT app_user_id, revoked_at, expires_at FROM refresh_token \
         WHERE token_hash = encode(digest($1, 'sha256'), 'hex')",
    )
    .bind(&body.refresh_token)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::Unauthenticated)?;

    let user_id: Uuid = row.try_get("app_user_id").map_err(|_| AppError::Internal)?;
    let revoked_at: Option<chrono::DateTime<Utc>> =
        row.try_get("revoked_at").map_err(|_| AppError::Internal)?;
    let expires_at: chrono::DateTime<Utc> =
        row.try_get("expires_at").map_err(|_| AppError::Internal)?;

    if revoked_at.is_some() {
        // Replay détecté : révoque toute la chaîne active (vol de token présumé).
        sqlx::query(
            "UPDATE refresh_token SET revoked_at = now() \
             WHERE app_user_id = $1 AND revoked_at IS NULL",
        )
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Err(AppError::Unauthenticated);
    }

    if expires_at <= Utc::now() {
        tx.rollback().await.ok();
        return Err(AppError::Unauthenticated);
    }

    // Token valide : révoque l'ancien, émet le nouveau.
    sqlx::query(
        "UPDATE refresh_token SET revoked_at = now() \
         WHERE token_hash = encode(digest($1, 'sha256'), 'hex')",
    )
    .bind(&body.refresh_token)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let user_row = sqlx::query("SELECT kind FROM app_user WHERE id = $1")
        .bind(user_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let kind: String = user_row.try_get("kind").map_err(|_| AppError::Internal)?;

    let new_raw_token = Uuid::new_v4().to_string();
    sqlx::query(
        r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
           VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
    )
    .bind(user_id)
    .bind(&new_raw_token)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

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

    Ok(Json(LoginResponse {
        access_token,
        refresh_token: new_raw_token,
        token_type: "Bearer".to_string(),
        expires_in: EXPIRES_IN,
    }))
}
