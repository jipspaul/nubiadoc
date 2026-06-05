//! Handlers pour les RDV patient : liste, détail, création et check-in.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

// ── Patch ────────────────────────────────────────────────────────────────────

/// Corps de la requête `PATCH /v1/appointments/:id`.
#[derive(Deserialize)]
pub struct PatchAppointmentBody {
    pub starts_at: Option<String>,
    pub motif: Option<String>,
}

/// Réponse de `PATCH /v1/appointments/:id`.
#[derive(Serialize)]
pub struct PatchAppointmentResponse {
    pub appointment_id: Uuid,
    pub status: String,
}

/// `PATCH /v1/appointments/:id` — patient modifie son RDV (créneau ou motif).
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// Hors délai (≥ 24 h avant starts_at courant) → `409 too_late`.
/// Conflit créneau (contrainte PG `23P01`) → `409 slot_taken`.
/// Audité (`update_appointment`) dans `audit_log`.
pub async fn patch_appointment(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
    Json(body): Json<PatchAppointmentBody>,
) -> Result<Json<PatchAppointmentResponse>, AppError> {
    let new_starts_at: Option<chrono::DateTime<chrono::Utc>> = body
        .starts_at
        .as_deref()
        .map(|s| s.parse::<chrono::DateTime<chrono::Utc>>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, starts_at, status, cabinet_id \
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
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;

    if status != "requested" && status != "confirmed" {
        return Err(AppError::InvalidStatus);
    }

    // Délai configurable, défaut 24 h avant le starts_at courant.
    if chrono::Utc::now() >= starts_at - chrono::Duration::hours(24) {
        return Err(AppError::TooLate);
    }

    // Scope cabinet pour UPDATE (tenant_isolation) + audit.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Préserve la durée si starts_at change. 23P01 → slot_taken.
    let result = sqlx::query(
        "UPDATE appointment \
         SET \
           starts_at  = COALESCE($1, starts_at), \
           ends_at    = CASE WHEN $1 IS NOT NULL \
                             THEN $1 + (ends_at - starts_at) \
                             ELSE ends_at END, \
           motif      = COALESCE($2, motif), \
           updated_at = now() \
         WHERE id = $3 \
         RETURNING id, status",
    )
    .bind(new_starts_at)
    .bind(body.motif.as_deref())
    .bind(id)
    .fetch_one(&mut *tx)
    .await;

    let updated = match result {
        Ok(row) => row,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    let appointment_id: Uuid = updated.try_get("id").map_err(|_| AppError::Internal)?;
    let new_status: String = updated.try_get("status").map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'update_appointment', 'appointment', $3)",
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
        "appointment patched"
    );

    Ok(Json(PatchAppointmentResponse {
        appointment_id,
        status: new_status,
    }))
}

// ── Cancel ──────────────────────────────────────────────────────────────────

/// Réponse de `POST /v1/appointments/:id/cancel`.
#[derive(Serialize)]
pub struct CancelResponse {
    pub appointment_id: Uuid,
    pub status: String,
}

/// `POST /v1/appointments/:id/cancel` — patient annule son RDV, libère le créneau.
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// Vérifie status IN ('requested','confirmed') → sinon `409 {"error":"invalid_status"}`.
/// Vérifie starts_at > now() + 2h → sinon `409 {"error":"too_late"}`.
pub async fn cancel_appointment(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<CancelResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, starts_at, status, cabinet_id, slot_id \
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
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let slot_id: Option<Uuid> = row.try_get("slot_id").map_err(|_| AppError::Internal)?;

    if status != "requested" && status != "confirmed" {
        return Err(AppError::InvalidStatus);
    }

    // Annulation refusée si le RDV démarre dans moins de 2 heures.
    if chrono::Utc::now() >= starts_at - chrono::Duration::hours(2) {
        return Err(AppError::TooLate);
    }

    // Scope cabinet pour UPDATE (tenant_isolation) + audit.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE appointment \
         SET status = 'cancelled', cancelled_at = now(), updated_at = now() \
         WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(sid) = slot_id {
        sqlx::query("UPDATE availability_slot SET status = 'open' WHERE id = $1")
            .bind(sid)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    }

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'cancel_appointment', 'appointment', $3)",
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
        "appointment cancelled"
    );

    Ok(Json(CancelResponse {
        appointment_id: id,
        status: "cancelled".to_string(),
    }))
}

// ── Check-in ────────────────────────────────────────────────────────────────

/// Corps optionnel de `POST /v1/appointments/:id/checkin`.
#[derive(Deserialize, Default)]
pub struct CheckinBody {
    pub method: Option<String>,
}

/// Réponse de `POST /v1/appointments/:id/checkin`.
#[derive(Serialize)]
pub struct CheckinResponse {
    pub appointment_id: Uuid,
    pub status: String,
    pub checkin_at: String,
}

/// `POST /v1/appointments/:id/checkin` — patient signale son arrivée.
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// Vérifie status = 'confirmed' → sinon `409 {"error":"invalid_status"}`.
/// Vérifie la fenêtre starts_at ± 30 min / + 60 min → sinon `409 {"error":"out_of_window"}`.
pub async fn checkin_appointment(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
    body: Option<Json<CheckinBody>>,
) -> Result<Json<CheckinResponse>, AppError> {
    let method = body
        .as_ref()
        .and_then(|b| b.method.as_deref())
        .unwrap_or("manual")
        .to_string();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, starts_at, status, cabinet_id \
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
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;

    if status != "confirmed" {
        return Err(AppError::InvalidStatus);
    }

    let now = chrono::Utc::now();
    if now < starts_at - chrono::Duration::minutes(30)
        || now > starts_at + chrono::Duration::minutes(60)
    {
        return Err(AppError::OutOfWindow);
    }

    // Scope cabinet pour UPDATE (tenant_isolation) + audit.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let updated = sqlx::query(
        "UPDATE appointment \
         SET status = 'checked_in', checkin_at = now(), checkin_method = $2, updated_at = now() \
         WHERE id = $1 \
         RETURNING checkin_at",
    )
    .bind(id)
    .bind(&method)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let checkin_at: chrono::DateTime<chrono::Utc> = updated
        .try_get("checkin_at")
        .map_err(|_| AppError::Internal)?;

    // Insérer l'événement check-in (UNIQUE sur appointment_id → 409 si double check-in concurrent).
    let mode = match method.as_str() {
        "qr_web" => "qr_web",
        "borne" => "borne",
        "sms" => "sms",
        _ => "qr_app",
    };
    let ce_result = sqlx::query(
        "INSERT INTO checkin_event (cabinet_id, appointment_id, mode) VALUES ($1, $2, $3)",
    )
    .bind(cabinet_id)
    .bind(id)
    .bind(mode)
    .execute(&mut *tx)
    .await;
    match ce_result {
        Ok(_) => {}
        Err(e) if is_unique_violation(&e) => return Err(AppError::InvalidStatus),
        Err(_) => return Err(AppError::Internal),
    }

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'checkin', 'appointment', $3)",
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
        method = %method,
        "appointment checked in"
    );

    Ok(Json(CheckinResponse {
        appointment_id: id,
        status: "checked_in".to_string(),
        checkin_at: checkin_at.to_rfc3339(),
    }))
}

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

// ── Preparation ─────────────────────────────────────────────────────────────

/// Provider summary for `GET /v1/appointments/:id/preparation`.
#[derive(Serialize)]
pub struct PreparationProvider {
    pub name: Option<String>,
}

/// Geo coordinates from cabinet settings.
#[derive(Serialize)]
pub struct GeoCoord {
    pub lat: f64,
    pub lon: f64,
}

/// Physical access info from cabinet settings.
#[derive(Serialize)]
pub struct AccessInfo {
    pub door_code: Option<String>,
    pub parking: Option<String>,
    pub pmr: bool,
}

/// Establishment info for preparation response.
#[derive(Serialize)]
pub struct PreparationEstablishment {
    pub address: Option<String>,
    pub geo: Option<GeoCoord>,
    pub access: AccessInfo,
}

/// Item in the bring list.
#[derive(Serialize)]
pub struct BringItem {
    pub label: String,
    pub required: bool,
}

/// Réponse de `GET /v1/appointments/:id/preparation`.
#[derive(Serialize)]
pub struct PreparationResponse {
    pub provider: PreparationProvider,
    pub establishment: PreparationEstablishment,
    pub bring: Vec<BringItem>,
    pub reminder_at: String,
}

/// `GET /v1/appointments/:id/preparation` — infos pratiques du RDV pour le patient.
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// Dérive `bring` : Carte Vitale (toujours), mutuelle si `tiers_payant`, documents si
/// `documents_hint` non null. `reminder_at = starts_at - 1 h`.
pub async fn get_appointment_preparation(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<PreparationResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, starts_at, cabinet_id, practitioner_id, documents_hint \
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
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let documents_hint: Option<String> = row
        .try_get("documents_hint")
        .map_err(|_| AppError::Internal)?;

    // Scope cabinet pour accès provider + cabinet.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let provider_row =
        sqlx::query("SELECT display_name FROM provider WHERE practitioner_id = $1 LIMIT 1")
            .bind(practitioner_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    let provider_name: Option<String> =
        provider_row.and_then(|r| r.try_get::<String, _>("display_name").ok());

    let cab_row = sqlx::query(
        "SELECT settings->>'address'   AS address, \
                settings->>'door_code' AS door_code, \
                settings->>'parking'   AS parking, \
                settings->>'pmr'       AS pmr, \
                settings->'geo'        AS geo \
         FROM cabinet WHERE id = $1",
    )
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::Internal)?;

    let address: Option<String> = cab_row.try_get("address").map_err(|_| AppError::Internal)?;
    let door_code: Option<String> = cab_row
        .try_get("door_code")
        .map_err(|_| AppError::Internal)?;
    let parking: Option<String> = cab_row.try_get("parking").map_err(|_| AppError::Internal)?;
    let pmr_str: Option<String> = cab_row.try_get("pmr").map_err(|_| AppError::Internal)?;
    let geo_val: Option<serde_json::Value> =
        cab_row.try_get("geo").map_err(|_| AppError::Internal)?;

    // Tiers-payant depuis patient_coverage (app.patient_account_id GUC déjà positionné).
    let coverage_row = sqlx::query(
        "SELECT tiers_payant FROM patient_coverage WHERE patient_account_id = $1 LIMIT 1",
    )
    .bind(claims.account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let tiers_payant: bool = coverage_row
        .and_then(|r| r.try_get::<bool, _>("tiers_payant").ok())
        .unwrap_or(false);

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let pmr = pmr_str.as_deref() == Some("true");

    let geo = geo_val.and_then(|v| {
        let lat = v["lat"].as_f64()?;
        let lon = v["lon"].as_f64()?;
        Some(GeoCoord { lat, lon })
    });

    let mut bring = vec![BringItem {
        label: "Carte Vitale".to_string(),
        required: true,
    }];
    if tiers_payant {
        bring.push(BringItem {
            label: "Carte mutuelle".to_string(),
            required: true,
        });
    }
    if documents_hint.is_some() {
        bring.push(BringItem {
            label: "Ordonnances et radios".to_string(),
            required: false,
        });
    }

    let reminder_at = (starts_at - chrono::Duration::hours(1)).to_rfc3339();

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        "appointment preparation queried"
    );

    Ok(Json(PreparationResponse {
        provider: PreparationProvider {
            name: provider_name,
        },
        establishment: PreparationEstablishment {
            address,
            geo,
            access: AccessInfo {
                door_code,
                parking,
                pmr,
            },
        },
        bring,
        reminder_at,
    }))
}

/// Corps de la requête `POST /v1/appointments`.
#[derive(Deserialize)]
pub struct CreateAppointmentBody {
    pub provider_id: Uuid,
    pub slot_id: Option<Uuid>,
    /// ISO 8601 UTC (ex. "2026-06-10T09:00:00Z"). Ignoré si `slot_id` est fourni.
    pub starts_at: Option<String>,
    pub motif: String,
    pub on_behalf_of: Option<Uuid>,
}

/// Réponse de `POST /v1/appointments`.
#[derive(Serialize)]
pub struct CreateAppointmentResponse {
    pub appointment_id: Uuid,
    pub status: String,
}

fn is_exclusion_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23P01")
    )
}

fn is_unique_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23505")
    )
}

/// `POST /v1/appointments` — création d'un RDV par le patient.
///
/// Token `kind:"patient"` requis. Le `cabinet_id` est déduit du praticien (jamais du body).
/// La contrainte d'exclusion DB `appointment_no_overlap` (erreur PG `23P01`) est mappée en
/// `409 slot_taken`. Si `on_behalf_of` est fourni, la tutelle active est vérifiée contre
/// `account_guardianship` — sinon `422 guardianship_required`.
/// Le statut initial est toujours `"requested"` (confirmation asynchrone par le cabinet).
pub async fn create_appointment(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<CreateAppointmentBody>,
) -> Result<(StatusCode, Json<CreateAppointmentResponse>), AppError> {
    if body.slot_id.is_none() && body.starts_at.is_none() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Vérifie la tutelle si on agit pour un proche.
    if let Some(dependent_id) = body.on_behalf_of {
        sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
            .bind(claims.account_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let guardianship = sqlx::query(
            "SELECT id FROM account_guardianship \
             WHERE guardian_account_id = $1 AND dependent_account_id = $2 AND active = true",
        )
        .bind(claims.account_id)
        .bind(dependent_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        if guardianship.is_none() {
            return Err(AppError::GuardianshipRequired);
        }
    }

    let effective_account_id = body.on_behalf_of.unwrap_or(claims.account_id);

    // Le praticien est récupéré via la policy `provider_public_read` (is_listed = true).
    let provider_row =
        sqlx::query("SELECT cabinet_id, practitioner_id FROM provider WHERE id = $1")
            .bind(body.provider_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = provider_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id_opt: Option<Uuid> = provider_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id = practitioner_id_opt.ok_or(AppError::NotFound)?;

    // Scope cabinet pour les INSERTs soumis à la RLS tenant_isolation.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Résout le dossier patient dans ce cabinet (RLS via GUC cabinet).
    let patient_row = sqlx::query(
        "SELECT id FROM patient \
         WHERE patient_account_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(effective_account_id)
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let patient_id: Uuid = patient_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Résout starts_at / ends_at selon slot_id ou starts_at fourni.
    let (starts_at, ends_at) = if let Some(slot_id) = body.slot_id {
        let slot_row =
            sqlx::query("SELECT starts_at, ends_at FROM availability_slot WHERE id = $1")
                .bind(slot_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
                .ok_or(AppError::NotFound)?;

        let sa: chrono::DateTime<chrono::Utc> = slot_row
            .try_get("starts_at")
            .map_err(|_| AppError::Internal)?;
        let ea: chrono::DateTime<chrono::Utc> = slot_row
            .try_get("ends_at")
            .map_err(|_| AppError::Internal)?;
        (sa, ea)
    } else {
        let sa = body
            .starts_at
            .as_deref()
            .and_then(|s| s.parse::<chrono::DateTime<chrono::Utc>>().ok())
            .ok_or(AppError::ValidationError)?;
        let ea = sa + chrono::Duration::minutes(30);
        (sa, ea)
    };

    // INSERT — 23P01 (appointment_no_overlap) → 409 slot_taken.
    let result = sqlx::query(
        "INSERT INTO appointment \
         (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, $5, 'requested', $6) \
         RETURNING id, status",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(&body.motif)
    .fetch_one(&mut *tx)
    .await;

    let row = match result {
        Ok(row) => row,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %appointment_id,
        "appointment created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateAppointmentResponse {
            appointment_id,
            status,
        }),
    ))
}
