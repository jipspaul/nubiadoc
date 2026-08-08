//! `GET /v1/appointments/:id/consultation-clinique` — lecture patient du
//! compte-rendu clinique finalisé d'un RDV (table `consultation_clinique`,
//! migration 0113). Issue #4646.
//!
//! La table `consultation_clinique` porte le compte-rendu de consultation
//! rédigé par le praticien (#4645) : jusqu'ici scaffoldée en DB (RLS,
//! contraintes) mais jamais exposée côté API. Ce handler couvre la lecture
//! patient : seul un compte-rendu `status = 'finalized'` est restitué (un
//! brouillon `draft` reste invisible au patient, cf. cycle de vie §0113).
//!
//! Ownership vérifié par la policy RLS `consultation_clinique_patient_read`
//! (appointment → patient → patient_account_id) : un compte-rendu d'un
//! autre patient ou un RDV inexistant renvoie `404` (anti-énumération),
//! cohérent avec `appointments_read::get_appointment`.

use axum::extract::{Path, State};
use axum::Json;
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    clinical::stub_decrypt,
    AppState,
};

#[derive(Serialize)]
pub struct ConsultationCliniqueResponse {
    pub id: Uuid,
    pub appointment_id: Uuid,
    pub practitioner_id: Uuid,
    pub status: String,
    /// Contenu du compte-rendu déchiffré (stub — KMS à NUB-T3). `None` si
    /// aucun contenu n'a été renseigné.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

/// `GET /v1/appointments/:id/consultation-clinique` — compte-rendu clinique
/// finalisé du RDV `:id`, pour le patient titulaire.
///
/// Token `kind:"patient"` requis. Seul un enregistrement `status =
/// 'finalized'` est restitué ; un compte-rendu encore `draft` (ou absent)
/// renvoie `404`, comme s'il n'existait pas — le patient ne doit jamais
/// distinguer "brouillon en cours" de "aucun compte-rendu".
pub async fn get_patient_consultation_clinique(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<ConsultationCliniqueResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient pour consultation_clinique_patient_read (migration 0113).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, appointment_id, practitioner_id, status, content_ciphertext, \
                created_at, updated_at \
         FROM consultation_clinique \
         WHERE appointment_id = $1 AND status = 'finalized'",
    )
    .bind(appt_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let appointment_id: Uuid = row
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let ciphertext: Option<Vec<u8>> = row
        .try_get("content_ciphertext")
        .map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    let updated_at: chrono::DateTime<chrono::Utc> =
        row.try_get("updated_at").map_err(|_| AppError::Internal)?;

    let content = ciphertext.and_then(|c| stub_decrypt(&c));

    Ok(Json(ConsultationCliniqueResponse {
        id,
        appointment_id,
        practitioner_id,
        status,
        content,
        created_at: created_at.to_rfc3339(),
        updated_at: updated_at.to_rfc3339(),
    }))
}
