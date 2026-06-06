//! Handler pour la facturation patient : GET /v1/quotes.

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
pub struct ListQuotesQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

#[derive(Serialize)]
pub struct QuoteItem {
    pub id: Uuid,
    pub status: String,
    pub amount_cents: i64,
    pub currency: String,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

#[derive(Serialize)]
pub struct ListQuotesResponse {
    pub data: Vec<QuoteItem>,
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

/// `GET /v1/quotes` — devis du patient connecté, tous cabinets confondus.
///
/// Token `kind:"patient"` requis ; token pro → `403`.
/// RLS via `app.patient_account_id` (policy `quote_patient_read`, migration 0029).
/// Filtre optionnel `?status=` (draft|sent|signed|refused|expired).
/// Pagination cursor-based (`limit` + `cursor`), tri `created_at DESC`.
/// Montants exposés en centimes entiers (`amount_cents`).
pub async fn list_quotes(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(params): Query<ListQuotesQuery>,
) -> Result<Json<ListQuotesResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let fetch_limit = limit + 1;

    let cursor = params.cursor.as_deref().and_then(decode_cursor);

    let status_clause = if params.status.is_some() {
        " AND q.status = $2"
    } else {
        ""
    };

    // Cursor binds shift by 1 when status is present.
    let cursor_clause = match (params.status.is_some(), cursor.is_some()) {
        (false, true) => " AND (q.created_at < $2 OR (q.created_at = $2 AND q.id < $3))",
        (true, true) => " AND (q.created_at < $3 OR (q.created_at = $3 AND q.id < $4))",
        _ => "",
    };

    let sql = format!(
        "SELECT q.id, q.status, (q.total_amount * 100)::bigint AS amount_cents, \
                q.currency, q.created_at \
         FROM quote q \
         WHERE q.deleted_at IS NULL\
         {status_clause}{cursor_clause} \
         ORDER BY q.created_at DESC, q.id DESC \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — quote_patient_read (migration 0029).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = match (params.status.as_deref(), cursor) {
        (None, None) => sqlx::query(&sql)
            .bind(fetch_limit)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        (Some(st), None) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(st)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        (None, Some((cursor_at, cursor_id))) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cursor_at)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        (Some(st), Some((cursor_at, cursor_id))) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(st)
            .bind(cursor_at)
            .bind(cursor_id)
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

    let mut data: Vec<QuoteItem> = Vec::with_capacity(visible.len());
    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        let amount_cents: i64 = row
            .try_get("amount_cents")
            .map_err(|_| AppError::Internal)?;
        let currency: String = row.try_get("currency").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        last_created_at = Some(created_at);
        last_id = Some(id);

        data.push(QuoteItem {
            id,
            status,
            amount_cents,
            currency: currency.trim().to_string(),
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
        "quotes listed"
    );

    Ok(Json(ListQuotesResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}
