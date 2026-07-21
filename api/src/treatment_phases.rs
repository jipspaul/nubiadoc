//! Handler `POST /v1/cabinet/treatment-plans/:id/phases` (#4050).
//!
//! Un plan de traitement sans phase est inutilisable côté patient (§4.1) —
//! ce handler crée une phase et permet, dans le même appel, de rattacher des
//! `quote_item` déjà existants via `phase_id` (colonne posée par la
//! migration 0010, jusqu'ici jamais renseignée hors seed SQL).
//!
//! `cabinet_id` extrait du JWT, jamais du path/body (invariant tenancy) —
//! même garanties que `dental_chart.rs`/`treatment_plans::create_treatment_plan`.
//! RLS `tenant_isolation` scoped via `app.current_cabinet_id`.

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

/// Corps de `POST /v1/cabinet/treatment-plans/:id/phases`.
#[derive(Deserialize)]
pub struct CreateTreatmentPhaseBody {
    pub title: String,
    pub position: i32,
    /// Actes déjà existants (devis) à rattacher à cette phase — optionnel.
    /// Seuls les `quote_item` du même cabinet sont rattachés ; les ids d'un
    /// autre tenant sont silencieusement ignorés (RLS/tenant isolation).
    #[serde(default)]
    pub quote_item_ids: Vec<Uuid>,
}

/// Réponse de `POST /v1/cabinet/treatment-plans/:id/phases`.
#[derive(Serialize)]
pub struct CreateTreatmentPhaseResponse {
    pub phase_id: Uuid,
}

/// `POST /v1/cabinet/treatment-plans/:id/phases` — ajoute une phase à un plan.
///
/// Praticien uniquement (via `ProPractitionerClaims`). Plan inexistant ou
/// hors tenant → 404. `title` vide → 422. Statut initial : `requested`.
/// Réponse `201 { phase_id }`.
pub async fn create_treatment_phase(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(plan_id): Path<Uuid>,
    Json(body): Json<CreateTreatmentPhaseBody>,
) -> Result<(StatusCode, Json<CreateTreatmentPhaseResponse>), AppError> {
    let title = body.title.trim().to_string();
    if title.is_empty() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le plan appartient au cabinet (RLS garantit le cloisonnement).
    let plan_exists = sqlx::query(
        "SELECT 1 FROM treatment_plan WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(plan_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if plan_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let phase_id: Uuid = sqlx::query(
        "INSERT INTO treatment_phase (cabinet_id, plan_id, position, title, status) \
         VALUES ($1, $2, $3, $4, 'requested') RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(plan_id)
    .bind(body.position)
    .bind(&title)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .try_get("id")
    .map_err(|_| AppError::Internal)?;

    if !body.quote_item_ids.is_empty() {
        sqlx::query("UPDATE quote_item SET phase_id = $1 WHERE id = ANY($2) AND cabinet_id = $3")
            .bind(phase_id)
            .bind(&body.quote_item_ids)
            .bind(claims.cabinet_id)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        plan_id = %plan_id,
        phase_id = %phase_id,
        attached_items = body.quote_item_ids.len(),
        "treatment phase created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateTreatmentPhaseResponse { phase_id }),
    ))
}
