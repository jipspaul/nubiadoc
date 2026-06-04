//! Handlers `GET /v1/appointments` et `GET /v1/appointments/:id` — RDV patient.

use axum::{
    extract::{Path, Query, State},
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

#[derive(Serialize)]
pub struct ProviderDetail {
    pub id: Option<Uuid>,
    pub display_name: Option<String>,
    pub specialty: Option<String>,
}

#[derive(Serialize)]
pub struct CabinetInfo {
    pub name: String,
    pub address: Option<String>,
}

#[derive(Serialize)]
pub struct AppointmentDetail {
    pub id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub status: String,
    pub motif: Option<String>,
    pub provider: ProviderDetail,
    pub cabinet: CabinetInfo,
}

/// `GET /v1/appointments/:id` — détail d'un RDV du patient connecté.
///
/// Token `kind:"patient"` requis. Ownership vérifié par RLS (policy 0029) :
/// si le RDV n'appartient pas au patient ou n'existe pas → `404` (anti-énumération).
/// Après fetch, le GUC `app.current_cabinet_id` est positionné pour lire le cabinet
/// et écrire l'entrée d'audit (§07 §2.9).
pub async fn get_appointment(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<AppointmentDetail>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient pour appointment_patient_read (policy 0029).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Fetch appointment — RLS garantit l'ownership (404 si autre patient ou inexistant).
    let row = sqlx::query(
        "SELECT id, starts_at, ends_at, status, motif, cabinet_id, practitioner_id \
         FROM appointment \
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(appt_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let starts_at: chrono::DateTime<chrono::Utc> =
        row.try_get("starts_at").map_err(|_| AppError::Internal)?;
    let ends_at: chrono::DateTime<chrono::Utc> =
        row.try_get("ends_at").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let motif: Option<String> = row.try_get("motif").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    // Scope cabinet pour provider_cabinet_manage + tenant_isolation (cabinet) + audit_log.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Fetch provider (inclut les non-listés via provider_cabinet_manage).
    let provider_row = sqlx::query(
        "SELECT id, display_name, specialite FROM provider \
         WHERE practitioner_id = $1 \
         LIMIT 1",
    )
    .bind(practitioner_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (provider_id, provider_display_name, provider_specialty) = match provider_row {
        Some(r) => {
            let pid: Uuid = r.try_get("id").map_err(|_| AppError::Internal)?;
            let dn: String = r.try_get("display_name").map_err(|_| AppError::Internal)?;
            let sp: Option<String> = r.try_get("specialite").map_err(|_| AppError::Internal)?;
            (Some(pid), Some(dn), sp)
        }
        None => (None, None, None),
    };

    // Fetch cabinet (accessible via tenant_isolation après SET LOCAL cabinet GUC).
    let cab_row = sqlx::query(
        "SELECT raison_sociale, settings->>'address' AS address FROM cabinet WHERE id = $1",
    )
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::Internal)?;

    let cabinet_name: String = cab_row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;
    let cabinet_address: Option<String> =
        cab_row.try_get("address").map_err(|_| AppError::Internal)?;

    // Audit (§07 §2.9) — cabinet_id correspond au GUC positionné ci-dessus.
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'read_appointment', 'appointment', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        "appointment detail queried"
    );

    Ok(Json(AppointmentDetail {
        id,
        starts_at: starts_at.to_rfc3339(),
        ends_at: ends_at.to_rfc3339(),
        status,
        motif,
        provider: ProviderDetail {
            id: provider_id,
            display_name: provider_display_name,
            specialty: provider_specialty,
        },
        cabinet: CabinetInfo {
            name: cabinet_name,
            address: cabinet_address,
        },
    }))
}
