//! Handler `GET /v1/cabinet/patients/:id/prescriptions` — historique des
//! ordonnances d'un patient, vue cabinet (#4132).
//!
//! Module dédié plutôt qu'un ajout à `prescriptions.rs` (déjà > 500 lignes,
//! proche du seuil de confort CLAUDE.md) — réutilise son DTO partagé
//! `PrescriptionDto`/`PrescriptionItemDto` (même shape que
//! `GET /v1/cabinet/prescriptions/:id`, pour que le front puisse consommer
//! les deux réponses avec le même modèle `Prescription`).

use axum::{
    extract::{Path, State},
    Json,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    prescriptions::{PrescriptionDto, PrescriptionItemDto},
    AppState,
};

/// Réponse de `GET /v1/cabinet/patients/:id/prescriptions`.
#[derive(Serialize)]
pub struct PatientPrescriptionsResponse {
    pub data: Vec<PrescriptionDto>,
}

/// `GET /v1/cabinet/patients/:id/prescriptions` — historique des ordonnances
/// d'un patient (#4132, préalable au bouton "Renouveler" côté Flutter).
///
/// Praticien uniquement (`ProPractitionerClaims`). `patient_id` (path)
/// inexistant ou hors tenant → `404`. Garde §14 (relation de soin, même
/// pattern que `prescriptions.rs::create_prescription`) : praticien sans
/// `appointment` avec ce patient → `403`. Trié `created_at DESC`, brouillons
/// inclus (contrairement à `list_account_prescriptions` côté patient — ici
/// le praticien doit voir ses propres brouillons en cours).
pub async fn list_patient_prescriptions(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<PatientPrescriptionsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let patient_exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // Garde §14 (relation de soin) — même pattern que prescriptions.rs.
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
           AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    let presc_rows = sqlx::query(
        "SELECT id, patient_id, consultation_id, status, signed_at, document_id, created_at \
         FROM prescription \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         ORDER BY created_at DESC \
         LIMIT 100",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut data: Vec<PrescriptionDto> = Vec::with_capacity(presc_rows.len());
    for row in presc_rows {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let signed_at: Option<chrono::DateTime<chrono::Utc>> =
            row.try_get("signed_at").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        let item_rows = sqlx::query(
            "SELECT id, label, form, posology, duration, quantity \
             FROM prescription_item \
             WHERE prescription_id = $1 AND cabinet_id = $2",
        )
        .bind(id)
        .bind(claims.cabinet_id)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        let items = item_rows
            .into_iter()
            .map(|r| {
                Ok(PrescriptionItemDto {
                    id: r.try_get("id").map_err(|_| AppError::Internal)?,
                    label: r.try_get("label").map_err(|_| AppError::Internal)?,
                    form: r.try_get("form").map_err(|_| AppError::Internal)?,
                    posology: r.try_get("posology").map_err(|_| AppError::Internal)?,
                    duration: r.try_get("duration").map_err(|_| AppError::Internal)?,
                    quantity: r.try_get("quantity").map_err(|_| AppError::Internal)?,
                })
            })
            .collect::<Result<Vec<_>, AppError>>()?;

        data.push(PrescriptionDto {
            id,
            patient_id: row.try_get("patient_id").map_err(|_| AppError::Internal)?,
            consultation_id: row
                .try_get("consultation_id")
                .map_err(|_| AppError::Internal)?,
            status: row.try_get("status").map_err(|_| AppError::Internal)?,
            signed_at: signed_at.map(|t| t.to_rfc3339()),
            document_id: row.try_get("document_id").map_err(|_| AppError::Internal)?,
            created_at: created_at.to_rfc3339(),
            items,
        });
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        count = data.len(),
        "patient prescriptions listed"
    );

    Ok(Json(PatientPrescriptionsResponse { data }))
}
