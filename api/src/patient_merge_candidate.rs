//! `GET /v1/cabinet/patient-merge-candidates`,
//! `POST /v1/cabinet/patient-merge-candidates/:id/resolve` (#3916, lot
//! interop A5) — résolution humaine des doublons patient flagués
//! automatiquement (table `patient_merge_candidate`, migration 0226,
//! RLS `cabinet_id`).
//!
//! Pas de fusion automatique en v1 (conforme à l'issue) : `resolve` marque
//! juste le candidat `resolved`/`dismissed` — c'est à l'admin d'appeler
//! ensuite `POST /v1/cabinet/patients/:id/merge` (#4102, `patient_merge.rs`)
//! s'il juge, après vérification humaine, qu'il s'agit d'un vrai doublon.
//! `dismissed` couvre le cas homonymie/erreur de saisie où les deux fiches
//! doivent rester distinctes.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminClaims},
    AppState,
};

#[derive(Deserialize)]
pub struct ListMergeCandidatesQuery {
    /// Filtre optionnel sur `status` (`pending`/`resolved`/`dismissed`) —
    /// défaut `pending` (les seuls candidats qui nécessitent une action).
    pub status: Option<String>,
}

#[derive(Serialize)]
pub struct MergeCandidateItem {
    pub id: Uuid,
    pub patient_a_id: Uuid,
    pub patient_b_id: Uuid,
    pub reason: String,
    pub status: String,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct ListMergeCandidatesResponse {
    pub data: Vec<MergeCandidateItem>,
}

const VALID_STATUSES: [&str; 3] = ["pending", "resolved", "dismissed"];

/// `GET /v1/cabinet/patient-merge-candidates` — liste les doublons flagués
/// pour ce cabinet (RLS `app.current_cabinet_id`).
///
/// Admin uniquement (`ProAdminClaims`) — même restriction que la fusion
/// elle-même (#4102), la revue de doublons est une action de gouvernance
/// des données, pas une tâche secrétariat/praticien courante.
/// `?status=` hors énum → `422 {"code":"validation_error"}`.
pub async fn list_merge_candidates(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Query(query): Query<ListMergeCandidatesQuery>,
) -> Result<Json<ListMergeCandidatesResponse>, AppError> {
    let status = query.status.as_deref().unwrap_or("pending");
    if !VALID_STATUSES.contains(&status) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, patient_a_id, patient_b_id, reason, status, created_at \
         FROM patient_merge_candidate \
         WHERE status = $1 \
         ORDER BY created_at DESC",
    )
    .bind(status)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in rows {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let patient_a_id: Uuid = row
            .try_get("patient_a_id")
            .map_err(|_| AppError::Internal)?;
        let patient_b_id: Uuid = row
            .try_get("patient_b_id")
            .map_err(|_| AppError::Internal)?;
        let reason: String = row.try_get("reason").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        data.push(MergeCandidateItem {
            id,
            patient_a_id,
            patient_b_id,
            reason,
            status,
            created_at: created_at.to_rfc3339(),
        });
    }

    Ok(Json(ListMergeCandidatesResponse { data }))
}

#[derive(Deserialize)]
pub struct ResolveMergeCandidateBody {
    /// `resolved` (doublon confirmé, fusion à faire séparément via
    /// `POST /v1/cabinet/patients/:id/merge`) ou `dismissed` (faux positif,
    /// ex. homonymie — les deux fiches restent distinctes).
    pub outcome: String,
}

const VALID_OUTCOMES: [&str; 2] = ["resolved", "dismissed"];

/// `POST /v1/cabinet/patient-merge-candidates/:id/resolve` — clôture un
/// candidat en `resolved` ou `dismissed`. N'effectue AUCUNE fusion (v1 :
/// résolution humaine uniquement, cf. doc de module).
///
/// Admin uniquement. Candidat hors cabinet ou déjà résolu → `404`
/// (anti-oracle, même pattern que les autres handlers du crate). `outcome`
/// hors énum → `422`.
pub async fn resolve_merge_candidate(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Path(candidate_id): Path<Uuid>,
    Json(body): Json<ResolveMergeCandidateBody>,
) -> Result<StatusCode, AppError> {
    if !VALID_OUTCOMES.contains(&body.outcome.as_str()) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let updated = sqlx::query(
        "UPDATE patient_merge_candidate \
         SET status = $1, resolved_by = $2, resolved_at = now() \
         WHERE id = $3 AND cabinet_id = $4 AND status = 'pending'",
    )
    .bind(&body.outcome)
    .bind(claims.sub)
    .bind(candidate_id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if updated.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'admin', 'resolve_merge_candidate', 'patient_merge_candidate', $3)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(candidate_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(StatusCode::OK)
}
