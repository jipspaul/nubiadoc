//! Handlers `GET /v1/cabinet/patients/:id/dental-chart` et
//! `PUT /v1/cabinet/patients/:id/dental-chart` (§14).
//!
//! Accès praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
//! PUT atomique : remplace intégralement `teeth_status` jsonb.
//! `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
//! RLS `tenant_isolation` scoped via `app.current_cabinet_id`.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

// ── Structures ────────────────────────────────────────────────────────────────

/// Réponse de `GET /v1/cabinet/patients/:id/dental-chart`.
#[derive(Serialize)]
pub struct DentalChartResponse {
    pub teeth: Value,
    pub updated_at: String,
}

/// Corps de `PUT /v1/cabinet/patients/:id/dental-chart`.
#[derive(Deserialize)]
pub struct PutDentalChartBody {
    pub teeth: Value,
}

// ── GET /v1/cabinet/patients/:id/dental-chart ─────────────────────────────────

/// `GET /v1/cabinet/patients/:id/dental-chart` — odontogramme du patient.
///
/// Praticien uniquement (R.4127-72) — secrétaire → 403 (via `ProPractitionerClaims`).
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS `tenant_isolation` scoped via `app.current_cabinet_id`.
/// Patient inexistant ou hors tenant → 404.
/// Si aucun enregistrement → retourne `{ teeth: {}, updated_at: <now> }`.
pub async fn get_dental_chart(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<DentalChartResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le cloisonnement).
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

    let row = sqlx::query(
        "SELECT teeth_status, updated_at FROM dental_chart \
         WHERE patient_id = $1 AND cabinet_id = $2 \
         ORDER BY updated_at DESC LIMIT 1",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let response = match row {
        None => DentalChartResponse {
            teeth: serde_json::json!({}),
            updated_at: chrono::Utc::now().to_rfc3339(),
        },
        Some(r) => {
            let teeth: Value = r.try_get("teeth_status").map_err(|_| AppError::Internal)?;
            let updated_at: chrono::DateTime<chrono::Utc> =
                r.try_get("updated_at").map_err(|_| AppError::Internal)?;
            DentalChartResponse {
                teeth,
                updated_at: updated_at.to_rfc3339(),
            }
        }
    };

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        "dental chart read"
    );

    Ok(Json(response))
}

// ── PUT /v1/cabinet/patients/:id/dental-chart ─────────────────────────────────

/// `PUT /v1/cabinet/patients/:id/dental-chart` — remplacement atomique de l'odontogramme.
///
/// Praticien uniquement (R.4127-72) — secrétaire → 403 (via `ProPractitionerClaims`).
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS `tenant_isolation` scoped via `app.current_cabinet_id`.
/// Patient inexistant ou hors tenant → 404.
/// PUT atomique : `teeth_status` est remplacé intégralement.
/// Réponse : `200 { updated_at }`.
pub async fn put_dental_chart(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
    Json(body): Json<PutDentalChartBody>,
) -> Result<Json<DentalChartResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le cloisonnement).
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

    // UPSERT atomique : remplace intégralement teeth_status.
    let row = sqlx::query(
        "INSERT INTO dental_chart (cabinet_id, patient_id, teeth_status, updated_at) \
         VALUES ($1, $2, $3, now()) \
         ON CONFLICT (patient_id, cabinet_id) \
         DO UPDATE SET teeth_status = EXCLUDED.teeth_status, updated_at = now() \
         RETURNING teeth_status, updated_at",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(&body.teeth)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let teeth: Value = row
        .try_get("teeth_status")
        .map_err(|_| AppError::Internal)?;
    let updated_at: chrono::DateTime<chrono::Utc> =
        row.try_get("updated_at").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        "dental chart updated"
    );

    Ok(Json(DentalChartResponse {
        teeth,
        updated_at: updated_at.to_rfc3339(),
    }))
}
