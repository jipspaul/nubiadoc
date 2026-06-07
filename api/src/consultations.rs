//! Handler `GET /v1/cabinet/consultations/:id` — contexte clinique d'une séance.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

/// Un acte CCAM réalisé pendant la séance.
#[derive(Serialize)]
pub struct ConsultationActItem {
    pub id: Uuid,
    pub ccam_code: String,
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tooth: Option<String>,
    pub amount_cents: i32,
}

/// Sous-objet praticien dans la réponse.
#[derive(Serialize)]
pub struct PractitionerSummary {
    pub id: Uuid,
    pub display_name: String,
}

/// Réponse de `GET /v1/cabinet/consultations/:id`.
#[derive(Serialize)]
pub struct ConsultationContextResponse {
    pub id: Uuid,
    pub appointment_id: Uuid,
    pub status: String,
    pub started_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<String>,
    pub practitioner: PractitionerSummary,
    /// Note clinique déchiffrée. `None` si aucune note ou clé KMS non disponible (NUB-T3).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    pub acts: Vec<ConsultationActItem>,
}

/// `GET /v1/cabinet/consultations/:id` — contexte clinique d'une séance au fauteuil.
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
/// Note clinique : déchiffrée côté serveur via `core/crypto` (NUB-T3 — `None` si scaffold).
/// Séance inexistante ou hors tenant → 404.
pub async fn get_consultation_context(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<ConsultationContextResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Séance + display_name du praticien via provider (peut être NULL si provider absent).
    let session_row = sqlx::query(
        "SELECT cs.id, cs.appointment_id, cs.practitioner_id, cs.status, \
                cs.started_at, cs.completed_at, cs.note_ciphertext, cs.note_key_ref, \
                COALESCE(p.display_name, '') AS display_name \
         FROM consultation_session cs \
         LEFT JOIN provider p ON p.practitioner_id = cs.practitioner_id \
                              AND p.cabinet_id = cs.cabinet_id \
         WHERE cs.id = $1 AND cs.cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let session_id: Uuid = session_row.try_get("id").map_err(|_| AppError::Internal)?;
    let appointment_id: Uuid = session_row
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = session_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = session_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let started_at: chrono::DateTime<chrono::Utc> = session_row
        .try_get("started_at")
        .map_err(|_| AppError::Internal)?;
    let completed_at: Option<chrono::DateTime<chrono::Utc>> = session_row
        .try_get("completed_at")
        .map_err(|_| AppError::Internal)?;
    let note_ciphertext: Option<Vec<u8>> = session_row
        .try_get("note_ciphertext")
        .map_err(|_| AppError::Internal)?;
    let display_name: String = session_row
        .try_get("display_name")
        .map_err(|_| AppError::Internal)?;

    // Note : déchiffrement via core/crypto (NUB-T3). Pour l'instant le crate est un
    // scaffold (CryptoError::NotImplemented) → on retourne None si ciphertext présent.
    let note: Option<String> = if note_ciphertext.is_some() {
        // TODO(NUB-T3) : appeler core_crypto::decrypt_column(ciphertext, key_ref, kms).
        None
    } else {
        None
    };

    // Actes CCAM de la séance.
    let act_rows = sqlx::query(
        "SELECT id, ccam_code, label, tooth, amount_cents \
         FROM consultation_act \
         WHERE appointment_id = $1 AND cabinet_id = $2 \
         ORDER BY created_at ASC",
    )
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut acts: Vec<ConsultationActItem> = Vec::with_capacity(act_rows.len());
    for row in act_rows {
        let act_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let ccam_code: String = row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
        let amount_cents: i32 = row
            .try_get("amount_cents")
            .map_err(|_| AppError::Internal)?;
        acts.push(ConsultationActItem {
            id: act_id,
            ccam_code,
            label,
            tooth,
            amount_cents,
        });
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_id = %session_id,
        "consultation context queried"
    );

    Ok(Json(ConsultationContextResponse {
        id: session_id,
        appointment_id,
        status,
        started_at: started_at.to_rfc3339(),
        completed_at: completed_at.map(|t| t.to_rfc3339()),
        practitioner: PractitionerSummary {
            id: practitioner_id,
            display_name,
        },
        note,
        acts,
    }))
}
