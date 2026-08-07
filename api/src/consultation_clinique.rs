//! Handlers `POST /v1/cabinet/appointments/:id/consultation-clinique` et
//! `POST /v1/cabinet/consultation-clinique/:id/finalize` — compte-rendu
//! clinique post-RDV rédigé par le praticien (table `consultation_clinique`,
//! migration 0113).
//!
//! Cycle de vie : `draft` -> `finalized` (irréversible, `status IN
//! ('draft', 'finalized')`). Le patient titulaire du RDV peut lire un
//! compte-rendu `finalized` (RLS `consultation_clinique_patient_read`,
//! migration 0113) via `GET /v1/appointments/:id/consultation-clinique`.
//!
//! Chiffrement applicatif : stub `STUB_ENC:` (même convention que
//! `medical_record.rs`, AES-256-GCM/KMS Scaleway à NUB-T3).

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, ProPractitionerClaims},
    medical_record::{decrypt_stub, encrypt_stub},
    AppState,
};

/// Corps de `POST /v1/cabinet/appointments/:id/consultation-clinique`.
#[derive(Deserialize)]
pub struct CreateConsultationCliniqueBody {
    pub content: String,
}

/// Réponse commune aux endpoints praticien de ce module.
#[derive(Serialize)]
pub struct ConsultationCliniqueResponse {
    pub id: Uuid,
    pub appointment_id: Uuid,
    pub status: String,
}

/// `POST /v1/cabinet/appointments/:id/consultation-clinique` — crée (en
/// `draft`) le compte-rendu clinique du RDV.
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`
/// (`consultation_clinique_cabinet_isolation`).
/// - Séance (RDV) inexistant ou hors tenant → 404.
/// - Seul le praticien du RDV peut créer le compte-rendu → 403 sinon.
/// - Un compte-rendu existe déjà pour ce RDV (contrainte `UNIQUE
///   appointment_id`) → 409.
pub async fn create_consultation_clinique(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(appointment_id): Path<Uuid>,
    Json(body): Json<CreateConsultationCliniqueBody>,
) -> Result<(StatusCode, Json<ConsultationCliniqueResponse>), AppError> {
    if body.content.trim().is_empty() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Le RDV doit appartenir au cabinet du token et au praticien appelant.
    let appointment_row = sqlx::query(
        "SELECT a.id, p.id AS practitioner_id \
         FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.id = $1 AND a.cabinet_id = $2 AND a.deleted_at IS NULL",
    )
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let practitioner_id: Uuid = appointment_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    let prac_row = sqlx::query(
        "SELECT id FROM practitioner WHERE id = $1 AND user_id = $2 AND cabinet_id = $3",
    )
    .bind(practitioner_id)
    .bind(claims.sub)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if prac_row.is_none() {
        return Err(AppError::Forbidden);
    }

    let existing = sqlx::query(
        "SELECT 1 FROM consultation_clinique WHERE appointment_id = $1 AND cabinet_id = $2",
    )
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if existing.is_some() {
        return Err(AppError::Conflict);
    }

    let ciphertext = encrypt_stub(&serde_json::json!({ "content": body.content.trim() }));

    let row = sqlx::query(
        "INSERT INTO consultation_clinique \
         (cabinet_id, appointment_id, practitioner_id, content_ciphertext, content_key_ref, status) \
         VALUES ($1, $2, $3, $4, 'stub-key-ref', 'draft') \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(appointment_id)
    .bind(practitioner_id)
    .bind(&ciphertext)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        appointment_id = %appointment_id,
        "consultation clinique created (draft)"
    );

    Ok((
        StatusCode::CREATED,
        Json(ConsultationCliniqueResponse {
            id,
            appointment_id,
            status: "draft".to_string(),
        }),
    ))
}

/// `POST /v1/cabinet/consultation-clinique/:id/finalize` — passe le
/// compte-rendu de `draft` à `finalized` (irréversible).
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// - Compte-rendu inexistant ou hors tenant → 404.
/// - Seul le praticien auteur du compte-rendu peut le finaliser → 403 sinon.
/// - Déjà `finalized` → 409 (transition non permise, cf. `AppError::InvalidStatus`).
pub async fn finalize_consultation_clinique(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<ConsultationCliniqueResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT cc.appointment_id, cc.status, p.id AS practitioner_id \
         FROM consultation_clinique cc \
         JOIN practitioner p ON p.id = cc.practitioner_id \
         WHERE cc.id = $1 AND cc.cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let appointment_id: Uuid = row
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    let prac_row = sqlx::query(
        "SELECT id FROM practitioner WHERE id = $1 AND user_id = $2 AND cabinet_id = $3",
    )
    .bind(practitioner_id)
    .bind(claims.sub)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if prac_row.is_none() {
        return Err(AppError::Forbidden);
    }

    if status != "draft" {
        return Err(AppError::InvalidStatus);
    }

    sqlx::query(
        "UPDATE consultation_clinique SET status = 'finalized', updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_clinique_id = %id,
        "consultation clinique finalized"
    );

    Ok(Json(ConsultationCliniqueResponse {
        id,
        appointment_id,
        status: "finalized".to_string(),
    }))
}

/// Réponse de `GET /v1/appointments/:id/consultation-clinique` (patient).
#[derive(Serialize)]
pub struct PatientConsultationCliniqueResponse {
    pub id: Uuid,
    pub content: String,
    pub status: String,
}

/// `GET /v1/appointments/:id/consultation-clinique` — lecture patient du
/// compte-rendu clinique finalisé de son RDV.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id`
/// (`consultation_clinique_patient_read`, migration 0113) : seul le patient
/// titulaire du RDV peut lire, et seulement s'il est `finalized` (un
/// brouillon praticien n'est jamais exposé au patient).
/// Aucun compte-rendu finalisé pour ce RDV (inexistant, hors tenant, ou
/// encore `draft`) → 404.
pub async fn get_patient_consultation_clinique(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appointment_id): Path<Uuid>,
) -> Result<Json<PatientConsultationCliniqueResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, content_ciphertext, status FROM consultation_clinique \
         WHERE appointment_id = $1 AND status = 'finalized'",
    )
    .bind(appointment_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let ciphertext: Option<Vec<u8>> = row
        .try_get("content_ciphertext")
        .map_err(|_| AppError::Internal)?;

    let content = ciphertext
        .and_then(|ct| decrypt_stub(&ct))
        .and_then(|data| data["content"].as_str().map(|s| s.to_string()))
        .unwrap_or_default();

    Ok(Json(PatientConsultationCliniqueResponse {
        id,
        content,
        status,
    }))
}
