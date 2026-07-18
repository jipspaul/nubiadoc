//! Handler `POST /v1/devices` — enregistrement d'un device FCM.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{auth::AppError, AppState};

/// Corps de la requête `POST /v1/devices`.
#[derive(Deserialize)]
pub struct RegisterDeviceBody {
    pub fcm_token: String,
    pub platform: String,
}

/// Réponse de `POST /v1/devices`.
#[derive(Serialize)]
pub struct RegisterDeviceResponse {
    pub id: Uuid,
}

/// `POST /v1/devices` — enregistre ou remplace le device FCM de l'utilisateur courant.
///
/// Accepte les tokens patient et pro (`sub` = `app_user.id`). La RLS `device_owner`
/// (migration 0052) filtre sur `app.current_user_id`. Platform invalide → 422.
/// UNIQUE partiel actif sur `(app_user_id, platform) WHERE deleted_at IS NULL` :
/// l'insert upsert soft-delete + insert pour garantir l'unicité par (user, platform).
#[tracing::instrument(skip_all, fields(user_id = %claims.sub, platform = %body.platform))]
pub async fn register_device(
    State(state): State<AppState>,
    claims: crate::auth::MeClaims,
    Json(body): Json<RegisterDeviceBody>,
) -> Result<(StatusCode, Json<RegisterDeviceResponse>), AppError> {
    if body.fcm_token.trim().is_empty() {
        return Err(AppError::ValidationError);
    }

    if !["ios", "android", "web"].contains(&body.platform.as_str()) {
        return Err(AppError::ValidationError);
    }

    let user_id = claims.sub;
    let device_id = Uuid::new_v4();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // RLS device_owner : exige app.current_user_id = app_user_id.
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Soft-delete l'éventuel device actif existant pour cette (user, platform).
    sqlx::query(
        "UPDATE device SET deleted_at = now() \
         WHERE app_user_id = $1 AND platform = $2 AND deleted_at IS NULL",
    )
    .bind(user_id)
    .bind(&body.platform)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Un fcm_token identifie UN install physique : invalide toute ligne active
    // d'un AUTRE utilisateur sur ce même token (terminal réattribué / partagé).
    // Sinon le worker push livre les notifs santé de l'ancien compte au nouveau
    // détenteur du terminal (issue #3789). La RLS device_owner (0052) empêche
    // nubia_app de voir/modifier les devices d'un autre app_user_id — passe par
    // la fonction SECURITY DEFINER device_deactivate_other_owners (0147).
    sqlx::query("SELECT device_deactivate_other_owners($1, $2)")
        .bind(&body.fcm_token)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Insert du nouveau device avec id pré-généré (évite RETURNING bloqué par RLS).
    sqlx::query(
        "INSERT INTO device (id, app_user_id, fcm_token, platform) \
         VALUES ($1, $2, $3, $4)",
    )
    .bind(device_id)
    .bind(user_id)
    .bind(&body.fcm_token)
    .bind(&body.platform)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %user_id,
        platform = %body.platform,
        device_id = %device_id,
        "device registered"
    );

    Ok((
        StatusCode::CREATED,
        Json(RegisterDeviceResponse { id: device_id }),
    ))
}

/// `DELETE /v1/devices/:token` — désenregistre (soft-delete) le device FCM de l'utilisateur
/// courant identifié par son token FCM. Appelé au logout pour ne plus recevoir de push.
/// Idempotent : token inconnu/déjà supprimé → 204 tout de même.
#[tracing::instrument(skip_all, fields(user_id = %claims.sub))]
pub async fn unregister_device(
    State(state): State<AppState>,
    claims: crate::auth::MeClaims,
    Path(token): Path<String>,
) -> Result<StatusCode, AppError> {
    let user_id = claims.sub;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // RLS device_owner : exige app.current_user_id = app_user_id.
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE device SET deleted_at = now() \
         WHERE app_user_id = $1 AND fcm_token = $2 AND deleted_at IS NULL",
    )
    .bind(user_id)
    .bind(&token)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(user_id = %user_id, "device unregistered");

    Ok(StatusCode::NO_CONTENT)
}
