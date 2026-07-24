//! Handlers suivi orthodontique (#4135), sur `orthodontic_treatment`/
//! `orthodontic_step` (migration 0189, #4134) :
//! - `GET/POST /v1/cabinet/patients/:id/orthodontics`
//! - `POST /v1/cabinet/orthodontics/:id/steps`
//!
//! Pattern JWT `ProPractitionerClaims` + `cabinet_id` du JWT, garde
//! relation-de-soin E.2.16.c §14, sur le modèle de `prescriptions.rs`.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

/// Vérifie que le patient appartient au cabinet (404 sinon) et que le
/// praticien appelant a eu au moins un `appointment` avec lui dans ce
/// cabinet (403 sinon, RLS strict E.2.16.c — §14).
async fn ensure_care_relationship(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    patient_id: Uuid,
    cabinet_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let patient_exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

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

    Ok(())
}

// ── GET/POST /v1/cabinet/patients/:id/orthodontics ──────────────────────────

/// Une étape d'un traitement orthodontique.
#[derive(Serialize)]
pub struct OrthodonticStepDto {
    pub id: Uuid,
    pub step_number: i32,
    pub kind: String,
    pub delivered_at: Option<String>,
    pub conformity_notes: Option<String>,
}

/// Un traitement orthodontique, avec ses étapes ordonnées par `step_number`.
#[derive(Serialize)]
pub struct OrthodonticTreatmentDto {
    pub id: Uuid,
    pub treatment_plan_id: Option<Uuid>,
    #[serde(rename = "type")]
    pub kind: String,
    pub semester_count: i32,
    pub started_at: Option<String>,
    pub status: String,
    pub steps: Vec<OrthodonticStepDto>,
}

/// `GET /v1/cabinet/patients/:id/orthodontics` — liste les traitements
/// orthodontiques du patient, chacun avec ses étapes ordonnées.
///
/// Praticien uniquement. `cabinet_id` extrait du JWT. RLS tenant-scoped.
/// Garde relation-de-soin E.2.16.c §14. Patient inexistant/hors tenant → 404.
pub async fn list_orthodontic_treatments(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<Vec<OrthodonticTreatmentDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    ensure_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub).await?;

    let treatment_rows = sqlx::query(
        "SELECT id, treatment_plan_id, type, semester_count, started_at, status \
         FROM orthodontic_treatment \
         WHERE patient_id = $1 AND cabinet_id = $2 \
         ORDER BY created_at ASC",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut treatments = Vec::with_capacity(treatment_rows.len());
    for row in &treatment_rows {
        let treatment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

        let step_rows = sqlx::query(
            "SELECT id, step_number, kind, delivered_at, conformity_notes \
             FROM orthodontic_step \
             WHERE treatment_id = $1 AND cabinet_id = $2 \
             ORDER BY step_number ASC",
        )
        .bind(treatment_id)
        .bind(claims.cabinet_id)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        let mut steps = Vec::with_capacity(step_rows.len());
        for step in &step_rows {
            steps.push(OrthodonticStepDto {
                id: step.try_get("id").map_err(|_| AppError::Internal)?,
                step_number: step
                    .try_get("step_number")
                    .map_err(|_| AppError::Internal)?,
                kind: step.try_get("kind").map_err(|_| AppError::Internal)?,
                delivered_at: step
                    .try_get::<Option<chrono::NaiveDate>, _>("delivered_at")
                    .map_err(|_| AppError::Internal)?
                    .map(|d| d.to_string()),
                conformity_notes: step
                    .try_get("conformity_notes")
                    .map_err(|_| AppError::Internal)?,
            });
        }

        treatments.push(OrthodonticTreatmentDto {
            id: treatment_id,
            treatment_plan_id: row
                .try_get("treatment_plan_id")
                .map_err(|_| AppError::Internal)?,
            kind: row.try_get("type").map_err(|_| AppError::Internal)?,
            semester_count: row
                .try_get("semester_count")
                .map_err(|_| AppError::Internal)?,
            started_at: row
                .try_get::<Option<chrono::NaiveDate>, _>("started_at")
                .map_err(|_| AppError::Internal)?
                .map(|d| d.to_string()),
            status: row.try_get("status").map_err(|_| AppError::Internal)?,
            steps,
        });
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(treatments))
}

/// Body de `POST /v1/cabinet/patients/:id/orthodontics`.
#[derive(Deserialize)]
pub struct CreateOrthodonticTreatmentBody {
    #[serde(rename = "type")]
    pub kind: String,
    pub semester_count: i32,
    pub treatment_plan_id: Option<Uuid>,
    pub started_at: Option<String>,
    pub status: Option<String>,
}

/// Réponse de `POST /v1/cabinet/patients/:id/orthodontics`.
#[derive(Serialize)]
pub struct CreateOrthodonticTreatmentResponse {
    pub treatment_id: Uuid,
}

const VALID_TREATMENT_STATUSES: [&str; 4] = ["planned", "in_progress", "completed", "discontinued"];

/// `POST /v1/cabinet/patients/:id/orthodontics` — crée un traitement
/// orthodontique.
///
/// `type` non vide, `semester_count > 0`, `status` (si fourni) valeur de
/// `VALID_TREATMENT_STATUSES` **et non terminal** (`completed`/
/// `discontinued` refusés à la création, #4366 — `add_orthodontic_step`
/// refuse déjà toute étape sur ces statuts, un traitement né terminal est
/// un cul-de-sac immédiat) → 422 sinon. `treatment_plan_id` (si fourni)
/// doit exister dans ce cabinet → 404 sinon (FK 23503 remontée en 500
/// sinon, cf. précédent `prescriptions.rs`).
pub async fn create_orthodontic_treatment(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
    Json(body): Json<CreateOrthodonticTreatmentBody>,
) -> Result<(StatusCode, Json<CreateOrthodonticTreatmentResponse>), AppError> {
    if body.kind.trim().is_empty() || body.semester_count <= 0 {
        return Err(AppError::ValidationError);
    }
    if let Some(ref status) = body.status {
        if !VALID_TREATMENT_STATUSES.contains(&status.as_str()) {
            return Err(AppError::ValidationError);
        }
        // #4366 : completed/discontinued sont des statuts TERMINAUX
        // (add_orthodontic_step, plus bas, refuse en 409 toute étape sur un
        // traitement dans l'un de ces deux états, #4308). Un traitement créé
        // directement dans cet état est un cul-de-sac immédiat, sans aucune
        // étape possible ensuite — seuls planned/in_progress sont des
        // statuts de départ valides.
        if status == "completed" || status == "discontinued" {
            return Err(AppError::ValidationError);
        }
    }
    let started_at: Option<chrono::NaiveDate> = body
        .started_at
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    ensure_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub).await?;

    if let Some(plan_id) = body.treatment_plan_id {
        let plan_exists = sqlx::query(
            "SELECT 1 FROM treatment_plan WHERE id = $1 AND cabinet_id = $2 AND patient_id = $3",
        )
        .bind(plan_id)
        .bind(claims.cabinet_id)
        .bind(patient_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        if plan_exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    let row = sqlx::query(
        "INSERT INTO orthodontic_treatment \
         (cabinet_id, patient_id, treatment_plan_id, type, semester_count, started_at, status) \
         VALUES ($1, $2, $3, $4, $5, $6, COALESCE($7, 'planned')) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(body.treatment_plan_id)
    .bind(body.kind.trim())
    .bind(body.semester_count)
    .bind(started_at)
    .bind(body.status.as_deref())
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let treatment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        treatment_id = %treatment_id,
        "orthodontic treatment created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateOrthodonticTreatmentResponse { treatment_id }),
    ))
}

// ── POST /v1/cabinet/orthodontics/:id/steps ──────────────────────────────────

/// Body de `POST /v1/cabinet/orthodontics/:id/steps`.
#[derive(Deserialize)]
pub struct AddOrthodonticStepBody {
    pub step_number: i32,
    pub kind: String,
    pub delivered_at: Option<String>,
    pub conformity_notes: Option<String>,
}

/// Réponse de `POST /v1/cabinet/orthodontics/:id/steps`.
#[derive(Serialize)]
pub struct AddOrthodonticStepResponse {
    pub step_id: Uuid,
}

const VALID_STEP_KINDS: [&str; 3] = ["bague", "contention", "gouttiere"];

/// `POST /v1/cabinet/orthodontics/:id/steps` — ajoute une étape à un
/// traitement orthodontique.
///
/// Traitement inexistant/hors tenant → 404. Garde relation-de-soin E.2.16.c
/// §14 sur le patient du traitement. `kind` doit être une valeur de
/// `VALID_STEP_KINDS`, `step_number > 0` → 422 sinon. `step_number` déjà
/// utilisé pour ce traitement → 409 (index unique `(treatment_id,
/// step_number)`, migration 0189). Traitement en statut terminal
/// (`completed`/`discontinued`) → 409 invalid_status (#4308,
/// QA-20260722-4) : un traitement terminé ne doit plus muter cliniquement,
/// même garde que `lab_work_orders::is_forward_transition`.
pub async fn add_orthodontic_step(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(treatment_id): Path<Uuid>,
    Json(body): Json<AddOrthodonticStepBody>,
) -> Result<(StatusCode, Json<AddOrthodonticStepResponse>), AppError> {
    if body.step_number <= 0 || !VALID_STEP_KINDS.contains(&body.kind.as_str()) {
        return Err(AppError::ValidationError);
    }
    let delivered_at: Option<chrono::NaiveDate> = body
        .delivered_at
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let treatment_row = sqlx::query(
        "SELECT patient_id, status FROM orthodontic_treatment WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(treatment_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let patient_id: Uuid = treatment_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;
    let treatment_status: String = treatment_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;

    // #4308 : completed/discontinued sont des statuts terminaux — un
    // traitement clos ne doit plus recevoir de nouvelle étape clinique.
    if treatment_status == "completed" || treatment_status == "discontinued" {
        return Err(AppError::InvalidStatus);
    }

    ensure_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub).await?;

    let row = sqlx::query(
        "INSERT INTO orthodontic_step \
         (cabinet_id, treatment_id, step_number, kind, delivered_at, conformity_notes) \
         VALUES ($1, $2, $3, $4, $5, $6) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(treatment_id)
    .bind(body.step_number)
    .bind(&body.kind)
    .bind(delivered_at)
    .bind(&body.conformity_notes)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            AppError::StepNumberTaken
        }
        _ => AppError::Internal,
    })?;

    let step_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        treatment_id = %treatment_id,
        step_id = %step_id,
        "orthodontic step added"
    );

    Ok((
        StatusCode::CREATED,
        Json(AddOrthodonticStepResponse { step_id }),
    ))
}
