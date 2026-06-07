//! Handler `POST /v1/devices` — enregistrement d'un device FCM.

use axum::{extract::State, http::StatusCode, Json};
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
pub async fn register_device(
    State(state): State<AppState>,
    claims: crate::auth::MeClaims,
    Json(body): Json<RegisterDeviceBody>,
) -> Result<(StatusCode, Json<RegisterDeviceResponse>), AppError> {
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
