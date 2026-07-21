//! `POST /v1/cabinet/patients/:id/merge` (#4102) — expose `merge_patient()`
//! (fonction SQL SECURITY DEFINER, migration 0178, #4101) en API admin-only,
//! auditée.
//!
//! Module dédié plutôt qu'ajout à `patient_detail.rs` : responsabilité
//! distincte (mutation destructive vs lecture), garde le fichier lecture
//! focalisé sur `get_cabinet_patient`.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::Deserialize;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminClaims},
    AppState,
};

/// Body de `POST /v1/cabinet/patients/:id/merge` — `:id` est le patient
/// CIBLE (qui survit à la fusion), `source_patient_id` le doublon fusionné
/// puis soft-supprimé.
#[derive(Deserialize)]
pub struct MergePatientBody {
    pub source_patient_id: Uuid,
}

/// `POST /v1/cabinet/patients/:id/merge` — fusionne un dossier doublon dans
/// le patient `:id`.
///
/// Admin uniquement (`ProAdminClaims`) — secretary/practitioner → 403.
/// `source_patient_id == :id` → 422. L'un des deux hors cabinet ou déjà
/// supprimé → 404 (vérifié explicitement avant l'appel SQL : `merge_patient`
/// est SECURITY DEFINER et refuse déjà les cabinets différents, mais avec un
/// message d'erreur SQL brut plutôt qu'un 404 propre côté API — anti-oracle
/// d'existence cross-tenant, même souci que d'autres handlers du crate).
/// Audite `merge_patient` dans `audit_log` (la fonction SQL elle-même ne le
/// fait pas : `actor_id`/`actor_role` ne sont connus qu'ici, côté API).
pub async fn merge_cabinet_patient(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Path(target_patient_id): Path<Uuid>,
    Json(body): Json<MergePatientBody>,
) -> Result<StatusCode, AppError> {
    if body.source_patient_id == target_patient_id {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    for patient_id in [body.source_patient_id, target_patient_id] {
        let exists = sqlx::query(
            "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
        )
        .bind(patient_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    sqlx::query("SELECT merge_patient($1, $2)")
        .bind(body.source_patient_id)
        .bind(target_patient_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'admin', 'merge_patient', 'patient', $3)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(target_patient_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(StatusCode::OK)
}
