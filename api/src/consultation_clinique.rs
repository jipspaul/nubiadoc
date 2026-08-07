//! Handlers `POST /v1/cabinet/consultations/:id/clinical-note` (création
//! du compte-rendu clinique, `draft`) et
//! `POST /v1/cabinet/consultations/:id/clinical-note/finalize`
//! (`draft` -> `finalized`) sur la table `consultation_clinique`
//! (migration 0113, jamais câblée côté API — issue #4645).
//!
//! Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
//! `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
//! RLS `consultation_clinique_cabinet_isolation` scoped via
//! `app.current_cabinet_id`. Contenu chiffré (stub `medical_record::encrypt_stub`),
//! jamais stocké/retourné en clair.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    medical_record::encrypt_stub,
    AppState,
};

/// Corps de `POST /v1/cabinet/consultations/:id/clinical-note`.
#[derive(Deserialize)]
pub struct CreateClinicalNoteBody {
    pub content: String,
}

/// Réponse commune create/finalize.
#[derive(Serialize)]
pub struct ClinicalNoteResponse {
    pub id: Uuid,
    pub status: String,
}

/// `POST /v1/cabinet/consultations/:id/clinical-note` — crée (ou renvoie si
/// déjà existant) le compte-rendu clinique en `draft` pour ce RDV.
///
/// `:id` est l'id de `appointment` (cohérent avec les autres routes
/// `/v1/cabinet/consultations/:id/*`). Le praticien doit être celui du RDV.
/// Un seul compte-rendu par RDV (`appointment_id UNIQUE`) : si un existe
/// déjà, retourne l'existant plutôt que de créer un doublon.
pub async fn create_clinical_note(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(appointment_id): Path<Uuid>,
    Json(body): Json<CreateClinicalNoteBody>,
) -> Result<Json<ClinicalNoteResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Le praticien doit être celui rattaché à ce RDV, dans son cabinet.
    let practitioner_row = sqlx::query(
        "SELECT p.id FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.id = $1 AND a.cabinet_id = $2 AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let practitioner_row = practitioner_row.ok_or(AppError::NotFound)?;
    let practitioner_id: Uuid = practitioner_row
        .try_get("id")
        .map_err(|_| AppError::Internal)?;

    if let Some(existing) = sqlx::query(
        "SELECT id, status FROM consultation_clinique WHERE appointment_id = $1 AND cabinet_id = $2",
    )
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    {
        let id: Uuid = existing.try_get("id").map_err(|_| AppError::Internal)?;
        let status: String = existing.try_get("status").map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(ClinicalNoteResponse { id, status }));
    }

    let ciphertext = encrypt_stub(&json!({ "content": body.content }));

    let row = sqlx::query(
        "INSERT INTO consultation_clinique \
         (cabinet_id, appointment_id, practitioner_id, content_ciphertext, content_key_ref, status) \
         VALUES ($1, $2, $3, $4, 'stub', 'draft') \
         RETURNING id, status",
    )
    .bind(claims.cabinet_id)
    .bind(appointment_id)
    .bind(practitioner_id)
    .bind(ciphertext)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    Ok(Json(ClinicalNoteResponse { id, status }))
}

/// `POST /v1/cabinet/consultations/:id/clinical-note/finalize` — passe le
/// compte-rendu clinique du RDV de `draft` à `finalized`.
///
/// `:id` est l'id de `appointment`. 404 si aucun compte-rendu n'existe pour
/// ce RDV dans ce cabinet. Idempotent-safe : re-finaliser un compte-rendu
/// déjà `finalized` renvoie simplement son état courant.
pub async fn finalize_clinical_note(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(appointment_id): Path<Uuid>,
) -> Result<Json<ClinicalNoteResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "UPDATE consultation_clinique SET status = 'finalized', updated_at = now() \
         WHERE appointment_id = $1 AND cabinet_id = $2 \
         RETURNING id, status",
    )
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    Ok(Json(ClinicalNoteResponse { id, status }))
}
