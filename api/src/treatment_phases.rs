//! Handlers `/v1/cabinet/treatment-plans/:id/phases` :
//! - `POST` (#4050) crée une phase.
//! - `PATCH .../phases/:phaseId` (#4262) fait progresser son statut.
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

/// Un acte CCAM inline (#4263) : créé comme `quote_item` (nouveau devis
/// `draft`) dans le même appel que la phase, plutôt que de nécessiter un
/// devis pré-existant.
#[derive(Deserialize)]
pub struct InlineTreatmentPhaseAct {
    pub label: String,
    #[serde(default)]
    pub ccam_code: Option<String>,
    #[serde(default)]
    pub tooth: Option<String>,
    pub amount_cents: i32,
}

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
    /// Actes CCAM à créer directement (#4263) — utile pour peupler une phase
    /// dès la création du plan, quand aucun `quote_item` n'existe encore.
    /// Crée un nouveau devis `draft` (total = somme des actes) et ses
    /// `quote_item`, rattachés à cette phase. Combinable avec
    /// `quote_item_ids` (les deux mécanismes sont indépendants).
    #[serde(default)]
    pub inline_acts: Vec<InlineTreatmentPhaseAct>,
}

/// Réponse de `POST /v1/cabinet/treatment-plans/:id/phases`.
#[derive(Serialize)]
pub struct CreateTreatmentPhaseResponse {
    pub phase_id: Uuid,
}

/// `POST /v1/cabinet/treatment-plans/:id/phases` — ajoute une phase à un plan.
///
/// Praticien uniquement (via `ProPractitionerClaims`). Plan inexistant ou
/// hors tenant → 404. `title` vide, ou un `inline_acts[].label` vide/
/// `amount_cents` négatif → 422. Statut initial : `requested`.
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
    for act in &body.inline_acts {
        if act.label.trim().is_empty() || act.amount_cents < 0 {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le plan appartient au cabinet (RLS garantit le cloisonnement) ;
    // récupère patient_id pour le devis inline (#4263), si besoin.
    let plan_row = sqlx::query(
        "SELECT patient_id FROM treatment_plan \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(plan_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(plan_row) = plan_row else {
        return Err(AppError::NotFound);
    };
    let patient_id: Uuid = plan_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

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

    if !body.inline_acts.is_empty() {
        let total_cents: i64 = body
            .inline_acts
            .iter()
            .map(|act| i64::from(act.amount_cents))
            .sum();

        let quote_id: Uuid = sqlx::query(
            "INSERT INTO quote (cabinet_id, patient_id, status, total_amount, currency) \
             VALUES ($1, $2, 'draft', $3::numeric / 100, 'EUR') RETURNING id",
        )
        .bind(claims.cabinet_id)
        .bind(patient_id)
        .bind(total_cents)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get("id")
        .map_err(|_| AppError::Internal)?;

        for act in &body.inline_acts {
            sqlx::query(
                "INSERT INTO quote_item \
                 (cabinet_id, quote_id, phase_id, label, ccam_code, tooth, unit_amount) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7::numeric / 100)",
            )
            .bind(claims.cabinet_id)
            .bind(quote_id)
            .bind(phase_id)
            .bind(act.label.trim())
            .bind(&act.ccam_code)
            .bind(&act.tooth)
            .bind(act.amount_cents)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        }
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        plan_id = %plan_id,
        phase_id = %phase_id,
        attached_items = body.quote_item_ids.len(),
        inline_acts = body.inline_acts.len(),
        "treatment phase created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateTreatmentPhaseResponse { phase_id }),
    ))
}

// ── PATCH /v1/cabinet/treatment-plans/:planId/phases/:phaseId ────────────────

/// Ordre de progression légal — une transition n'est autorisée que vers un
/// statut de rang STRICTEMENT supérieur (retour arrière interdit), même
/// pattern que `lab_work_orders.rs::STATUS_ORDER` (#4148).
const PHASE_STATUS_ORDER: [&str; 4] = ["requested", "confirmed", "in_progress", "done"];

fn is_forward_transition(current: &str, target: &str) -> bool {
    let (Some(from), Some(to)) = (
        PHASE_STATUS_ORDER.iter().position(|s| *s == current),
        PHASE_STATUS_ORDER.iter().position(|s| *s == target),
    ) else {
        return false;
    };
    to > from
}

/// Corps de `PATCH /v1/cabinet/treatment-plans/:planId/phases/:phaseId`.
#[derive(Deserialize)]
pub struct PatchTreatmentPhaseBody {
    pub status: String,
}

/// Réponse de `PATCH /v1/cabinet/treatment-plans/:planId/phases/:phaseId`.
#[derive(Serialize)]
pub struct PatchTreatmentPhaseResponse {
    pub status: String,
}

/// `PATCH /v1/cabinet/treatment-plans/:planId/phases/:phaseId` — fait
/// progresser le statut d'une phase (#4262).
///
/// Praticien uniquement (via `ProPractitionerClaims`). Phase inexistante,
/// hors tenant, ou hors du plan indiqué dans le path → 404. Transition vers
/// un statut de rang inférieur ou égal (retour arrière, statut inconnu) →
/// `409 invalid_status` — mêmes règles que `lab_work_orders.rs` (#4148) : la
/// progression n'a pas besoin d'être séquentielle (`requested → done`
/// autorisé, saute `confirmed`/`in_progress`), seulement croissante.
pub async fn patch_treatment_phase(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path((plan_id, phase_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<PatchTreatmentPhaseBody>,
) -> Result<Json<PatchTreatmentPhaseResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT status FROM treatment_phase \
         WHERE id = $1 AND plan_id = $2 AND cabinet_id = $3",
    )
    .bind(phase_id)
    .bind(plan_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let current_status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    if !is_forward_transition(&current_status, &body.status) {
        return Err(AppError::InvalidStatus);
    }

    sqlx::query("UPDATE treatment_phase SET status = $1 WHERE id = $2 AND cabinet_id = $3")
        .bind(&body.status)
        .bind(phase_id)
        .bind(claims.cabinet_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        plan_id = %plan_id,
        phase_id = %phase_id,
        from = %current_status,
        to = %body.status,
        "treatment phase status updated"
    );

    Ok(Json(PatchTreatmentPhaseResponse {
        status: body.status,
    }))
}
