//! Handler `POST /v1/auth/select-context`.

use axum::extract::{Json, State};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use crate::AppState;

use super::{AppError, ProClaims, ProRegisterClaims};

/// Corps de la requête `POST /v1/auth/select-context`.
#[derive(Deserialize)]
pub struct SelectContextBody {
    cabinet_id: Uuid,
}

/// Réponse de `POST /v1/auth/select-context`.
#[derive(Serialize)]
pub struct SelectContextResponse {
    access_token: String,
    token_type: String,
    expires_in: u64,
}

/// `POST /v1/auth/select-context` — émet un JWT scopé sur le cabinet demandé.
///
/// Le porteur doit être un pro authentifié (`ProClaims`). L'endpoint vérifie que
/// l'utilisateur est membre actif du `cabinet_id` demandé via `user_all_memberships`
/// (SECURITY DEFINER, contourne la RLS cabinet-scoped) puis émet un nouveau
/// `ProRegisterClaims` portant `cabinet_id` et `role`. Aucun refresh token n'est
/// émis — sélection de contexte uniquement.
///
/// Retourne `403 forbidden` si l'utilisateur n'est pas membre actif du cabinet demandé.
pub async fn select_context(
    State(state): State<AppState>,
    claims: ProClaims,
    Json(body): Json<SelectContextBody>,
) -> Result<Json<SelectContextResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row =
        sqlx::query("SELECT cabinet_id, role FROM user_all_memberships($1) WHERE cabinet_id = $2")
            .bind(claims.sub)
            .bind(body.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::Forbidden)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let role: String = row.try_get("role").map_err(|_| AppError::Internal)?;

    const EXPIRES_IN: u64 = 900;
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + EXPIRES_IN;

    let access_token = encode(
        &Header::default(),
        &ProRegisterClaims {
            sub: claims.sub,
            kind: "pro".to_string(),
            cabinet_id,
            role,
            exp,
        },
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %claims.sub,
        cabinet_id = %cabinet_id,
        "context selected"
    );

    Ok(Json(SelectContextResponse {
        access_token,
        token_type: "Bearer".to_string(),
        expires_in: EXPIRES_IN,
    }))
}
