//! Handler `GET /v1/appointments` — liste paginée des RDV du patient.

use axum::{
    extract::{Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

#[derive(Deserialize)]
pub struct AppointmentsQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

#[derive(Serialize)]
pub struct ProviderSummary {
    pub display_name: Option<String>,
}

#[derive(Serialize)]
pub struct AppointmentItem {
    pub id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub status: String,
    pub motif: Option<String>,
    pub provider: ProviderSummary,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

#[derive(Serialize)]
pub struct AppointmentsResponse {
    pub data: Vec<AppointmentItem>,
    pub page: PageInfo,
}

fn encode_cursor(starts_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", starts_at.timestamp_micros(), id)
}

fn decode_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/appointments` — liste paginée des RDV du patient connecté, tous praticiens.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` (policy 0029).
/// `provider.display_name` n'est visible que si `is_listed = true` (policy 0011) ;
/// retourné `null` sinon — comportement attendu en MVP.
pub async fn list_appointments(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(params): Query<AppointmentsQuery>,
) -> Result<Json<AppointmentsResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let is_past = params.status.as_deref() == Some("past");

    let status_clause = match params.status.as_deref() {
        Some("upcoming") => {
            " AND a.starts_at > now() \
              AND a.status IN ('requested','confirmed','checked_in','in_progress')"
        }
        Some("past") => " AND (a.starts_at <= now() OR a.status IN ('done','cancelled','no_show'))",
        _ => "",
    };

    let order = if is_past { "DESC" } else { "ASC" };

    let cursor = params.cursor.as_deref().and_then(decode_cursor);

    // $1 = fetch_limit ; si cursor : $2 = starts_at, $3 = id
    let cursor_clause = if cursor.is_some() {
        if is_past {
            " AND (a.starts_at < $2 OR (a.starts_at = $2 AND a.id < $3))"
        } else {
            " AND (a.starts_at > $2 OR (a.starts_at = $2 AND a.id > $3))"
        }
    } else {
        ""
    };

    let sql = format!(
        "SELECT \
             a.id, a.starts_at, a.ends_at, a.status, a.motif, \
             (SELECT p.display_name FROM provider p \
              WHERE p.practitioner_id = a.practitioner_id LIMIT 1) \
              AS provider_display_name \
         FROM appointment a \
         WHERE a.deleted_at IS NULL \
         {status_clause}{cursor_clause} \
         ORDER BY a.starts_at {order}, a.id {order} \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let fetch_limit = limit + 1;

    let rows = match cursor {
        Some((cursor_starts_at, cursor_id)) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cursor_starts_at)
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

    let mut data: Vec<AppointmentItem> = Vec::with_capacity(visible.len());
    let mut last_starts_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let starts_at: chrono::DateTime<chrono::Utc> =
            row.try_get("starts_at").map_err(|_| AppError::Internal)?;
        let ends_at: chrono::DateTime<chrono::Utc> =
            row.try_get("ends_at").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        let motif: Option<String> = row.try_get("motif").map_err(|_| AppError::Internal)?;
        let display_name: Option<String> = row
            .try_get("provider_display_name")
            .map_err(|_| AppError::Internal)?;

        last_starts_at = Some(starts_at);
        last_id = Some(id);

        data.push(AppointmentItem {
            id,
            starts_at: starts_at.to_rfc3339(),
            ends_at: ends_at.to_rfc3339(),
            status,
            motif,
            provider: ProviderSummary { display_name },
        });
    }

    let next_cursor = if has_more {
        last_starts_at
            .zip(last_id)
            .map(|(dt, id)| encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        account_id = %claims.account_id,
        count = data.len(),
        has_more,
        "appointments listed"
    );

    Ok(Json(AppointmentsResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}
