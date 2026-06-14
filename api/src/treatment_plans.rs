//! Handler pour le parcours de soins patient :
//! GET /v1/treatment-plans — liste paginée des plans de traitement.

use axum::extract::{Path, Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

#[derive(Deserialize)]
pub struct ListTreatmentPlansQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

#[derive(Serialize)]
pub struct TreatmentPlanItem {
    pub id: Uuid,
    pub title: String,
    pub status: String,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

#[derive(Serialize)]
pub struct ListTreatmentPlansResponse {
    pub data: Vec<TreatmentPlanItem>,
    pub page: PageInfo,
}

fn encode_cursor(created_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", created_at.timestamp_micros(), id)
}

fn decode_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/treatment-plans` — parcours de soins patient : liste paginée des plans de traitement.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` (migration 0038).
/// Tri par `created_at DESC`. Pagination cursor-based (`limit` + `cursor`).
/// Aucun plan → `{ data: [], page: { limit } }`.
pub async fn list_treatment_plans(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(params): Query<ListTreatmentPlansQuery>,
) -> Result<Json<ListTreatmentPlansResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let fetch_limit = limit + 1;

    let cursor = params.cursor.as_deref().and_then(decode_cursor);

    let cursor_clause = if cursor.is_some() {
        " AND (tp.created_at < $2 OR (tp.created_at = $2 AND tp.id < $3))"
    } else {
        ""
    };

    let sql = format!(
        "SELECT tp.id, tp.title, tp.status, tp.created_at \
         FROM treatment_plan tp \
         WHERE tp.deleted_at IS NULL\
         {cursor_clause} \
         ORDER BY tp.created_at DESC, tp.id DESC \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — RLS treatment_plan_patient_read (migration 0038).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = match cursor {
        Some((cursor_at, cursor_id)) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cursor_at)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        None => sqlx::query(&sql)
            .bind(fetch_limit)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<TreatmentPlanItem> = Vec::with_capacity(visible.len());
    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let title: String = row.try_get("title").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        last_created_at = Some(created_at);
        last_id = Some(id);

        data.push(TreatmentPlanItem {
            id,
            title,
            status,
            created_at: created_at.to_rfc3339(),
        });
    }

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        account_id = %claims.account_id,
        count = data.len(),
        has_more,
        "treatment plans listed"
    );

    Ok(Json(ListTreatmentPlansResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}

// ---------------------------------------------------------------------------
// GET /v1/treatment-plans/:id
// ---------------------------------------------------------------------------

#[derive(Serialize)]
pub struct TreatmentPlanDetailItem {
    pub label: String,
    pub ccam_code: Option<String>,
    pub unit_amount_cents: i64,
    pub amo_part_cents: i64,
    pub amc_part_cents: i64,
}

#[derive(Serialize)]
pub struct TreatmentPlanPhase {
    pub id: Uuid,
    pub position: i32,
    pub title: String,
    pub status: String,
    pub items: Vec<TreatmentPlanDetailItem>,
}

#[derive(Serialize)]
pub struct TreatmentPlanDetailResponse {
    pub id: Uuid,
    pub title: String,
    pub status: String,
    pub total_cost_cents: i64,
    pub remaining_cents: i64,
    pub amo_part_cents: i64,
    pub amc_part_cents: i64,
    pub phases: Vec<TreatmentPlanPhase>,
}

/// `GET /v1/treatment-plans/:id` — détail d'un plan de traitement avec phases et actes.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` (migration 0038).
/// Vérifie que le plan appartient au patient (via policy RLS + `patient_account_id`).
/// `404 not_found` si l'id est inexistant ou hors patient.
pub async fn get_treatment_plan(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<TreatmentPlanDetailResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — RLS treatment_plan_patient_read (migration 0038).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Fetch the plan header (RLS ensures it belongs to this patient or returns nothing).
    let plan_row = sqlx::query(
        "SELECT tp.id, tp.cabinet_id, tp.title, tp.status \
         FROM treatment_plan tp \
         WHERE tp.id = $1 AND tp.deleted_at IS NULL",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let plan_id: Uuid = plan_row.try_get("id").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = plan_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let plan_title: String = plan_row.try_get("title").map_err(|_| AppError::Internal)?;
    let plan_status: String = plan_row.try_get("status").map_err(|_| AppError::Internal)?;

    // Scope cabinet — RLS treatment_phase / quote_item uses app.current_cabinet_id.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Fetch phases ordered by position.
    let phase_rows = sqlx::query(
        "SELECT tp2.id, tp2.position, tp2.title, tp2.status \
         FROM treatment_phase tp2 \
         WHERE tp2.plan_id = $1 \
         ORDER BY tp2.position ASC",
    )
    .bind(plan_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Fetch all quote_items linked to phases of this plan in one query.
    let item_rows = sqlx::query(
        "SELECT qi.phase_id, qi.label, qi.ccam_code, \
                (qi.unit_amount * 100)::bigint AS unit_amount_cents, \
                COALESCE((qi.amo_part * 100)::bigint, 0) AS amo_part_cents, \
                COALESCE((qi.amc_part * 100)::bigint, 0) AS amc_part_cents \
         FROM quote_item qi \
         JOIN treatment_phase tp3 ON tp3.id = qi.phase_id \
         WHERE tp3.plan_id = $1",
    )
    .bind(plan_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Group items by phase_id.
    let mut items_by_phase: std::collections::HashMap<Uuid, Vec<TreatmentPlanDetailItem>> =
        std::collections::HashMap::new();

    let mut total_cost_cents: i64 = 0;
    let mut total_amo_cents: i64 = 0;
    let mut total_amc_cents: i64 = 0;

    for row in &item_rows {
        let phase_id: Uuid = row.try_get("phase_id").map_err(|_| AppError::Internal)?;
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        let ccam_code: Option<String> = row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
        let unit_amount_cents: i64 = row
            .try_get("unit_amount_cents")
            .map_err(|_| AppError::Internal)?;
        let amo_part_cents: i64 = row
            .try_get("amo_part_cents")
            .map_err(|_| AppError::Internal)?;
        let amc_part_cents: i64 = row
            .try_get("amc_part_cents")
            .map_err(|_| AppError::Internal)?;

        total_cost_cents += unit_amount_cents;
        total_amo_cents += amo_part_cents;
        total_amc_cents += amc_part_cents;

        items_by_phase
            .entry(phase_id)
            .or_default()
            .push(TreatmentPlanDetailItem {
                label,
                ccam_code,
                unit_amount_cents,
                amo_part_cents,
                amc_part_cents,
            });
    }

    let remaining_cents = total_cost_cents - total_amo_cents - total_amc_cents;

    let phases = phase_rows
        .into_iter()
        .map(|row| {
            let phase_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let position: i32 = row.try_get("position").map_err(|_| AppError::Internal)?;
            let title: String = row.try_get("title").map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            let items = items_by_phase.remove(&phase_id).unwrap_or_default();
            Ok(TreatmentPlanPhase {
                id: phase_id,
                position,
                title,
                status,
                items,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        account_id = %claims.account_id,
        plan_id = %plan_id,
        "treatment plan detail fetched"
    );

    Ok(Json(TreatmentPlanDetailResponse {
        id: plan_id,
        title: plan_title,
        status: plan_status,
        total_cost_cents,
        remaining_cents,
        amo_part_cents: total_amo_cents,
        amc_part_cents: total_amc_cents,
        phases,
    }))
}
