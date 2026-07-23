//! Handler `POST /v1/cabinet/recall-campaigns` (#4151), sur `reminder`
//! (`kind='recall_annual'`, `appointment_id NULL` — nullable depuis #4150).
//!
//! `ProSecretaryPlusClaims` (secretary/practitioner/admin/manager) : tâche
//! opérationnelle du cabinet, pas une décision clinique.

use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Body de `POST /v1/cabinet/recall-campaigns`.
#[derive(Deserialize)]
pub struct CreateRecallCampaignBody {
    /// Seuil d'éligibilité : patient sans RDV honoré (`status='done'`)
    /// depuis plus de `months_since_last_appointment` mois (ou jamais).
    pub months_since_last_appointment: i32,
}

/// Réponse de `POST /v1/cabinet/recall-campaigns`.
#[derive(Serialize)]
pub struct CreateRecallCampaignResponse {
    pub created_count: i64,
}

/// `POST /v1/cabinet/recall-campaigns` — crée en masse des `reminder`
/// (`kind='recall_annual'`, `appointment_id NULL`) pour les patients du
/// cabinet sans RDV honoré depuis plus de N mois.
///
/// `months_since_last_appointment` doit être dans `1..=1200` → 422 sinon
/// (#4345 — la borne haute évite un débordement `timestamptz` dans
/// `now() - make_interval(months => N)`). Un patient déjà titulaire
/// d'un rappel `recall_annual` `pending` est exclu (évite les doublons si la
/// campagne est déclenchée plusieurs fois).
pub async fn create_recall_campaign(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateRecallCampaignBody>,
) -> Result<(StatusCode, Json<CreateRecallCampaignResponse>), AppError> {
    // #4345 : au-dela de ~80000 mois, `now() - make_interval(months => N)`
    // sort de la plage timestamptz de Postgres (< 4713 av. J.-C.) -> erreur
    // SQL mappee en 500 au lieu d'un refus de validation. 1200 mois (100 ans)
    // est deja tres au-dela de toute campagne de relance realiste.
    if !(1..=1200).contains(&body.months_since_last_appointment) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "INSERT INTO reminder (cabinet_id, patient_id, scheduled_at, kind) \
         SELECT p.cabinet_id, p.id, now(), 'recall_annual' \
         FROM patient p \
         WHERE p.cabinet_id = $1 \
           AND p.deleted_at IS NULL \
           AND NOT EXISTS ( \
             SELECT 1 FROM appointment a \
             WHERE a.patient_id = p.id \
               AND a.cabinet_id = $1 \
               AND a.status = 'done' \
               AND a.starts_at > now() - make_interval(months => $2) \
           ) \
           AND NOT EXISTS ( \
             SELECT 1 FROM reminder r \
             WHERE r.patient_id = p.id \
               AND r.cabinet_id = $1 \
               AND r.kind = 'recall_annual' \
               AND r.status = 'pending' \
           ) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.months_since_last_appointment)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let created_count = rows.len() as i64;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        months = body.months_since_last_appointment,
        created_count,
        "recall campaign triggered"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateRecallCampaignResponse { created_count }),
    ))
}
