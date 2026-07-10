//! Handler `GET /v1/reminders` — rappels de suivi et prévention patient.

use axum::extract::State;
use axum::Json;
use serde::Serialize;
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
/// Version 🎭 : données mockées (prochain RDV, document à signer, prévention).
/// Triés par `due_at ASC` (plus urgents en premier).
/// Aucun rappel → `{ data: [] }`.
pub async fn list_reminders(
    State(_state): State<AppState>,
    _claims: PatientAccountClaims,
) -> Result<Json<RemindersResponse>, AppError> {
    let data = vec![
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
            id: uuid::uuid!("b2c3d4e5-f6a7-8901-bcde-f12345678901"),
            kind: "document".to_string(),
            title: "Devis à signer avant votre prochain soin".to_string(),
            due_at: "2026-06-20T00:00:00Z".to_string(),
            status: "pending".to_string(),
            metadata: Some(serde_json::json!({
                "document_id": "d3e4f5a6-b7c8-9012-cdef-123456789012"
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

    Ok(Json(RemindersResponse { data }))
}
