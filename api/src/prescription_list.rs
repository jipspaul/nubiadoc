//! Handler `GET /v1/cabinet/patients/:id/prescriptions` — historique des
//! ordonnances d'un patient, vue cabinet (#4132).
//!
//! Module dédié plutôt qu'un ajout à `prescriptions.rs` (déjà > 500 lignes,
//! proche du seuil de confort CLAUDE.md) — réutilise son DTO partagé
//! `PrescriptionDto`/`PrescriptionItemDto` (même shape que
//! `GET /v1/cabinet/prescriptions/:id`, pour que le front puisse consommer
//! les deux réponses avec le même modèle `Prescription`).

use axum::{
    extract::{Path, Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    prescriptions::{
        decode_prescriptions_cursor, encode_prescriptions_cursor, PrescriptionDto,
        PrescriptionItemDto,
    },
    AppState,
};

/// Pagination cursor de `page.next_cursor` — même schéma que la vue patient
/// (`list_account_prescriptions`, #6381).
#[derive(Serialize)]
pub struct PatientPrescriptionsPageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
    /// Nombre total d'ordonnances du patient, indépendant de la pagination.
    pub total: i64,
}

/// Réponse de `GET /v1/cabinet/patients/:id/prescriptions`.
#[derive(Serialize)]
pub struct PatientPrescriptionsResponse {
    pub data: Vec<PrescriptionDto>,
    pub page: PatientPrescriptionsPageInfo,
}

#[derive(Deserialize)]
pub struct ListPatientPrescriptionsQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
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
///
/// Paginée par curseur (`limit`/`cursor`, `page.total`), même schéma que
/// `list_account_prescriptions` (#6381) : avant #8478, `LIMIT 100` était
/// figé en dur sans aucun extracteur `Query`, rendant 342/442 ordonnances
/// d'un même patient structurellement inatteignables côté cabinet.
pub async fn list_patient_prescriptions(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
    Query(params): Query<ListPatientPrescriptionsQuery>,
) -> Result<Json<PatientPrescriptionsResponse>, AppError> {
    // Défaut à 100 (comportement historique du `LIMIT 100` en dur) pour ne
    // pas régresser les clients existants qui n'envoient pas `limit`.
    let limit: i64 = params.limit.unwrap_or(100).clamp(1, 100);
    let cursor = match params.cursor.as_deref() {
        Some(s) => Some(decode_prescriptions_cursor(s).ok_or(AppError::ValidationError)?),
        None => None,
    };
    let fetch_limit = limit + 1;

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

    let presc_rows = match cursor {
        Some((cursor_at, cursor_id)) => sqlx::query(
            "SELECT id, patient_id, consultation_id, status, signed_at, document_id, created_at \
             FROM prescription \
             WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
               AND (created_at < $3 OR (created_at = $3 AND id < $4)) \
             ORDER BY created_at DESC, id DESC LIMIT $5",
        )
        .bind(patient_id)
        .bind(claims.cabinet_id)
        .bind(cursor_at)
        .bind(cursor_id)
        .bind(fetch_limit)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?,
        None => sqlx::query(
            "SELECT id, patient_id, consultation_id, status, signed_at, document_id, created_at \
             FROM prescription \
             WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
             ORDER BY created_at DESC, id DESC LIMIT $3",
        )
        .bind(patient_id)
        .bind(claims.cabinet_id)
        .bind(fetch_limit)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?,
    };

    let total: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM prescription \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let has_more = presc_rows.len() > limit as usize;
    let presc_rows = if has_more {
        &presc_rows[..limit as usize]
    } else {
        &presc_rows[..]
    };

    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    let mut data: Vec<PrescriptionDto> = Vec::with_capacity(presc_rows.len());
    for row in presc_rows {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let signed_at: Option<chrono::DateTime<chrono::Utc>> =
            row.try_get("signed_at").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        last_created_at = Some(created_at);
        last_id = Some(id);

        let item_rows = sqlx::query(
            "SELECT id, label, form, posology, duration, quantity, \
                    structured_posology, product_reference, non_substitution_reason, non_renouvelable \
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
                    structured_posology: r
                        .try_get("structured_posology")
                        .map_err(|_| AppError::Internal)?,
                    product_reference: r
                        .try_get("product_reference")
                        .map_err(|_| AppError::Internal)?,
                    non_substitution_reason: r
                        .try_get("non_substitution_reason")
                        .map_err(|_| AppError::Internal)?,
                    non_renouvelable: r
                        .try_get("non_renouvelable")
                        .map_err(|_| AppError::Internal)?,
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

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| encode_prescriptions_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        count = data.len(),
        "patient prescriptions listed"
    );

    Ok(Json(PatientPrescriptionsResponse {
        data,
        page: PatientPrescriptionsPageInfo {
            next_cursor,
            limit,
            total,
        },
    }))
}
