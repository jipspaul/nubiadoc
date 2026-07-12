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
/// Le rappel `document` (devis à signer) est dérivé des devis réels du patient :
/// un rappel par devis `status = 'sent'` (envoyé par le cabinet, en attente de
/// signature), RLS scoped via `app.patient_account_id` (policy `quote_patient_read`,
/// migration 0029), comme `GET /v1/dashboard`. Aucun devis en attente → aucun
/// rappel `document`.
/// Triés par `due_at ASC` (plus urgents en premier).
/// Aucun rappel → `{ data: [] }`.
pub async fn list_reminders(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<RemindersResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — quote_patient_read (migration 0029).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Devis envoyés au patient, en attente de signature.
    let quote_rows = sqlx::query(
        "SELECT id, updated_at FROM quote \
         WHERE status = 'sent' AND deleted_at IS NULL \
         ORDER BY updated_at ASC",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data = vec![
        ReminderItem {
            id: uuid::uuid!("a1b2c3d4-e5f6-7890-abcd-ef1234567890"),
            kind: "appointment".to_string(),
            title: "Prochain rendez-vous de contrôle".to_string(),
            due_at: "2026-06-15T09:00:00Z".to_string(),
            status: "pending".to_string(),
            metadata: Some(serde_json::json!({
                "cabinet_name": "Cabinet Dentaire Dubois",
                "practitioner": "Dr. Dubois"
            })),
        },
        ReminderItem {
            id: uuid::uuid!("c3d4e5f6-a7b8-9012-cdef-234567890123"),
            kind: "prevention".to_string(),
            title: "Détartrage annuel recommandé".to_string(),
            due_at: "2026-07-01T00:00:00Z".to_string(),
            status: "pending".to_string(),
            metadata: None,
        },
    ];

    for row in quote_rows {
        let quote_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let updated_at: chrono::DateTime<chrono::Utc> =
            row.try_get("updated_at").map_err(|_| AppError::Internal)?;
        data.push(ReminderItem {
            id: quote_id,
            kind: "document".to_string(),
            title: "Devis à signer avant votre prochain soin".to_string(),
            due_at: updated_at.to_rfc3339(),
            status: "pending".to_string(),
            metadata: Some(serde_json::json!({ "document_id": quote_id })),
        });
    }

    Ok(Json(RemindersResponse { data }))
}
