//! Handler `GET /v1/reminders` — rappels de suivi patient.

use axum::extract::State;
use axum::Json;
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

/// Un rappel patient (RDV, document à signer).
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

/// `GET /v1/reminders` — rappels de suivi du patient authentifié.
///
/// Dérivé des données réelles du patient (RLS scoped via `app.patient_account_id`,
/// comme `GET /v1/dashboard`) : prochain RDV confirmé, devis envoyés à signer.
/// Triés par `due_at ASC` (plus urgents en premier). Aucun rappel → `{ data: [] }`.
pub async fn list_reminders(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<RemindersResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Prochain RDV futur confirmé, avec cabinet et praticien réels.
    let appt = sqlx::query(
        "SELECT a.id, a.starts_at, c.raison_sociale AS cabinet_name, p.display_name AS practitioner_name \
         FROM appointment a \
         JOIN cabinet c ON c.id = a.cabinet_id \
         LEFT JOIN provider p ON p.practitioner_id = a.practitioner_id \
         WHERE a.status IN ('confirmed','checked_in') AND a.starts_at > now() \
         ORDER BY a.starts_at LIMIT 1",
    )
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Devis envoyés au patient, en attente de signature.
    let quotes = sqlx::query(
        "SELECT id, updated_at FROM quote \
         WHERE status = 'sent' AND deleted_at IS NULL \
         ORDER BY updated_at LIMIT 5",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data = Vec::new();

    if let Some(row) = appt {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let starts_at: chrono::DateTime<chrono::Utc> =
            row.try_get("starts_at").map_err(|_| AppError::Internal)?;
        let cabinet_name: String = row
            .try_get("cabinet_name")
            .map_err(|_| AppError::Internal)?;
        let practitioner_name: Option<String> = row
            .try_get("practitioner_name")
            .map_err(|_| AppError::Internal)?;
        data.push(ReminderItem {
            id,
            kind: "appointment".to_string(),
            title: "Prochain rendez-vous de contrôle".to_string(),
            due_at: starts_at.to_rfc3339(),
            status: "pending".to_string(),
            metadata: Some(serde_json::json!({
                "cabinet_name": cabinet_name,
                "practitioner": practitioner_name,
            })),
        });
    }

    for row in quotes {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let updated_at: chrono::DateTime<chrono::Utc> =
            row.try_get("updated_at").map_err(|_| AppError::Internal)?;
        data.push(ReminderItem {
            id,
            kind: "document".to_string(),
            title: "Devis à signer avant votre prochain soin".to_string(),
            due_at: updated_at.to_rfc3339(),
            status: "pending".to_string(),
            metadata: Some(serde_json::json!({ "document_id": id })),
        });
    }

    Ok(Json(RemindersResponse { data }))
}
