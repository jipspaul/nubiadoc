//! Handlers du questionnaire médical patient pré-consultation (#4108, table
//! `medical_questionnaire_submission`, migration 0180).
//!
//! Trois routes :
//! - `POST /v1/account/medical-questionnaire` (patient) : crée un brouillon.
//! - `PATCH /v1/account/medical-questionnaire` (patient) : modifie le
//!   brouillon existant, et/ou le soumet (`submit: true`).
//! - `GET /v1/cabinet/patients/:id/medical-questionnaire` (praticien) : lit
//!   la dernière soumission — RLS (`medical_questionnaire_submission_cabinet_read`,
//!   migration 0180) masque déjà les brouillons, non soumis au cabinet.
//!
//! Un seul brouillon actif par (patient_account_id, cabinet_id) — pas de
//! contrainte d'unicité en base (aucune demandée par l'issue), garde
//! applicative : `POST` renvoie 409 si un brouillon existe déjà, `PATCH` 404
//! si aucun brouillon n'existe (ou qu'il a déjà été soumis — pas de
//! modification après soumission, non demandée par l'issue).
//!
//! Garde praticien identique à `dental_chart.rs`/`periodontal_chart.rs`
//! (R.4127-72) : un `appointment` (passé ou à venir) avec ce patient est
//! requis — un rendez-vous réservé suffit à autoriser la lecture du
//! questionnaire avant la consultation, cas d'usage central de cette issue.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, ProPractitionerClaims},
    AppState,
};

// ── Structures ────────────────────────────────────────────────────────────

/// Réponse commune aux trois routes.
#[derive(Serialize)]
pub struct MedicalQuestionnaireResponse {
    pub id: Uuid,
    pub cabinet_id: Uuid,
    pub payload: Value,
    pub status: String,
    pub submitted_at: Option<String>,
}

/// Corps de `POST /v1/account/medical-questionnaire`.
#[derive(Deserialize)]
pub struct CreateMedicalQuestionnaireBody {
    pub cabinet_id: Uuid,
    pub payload: Value,
}

/// Corps de `PATCH /v1/account/medical-questionnaire`.
#[derive(Deserialize)]
pub struct PatchMedicalQuestionnaireBody {
    pub cabinet_id: Uuid,
    pub payload: Option<Value>,
    #[serde(default)]
    pub submit: bool,
}

/// `payload` : objet libre (questionnaire libre, aucun vocabulaire fermé
/// n'est demandé par l'issue) — seule contrainte : un objet, pas un
/// scalaire/tableau (même garde minimale que `periodontal_chart`).
fn validate_payload(value: &Value) -> Result<(), AppError> {
    if !value.is_object() {
        return Err(AppError::ValidationError);
    }
    Ok(())
}

fn row_to_response(row: sqlx::postgres::PgRow) -> Result<MedicalQuestionnaireResponse, AppError> {
    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let payload: Value = row.try_get("payload").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let submitted_at: Option<chrono::DateTime<chrono::Utc>> = row
        .try_get("submitted_at")
        .map_err(|_| AppError::Internal)?;

    Ok(MedicalQuestionnaireResponse {
        id,
        cabinet_id,
        payload,
        status,
        submitted_at: submitted_at.map(|d| d.to_rfc3339()),
    })
}

// ── POST /v1/account/medical-questionnaire ──────────────────────────────

/// `POST /v1/account/medical-questionnaire` — crée un brouillon pour le
/// cabinet donné. `409` si un brouillon existe déjà pour ce cabinet.
pub async fn create_medical_questionnaire(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<CreateMedicalQuestionnaireBody>,
) -> Result<Json<MedicalQuestionnaireResponse>, AppError> {
    validate_payload(&body.payload)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing_draft = sqlx::query(
        "SELECT 1 FROM medical_questionnaire_submission \
         WHERE patient_account_id = $1 AND cabinet_id = $2 AND status = 'draft'",
    )
    .bind(claims.account_id)
    .bind(body.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if existing_draft.is_some() {
        return Err(AppError::MedicalQuestionnaireDraftExists);
    }

    let row = sqlx::query(
        "INSERT INTO medical_questionnaire_submission \
           (cabinet_id, patient_account_id, payload) \
         VALUES ($1, $2, $3) \
         RETURNING id, cabinet_id, payload, status, submitted_at",
    )
    .bind(body.cabinet_id)
    .bind(claims.account_id)
    .bind(&body.payload)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        cabinet_id = %body.cabinet_id,
        "medical questionnaire draft created"
    );

    Ok(Json(row_to_response(row)?))
}

// ── PATCH /v1/account/medical-questionnaire ─────────────────────────────

/// `PATCH /v1/account/medical-questionnaire` — modifie le brouillon existant
/// et/ou le soumet (`submit: true`). `404` si aucun brouillon n'existe pour
/// ce cabinet.
pub async fn patch_medical_questionnaire(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<PatchMedicalQuestionnaireBody>,
) -> Result<Json<MedicalQuestionnaireResponse>, AppError> {
    if let Some(ref payload) = body.payload {
        validate_payload(payload)?;
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "UPDATE medical_questionnaire_submission \
         SET payload = COALESCE($3, payload), \
             status = CASE WHEN $4 THEN 'submitted' ELSE status END, \
             submitted_at = CASE WHEN $4 THEN now() ELSE submitted_at END, \
             updated_at = now() \
         WHERE patient_account_id = $1 AND cabinet_id = $2 AND status = 'draft' \
         RETURNING id, cabinet_id, payload, status, submitted_at",
    )
    .bind(claims.account_id)
    .bind(body.cabinet_id)
    .bind(&body.payload)
    .bind(body.submit)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        return Err(AppError::NotFound);
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        cabinet_id = %body.cabinet_id,
        submitted = body.submit,
        "medical questionnaire draft updated"
    );

    Ok(Json(row_to_response(row)?))
}

// ── GET /v1/cabinet/patients/:id/medical-questionnaire ──────────────────

async fn ensure_practitioner_care_relationship(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    patient_id: Uuid,
    cabinet_id: Uuid,
    user_id: Uuid,
) -> Result<Uuid, AppError> {
    let patient = sqlx::query(
        "SELECT patient_account_id FROM patient \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(patient) = patient else {
        return Err(AppError::NotFound);
    };

    let patient_account_id: Option<Uuid> = patient
        .try_get("patient_account_id")
        .map_err(|_| AppError::Internal)?;
    let Some(patient_account_id) = patient_account_id else {
        return Err(AppError::NotFound);
    };

    // Même garde R.4127-72 que dental_chart.rs/periodontal_chart.rs : un
    // appointment (passé OU à venir) avec ce patient dans ce cabinet suffit —
    // un RDV réservé autorise la lecture du questionnaire avant qu'il n'ait
    // lieu, cas d'usage central de cette issue (pré-consultation).
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
           AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(user_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    Ok(patient_account_id)
}

/// `GET /v1/cabinet/patients/:id/medical-questionnaire` — dernière
/// soumission visible du patient (RLS masque déjà les brouillons).
/// `404` si le patient n'existe pas dans ce cabinet, n'a pas de compte
/// plateforme lié, ou n'a aucune soumission visible.
pub async fn get_cabinet_medical_questionnaire(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<MedicalQuestionnaireResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let patient_account_id =
        ensure_practitioner_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub)
            .await?;

    let row = sqlx::query(
        "SELECT id, cabinet_id, payload, status, submitted_at \
         FROM medical_questionnaire_submission \
         WHERE patient_account_id = $1 AND cabinet_id = $2 \
         ORDER BY submitted_at DESC LIMIT 1",
    )
    .bind(patient_account_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        return Err(AppError::NotFound);
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        "medical questionnaire read"
    );

    Ok(Json(row_to_response(row)?))
}
