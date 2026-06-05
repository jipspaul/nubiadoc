//! Handler pour le parcours de soins patient :
//! GET /v1/treatment-plans — liste paginée des plans de traitement.

use axum::extract::{Query, State};
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
