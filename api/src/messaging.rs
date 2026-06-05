//! Handler pour la messagerie patient : POST /v1/conversations.

use axum::{extract::State, http::StatusCode, response::IntoResponse, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

/// Corps de la requête `POST /v1/conversations`.
#[derive(Deserialize)]
pub struct CreateConversationBody {
    pub cabinet_id: Uuid,
}

/// Réponse de `POST /v1/conversations`.
#[derive(Serialize)]
pub struct CreateConversationResponse {
    pub conversation_id: Uuid,
    pub existing: bool,
}

/// `POST /v1/conversations` — démarre un fil de messagerie patient ↔ cabinet.
///
/// Idempotent : un seul fil par couple `(patient_account_id, cabinet_id)` — contrainte
/// DB unique. Cabinet inexistant ou non listé (`is_listed=false`) → `404`.
/// Fil existant → `200 + existing:true`. Nouveau fil → `201 + existing:false`.
pub async fn create_conversation(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<CreateConversationBody>,
) -> Result<impl IntoResponse, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Vérifie que le cabinet a au moins un praticien listé (lecture publique sans GUC).
    let listed =
        sqlx::query("SELECT 1 FROM provider WHERE cabinet_id = $1 AND is_listed = true LIMIT 1")
            .bind(body.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    if listed.is_none() {
        return Err(AppError::NotFound);
    }

    // Scope RLS au cabinet cible pour la table conversation (SET LOCAL — scoped à tx).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(body.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Tente l'insertion — ON CONFLICT DO NOTHING pour l'idempotence.
    let row = sqlx::query(
        "INSERT INTO conversation (patient_account_id, cabinet_id) \
         VALUES ($1, $2) \
         ON CONFLICT (patient_account_id, cabinet_id) DO NOTHING \
         RETURNING id",
    )
    .bind(claims.account_id)
    .bind(body.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (conversation_id, existing) = if let Some(r) = row {
        let id: Uuid = r.try_get("id").map_err(|_| AppError::Internal)?;
        (id, false)
    } else {
        // Fil existant — le récupérer (RLS via GUC déjà positionné).
        let existing_row = sqlx::query(
            "SELECT id FROM conversation \
             WHERE patient_account_id = $1 AND cabinet_id = $2",
        )
        .bind(claims.account_id)
        .bind(body.cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        let id: Uuid = existing_row.try_get("id").map_err(|_| AppError::Internal)?;
        (id, true)
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        patient_account_id = %claims.account_id,
        cabinet_id = %body.cabinet_id,
        conversation_id = %conversation_id,
        existing,
        "conversation created or fetched"
    );

    let response = CreateConversationResponse {
        conversation_id,
        existing,
    };

    if existing {
        Ok((StatusCode::OK, Json(response)).into_response())
    } else {
        Ok((StatusCode::CREATED, Json(response)).into_response())
    }
}
