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

/// Valide un code dent ISO 3950 (notation FDI) : `<quadrant><dent>`,
/// quadrant 1-4 (dentition permanente, dents 1-8) ou 5-8 (temporaire, 1-5).
/// Même règle que `dental_chart.rs::validate_teeth` (#3680) — dupliquée ici
/// faute de module de validation partagé pour une fonction aussi courte.
fn is_valid_fdi_tooth(code: &str) -> bool {
    code.len() == 2 && code.chars().all(|c| c.is_ascii_digit()) && {
        let quadrant = code.as_bytes()[0] - b'0';
        let tooth = code.as_bytes()[1] - b'0';
        match quadrant {
            1..=4 => (1..=8).contains(&tooth),
            5..=8 => (1..=5).contains(&tooth),
            _ => false,
        }
    }
}

/// `POST /v1/cabinet/treatment-plans/:id/phases` — ajoute une phase à un plan.
///
/// Praticien uniquement (via `ProPractitionerClaims`). Plan inexistant ou
/// hors tenant → 404. `title` vide, `position` négatif (rang d'ordonnancement
/// clinique, trié `ORDER BY position ASC`), un `inline_acts[].label` vide,
/// `amount_cents` négatif, `tooth` hors numérotation FDI (#4368), ou plan
/// déjà `done` (terminal — #4386) → 422.
/// Statut initial : `requested`. Réponse `201 { phase_id }`.
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
    if body.position < 0 {
        return Err(AppError::ValidationError);
    }
    for act in &body.inline_acts {
        if act.label.trim().is_empty() || act.amount_cents < 0 {
            return Err(AppError::ValidationError);
        }
        if let Some(tooth) = &act.tooth {
            if !is_valid_fdi_tooth(tooth) {
                return Err(AppError::ValidationError);
            }
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
        "SELECT patient_id, status FROM treatment_plan \
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
    let plan_status: String = plan_row.try_get("status").map_err(|_| AppError::Internal)?;
    // Plan déjà `done` (terminal) : ajouter une phase ouverte le laisserait
    // figé `done` avec du travail en cours (#4386) — sync_plan_status_from_phases
    // est forward-only (jamais done -> in_progress) et n'est de toute façon
    // appelée qu'au PATCH d'une phase existante, pas à la création.
    if plan_status == "done" {
        return Err(AppError::ValidationError);
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

/// Ordre du plan (migration 0010) — même pattern `[...]`/`position()` que
/// `PHASE_STATUS_ORDER`. `proposed`/`accepted` n'ont aucun déclencheur dans
/// ce backend (aucune route ne les pose — hors scope #4348, nécessiterait un
/// flux d'acceptation patient non spécifié) ; seule la dérivation
/// mécanique `in_progress`/`done` à partir des phases est implémentée ici.
const PLAN_STATUS_ORDER: [&str; 5] = ["draft", "proposed", "accepted", "in_progress", "done"];

/// #4348 : la machine à états du plan était morte (`status` restait `draft`
/// à vie, aucun `UPDATE treatment_plan SET status` nulle part) — incohérent
/// avec les phases, qui progressent normalement. Dérive `in_progress`/`done`
/// à partir de l'état agrégé des phases, dans la même transaction que la
/// mise à jour de la phase qui vient de changer. Ne régresse jamais
/// (`PLAN_STATUS_ORDER`, même discipline "forward-only" que les phases).
async fn sync_plan_status_from_phases(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    plan_id: Uuid,
    cabinet_id: Uuid,
) -> Result<(), AppError> {
    let counts = sqlx::query(
        "SELECT count(*) AS total, \
                count(*) FILTER (WHERE status = 'done') AS done_count, \
                count(*) FILTER (WHERE status IN ('in_progress', 'done')) AS active_count \
         FROM treatment_phase WHERE plan_id = $1 AND cabinet_id = $2",
    )
    .bind(plan_id)
    .bind(cabinet_id)
    .fetch_one(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let total: i64 = counts.try_get("total").map_err(|_| AppError::Internal)?;
    let done_count: i64 = counts
        .try_get("done_count")
        .map_err(|_| AppError::Internal)?;
    let active_count: i64 = counts
        .try_get("active_count")
        .map_err(|_| AppError::Internal)?;

    let derived = if total > 0 && done_count == total {
        Some("done")
    } else if active_count > 0 {
        Some("in_progress")
    } else {
        None
    };
    let Some(derived) = derived else {
        return Ok(());
    };

    let plan_row =
        sqlx::query("SELECT status FROM treatment_plan WHERE id = $1 AND cabinet_id = $2")
            .bind(plan_id)
            .bind(cabinet_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;
    let Some(plan_row) = plan_row else {
        return Ok(());
    };
    let current: String = plan_row.try_get("status").map_err(|_| AppError::Internal)?;

    let (Some(from), Some(to)) = (
        PLAN_STATUS_ORDER.iter().position(|s| *s == current),
        PLAN_STATUS_ORDER.iter().position(|s| *s == derived),
    ) else {
        return Ok(());
    };
    if to <= from {
        return Ok(());
    }

    sqlx::query("UPDATE treatment_plan SET status = $1, updated_at = now() WHERE id = $2 AND cabinet_id = $3")
        .bind(derived)
        .bind(plan_id)
        .bind(cabinet_id)
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
    Ok(())
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
/// `treatment_plan.status` est synchronisé dans la même transaction
/// (#4348 — `sync_plan_status_from_phases` : `in_progress` dès qu'une phase
/// est `in_progress`/`done`, `done` quand toutes le sont ; jamais de
/// régression). `proposed`/`accepted` restent hors de portée de cette
/// route (aucun déclencheur métier défini pour ces deux statuts).
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

    sync_plan_status_from_phases(&mut tx, plan_id, claims.cabinet_id).await?;

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
