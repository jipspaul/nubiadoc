//! Handler `GET /v1/reminders` — rappels de suivi et prévention patient.

use axum::extract::State;
use axum::Json;
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

/// Un rappel patient (RDV, document à signer, prévention).
#[derive(Serialize)]
pub struct ReminderItem {
    pub id: Uuid,
    #[serde(rename = "type")]
    pub kind: String,
    pub title: String,
    pub due_at: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub metadata: Option<serde_json::Value>,
}

/// Réponse de `GET /v1/reminders`.
#[derive(Serialize)]
pub struct RemindersResponse {
    pub data: Vec<ReminderItem>,
}

/// `GET /v1/reminders` — rappels de suivi et prévention du patient authentifié.
///
/// Le rappel `type:"appointment"` est dérivé du prochain RDV futur confirmé du
/// patient (cabinet/praticien réels). Aucun RDV à venir → aucun rappel `appointment`
/// (pas de fallback mocké).
/// Triés par `due_at ASC` (plus urgents en premier).
/// Aucun rappel → `{ data: [] }`.
pub async fn list_reminders(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<RemindersResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — appointment_patient_read (policy 0029).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Prochain RDV futur confirmé — même critère que GET /v1/dashboard.
    let appt = sqlx::query(
        "SELECT id, starts_at, cabinet_id, practitioner_id FROM appointment \
         WHERE status IN ('confirmed','checked_in') AND starts_at > now() \
         ORDER BY starts_at LIMIT 1",
    )
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut data = Vec::new();

    if let Some(row) = appt {
        let appt_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let starts_at: chrono::DateTime<chrono::Utc> =
            row.try_get("starts_at").map_err(|_| AppError::Internal)?;
        let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
        let practitioner_id: Uuid = row
            .try_get("practitioner_id")
            .map_err(|_| AppError::Internal)?;

        // Scope cabinet pour lire raison_sociale + provider (tenant_isolation).
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let cabinet_name: Option<String> =
            sqlx::query("SELECT raison_sociale FROM cabinet WHERE id = $1")
                .bind(cabinet_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
                .map(|r| r.try_get("raison_sociale"))
                .transpose()
                .map_err(|_| AppError::Internal)?;

        let practitioner: Option<String> =
            sqlx::query("SELECT display_name FROM provider WHERE practitioner_id = $1 LIMIT 1")
                .bind(practitioner_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
                .map(|r| r.try_get("display_name"))
                .transpose()
                .map_err(|_| AppError::Internal)?;

        data.push(ReminderItem {
            id: appt_id,
            kind: "appointment".to_string(),
            title: "Prochain rendez-vous de contrôle".to_string(),
            due_at: starts_at.to_rfc3339(),
            status: "pending".to_string(),
            metadata: Some(serde_json::json!({
                "cabinet_name": cabinet_name,
                "practitioner": practitioner
            })),
        });
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(RemindersResponse { data }))
}
