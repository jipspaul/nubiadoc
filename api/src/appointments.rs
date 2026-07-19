//! Handlers pour les RDV patient : liste, détail, création et check-in.

use axum::{
    extract::{Extension, Path, Query, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState, JobDispatcher,
};

// ── Patch ────────────────────────────────────────────────────────────────────

/// Corps de la requête `PATCH /v1/appointments/:id`.
#[derive(Deserialize)]
pub struct PatchAppointmentBody {
    pub starts_at: Option<String>,
    pub motif: Option<String>,
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
) -> Result<Json<AppointmentDetail>, AppError> {
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
        "SELECT id, starts_at, status, cabinet_id, slot_id, practitioner_id \
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
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    if status != "requested" && status != "confirmed" {
        return Err(AppError::InvalidStatus);
    }

    // Délai configurable, défaut 24 h avant le starts_at courant.
    if chrono::Utc::now() >= starts_at - chrono::Duration::hours(24) {
        return Err(AppError::TooLate);
    }

    // Reprogrammation : le nouveau créneau doit être validé côté serveur, comme
    // la réservation initiale (POST /v1/bookings exige un availability_slot réel).
    // Sinon un patient pouvait déplacer son RDV vers une date passée ou une heure
    // sans ouverture (03h17…) — RDV fantôme "requested" polluant la liste cabinet
    // (#3558). Le nouveau starts_at doit être (a) dans le futur ET (b) correspondre
    // à un créneau `open` du praticien. Les créneaux ouverts sont publiquement
    // lisibles (policy availability_slot_patient_read, 0117 — aucun GUC requis).
    let mut new_slot_id: Option<Uuid> = None;
    if let Some(new_ts) = new_starts_at {
        if new_ts <= chrono::Utc::now() {
            return Err(AppError::SlotUnavailable);
        }
        new_slot_id = sqlx::query_scalar(
            "SELECT s.id FROM availability_slot s \
               JOIN provider p ON p.id = s.provider_id \
               WHERE p.practitioner_id = $1 \
                 AND s.starts_at = $2 \
                 AND s.status = 'open' \
                 AND s.deleted_at IS NULL",
        )
        .bind(practitioner_id)
        .bind(new_ts)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        if new_slot_id.is_none() {
            return Err(AppError::SlotUnavailable);
        }
    }

    // Scope cabinet pour UPDATE (tenant_isolation) + audit.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Préserve la durée si starts_at change. 23P01 → slot_taken.
    // Un starts_at différent délie le RDV de son créneau d'origine et le
    // rattache au nouveau créneau de destination (slot_id = new_slot_id),
    // symétrique de create_appointment.
    let result = sqlx::query(
        "UPDATE appointment \
         SET \
           starts_at  = COALESCE($1, starts_at), \
           ends_at    = CASE WHEN $1 IS NOT NULL \
                             THEN $1 + (ends_at - starts_at) \
                             ELSE ends_at END, \
           motif      = COALESCE($2, motif), \
           slot_id    = CASE WHEN $1 IS NOT NULL THEN $4 ELSE slot_id END, \
           updated_at = now() \
         WHERE id = $3 \
         RETURNING id, starts_at, ends_at, status, motif, practitioner_id",
    )
    .bind(new_starts_at)
    .bind(body.motif.as_deref())
    .bind(id)
    .bind(new_slot_id)
    .fetch_one(&mut *tx)
    .await;

    let updated = match result {
        Ok(row) => row,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    // Libère l'ancien créneau (comme cancel_appointment) puisqu'il n'est plus occupé.
    if new_starts_at.is_some() {
        if let Some(sid) = slot_id {
            sqlx::query("UPDATE availability_slot SET status = 'open' WHERE id = $1")
                .bind(sid)
                .execute(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
        }

        // Consomme le créneau de destination (symétrique de create_appointment,
        // l.1791-1801) : sinon il reste 'open' et apparaît comme réservable
        // dans la recherche publique alors qu'il est déjà occupé (#3707).
        if let Some(sid) = new_slot_id {
            sqlx::query(
                "UPDATE availability_slot SET status = 'booked', updated_at = now() \
                 WHERE id = $1",
            )
            .bind(sid)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        }
    }

    let appointment_id: Uuid = updated.try_get("id").map_err(|_| AppError::Internal)?;
    let new_starts_at: chrono::DateTime<chrono::Utc> = updated
        .try_get("starts_at")
        .map_err(|_| AppError::Internal)?;
    let new_ends_at: chrono::DateTime<chrono::Utc> =
        updated.try_get("ends_at").map_err(|_| AppError::Internal)?;
    let new_status: String = updated.try_get("status").map_err(|_| AppError::Internal)?;
    let new_motif: Option<String> = updated.try_get("motif").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = updated
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

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

    let (provider_id, provider_display_name, provider_specialty) =
        fetch_provider_for_response(&mut tx, practitioner_id).await?;
    let (cabinet_name, cabinet_address) =
        fetch_cabinet_for_response(&mut tx, cabinet_id, practitioner_id).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        "appointment patched"
    );

    Ok(Json(AppointmentDetail {
        id: appointment_id,
        starts_at: new_starts_at.to_rfc3339(),
        ends_at: new_ends_at.to_rfc3339(),
        status: new_status,
        motif: new_motif,
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

// ── Cancel ──────────────────────────────────────────────────────────────────

/// Corps optionnel de `POST /v1/appointments/:id/cancel`.
#[derive(Deserialize, Default)]
pub struct CancelBody {
    pub reason: Option<String>,
}

/// Réponse de `POST /v1/appointments/:id/cancel`.
#[derive(Serialize)]
pub struct CancelResponse {
    pub appointment_id: Uuid,
    pub status: String,
}

/// `POST /v1/appointments/:id/cancel` — patient annule son RDV, libère le créneau.
/// Si le RDV est `checked_in`, permet de sortir de la file d'attente (→ `no_show`).
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// Vérifie status IN ('requested','confirmed','checked_in') → sinon `409 {"error":"invalid_status"}`.
/// Vérifie starts_at > now() + 2h → sinon `409 {"error":"too_late"}` (sauf si déjà `checked_in`
/// ou si starts_at est déjà dans le passé, #3811 — sinon un RDV périmé devient inclôturable).
pub async fn cancel_appointment(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
    body: Option<Json<CancelBody>>,
) -> Result<Json<CancelResponse>, AppError> {
    let reason = body
        .as_ref()
        .and_then(|b| b.reason.as_deref())
        .map(str::to_owned);
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

    if status != "requested" && status != "confirmed" && status != "checked_in" {
        return Err(AppError::InvalidStatus);
    }

    // Annulation refusée si le RDV démarre dans moins de 2 heures — sauf pour un
    // patient déjà checked_in, qui doit pouvoir sortir de la file à tout moment,
    // et sauf si starts_at est déjà dans le passé : la fenêtre des 2h est alors
    // déjà révolue et bloquer indéfiniment créerait un cul-de-sac (#3811) pour
    // les RDV résiduels créés avant le déploiement des gardes amont (#3750).
    let now = chrono::Utc::now();
    if status != "checked_in" && now < starts_at && now >= starts_at - chrono::Duration::hours(2) {
        return Err(AppError::TooLate);
    }

    // Un checked_in qui quitte la file est un no_show (il n'a pas été vu) ; sinon annulation classique.
    let new_status = if status == "checked_in" {
        "no_show"
    } else {
        "cancelled"
    };

    // Scope cabinet pour UPDATE (tenant_isolation) + audit.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE appointment \
         SET status = $2, cancelled_at = now(), cancel_reason = $3, updated_at = now() \
         WHERE id = $1",
    )
    .bind(id)
    .bind(new_status)
    .bind(reason.as_deref())
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
        status: new_status.to_string(),
    }))
}

// ── Check-in ────────────────────────────────────────────────────────────────

/// Corps optionnel de `POST /v1/appointments/:id/checkin`.
#[derive(Deserialize, Default)]
pub struct CheckinBody {
    pub qr_code: Option<String>,
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
    Extension(hub): Extension<std::sync::Arc<crate::realtime::WsHub>>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
    body: Option<Json<CheckinBody>>,
) -> Result<Json<CheckinResponse>, AppError> {
    let qr_code = body.as_ref().and_then(|b| b.qr_code.clone());
    let method = if qr_code.is_some() {
        "qr_app"
    } else {
        "manual"
    }
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
    if now < starts_at - chrono::Duration::minutes(60) {
        return Err(AppError::TooEarly);
    }
    if now > starts_at + chrono::Duration::minutes(60) {
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
    let ce_result = sqlx::query(
        "INSERT INTO checkin_event (cabinet_id, appointment_id, mode) VALUES ($1, $2, $3)",
    )
    .bind(cabinet_id)
    .bind(id)
    .bind(&method)
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

    // Temps réel : le patient apparaît dans la salle d'attente du cabinet — #3238.
    hub.publish(
        cabinet_id,
        serde_json::json!({
            "channel": "waiting_room",
            "event": "checked_in",
            "data": { "appointment_id": id, "checkin_at": checkin_at.to_rfc3339() }
        })
        .to_string(),
    );

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
    /// Filtre par statut (`upcoming` | `past`). Alias pour rétro-compatibilité front.
    pub status: Option<String>,
    /// Alias `filter=upcoming|history` (convention Flutter nubia_data). `history` → `past`.
    pub filter: Option<String>,
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

    // `filter` est l'alias Flutter (history → past). `status` garde la rétro-compat.
    let effective_status = params
        .filter
        .as_deref()
        .map(|f| if f == "history" { "past" } else { f })
        .or(params.status.as_deref());

    let is_past = effective_status == Some("past");

    let status_clause = match effective_status {
        Some("upcoming") => {
            " AND (a.status IN ('checked_in','in_progress') \
              OR (a.starts_at > now() AND a.status IN ('requested','confirmed')))"
        }
        Some("past") => {
            " AND (a.status IN ('done','cancelled','no_show') \
              OR (a.starts_at <= now() AND a.status IN ('requested','confirmed')))"
        }
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

    // Fetch cabinet (accessible via tenant_isolation après SET LOCAL cabinet GUC) +
    // fallback establishment (#3799, même helper que create/patch_appointment).
    let (cabinet_name, cabinet_address) =
        fetch_cabinet_for_response(&mut tx, cabinet_id, practitioner_id).await?;

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

/// Formate l'adresse jsonb `establishment.address` (`{"rue":...,"cp":...,"ville":...}`,
/// cf. `db/migrations/0040_marketplace_provider_seed.sql`) en une ligne affichable /
/// utilisable comme destination de navigation.
fn format_establishment_address(address: &serde_json::Value) -> Option<String> {
    let rue = address.get("rue").and_then(|v| v.as_str());
    let cp = address.get("cp").and_then(|v| v.as_str());
    let ville = address.get("ville").and_then(|v| v.as_str());

    let cp_ville = match (cp, ville) {
        (Some(cp), Some(ville)) => Some(format!("{cp} {ville}")),
        (Some(cp), None) => Some(cp.to_string()),
        (None, Some(ville)) => Some(ville.to_string()),
        (None, None) => None,
    };

    let parts: Vec<String> = [rue.map(str::to_string), cp_ville]
        .into_iter()
        .flatten()
        .collect();

    if parts.is_empty() {
        None
    } else {
        Some(parts.join(", "))
    }
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
    pub parking: bool,
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

    // Jointure establishment/geo praticien : fallback quand `cabinet.settings` ne porte
    // pas d'adresse (cas du cabinet seed — cf. #3557).
    let provider_row = sqlx::query(
        "SELECT p.display_name, e.address AS establishment_address, \
                ST_Y(p.geo::geometry) AS geo_lat, ST_X(p.geo::geometry) AS geo_lng \
         FROM provider p \
         LEFT JOIN establishment e ON e.id = p.establishment_id \
         WHERE p.practitioner_id = $1 \
         LIMIT 1",
    )
    .bind(practitioner_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let provider_name: Option<String> = provider_row
        .as_ref()
        .and_then(|r| r.try_get::<String, _>("display_name").ok());
    let establishment_address: Option<serde_json::Value> = provider_row.as_ref().and_then(|r| {
        r.try_get::<Option<serde_json::Value>, _>("establishment_address")
            .ok()
            .flatten()
    });
    let provider_geo_lat: Option<f64> = provider_row
        .as_ref()
        .and_then(|r| r.try_get::<Option<f64>, _>("geo_lat").ok().flatten());
    let provider_geo_lng: Option<f64> = provider_row
        .as_ref()
        .and_then(|r| r.try_get::<Option<f64>, _>("geo_lng").ok().flatten());

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
    let parking_str: Option<String> = cab_row.try_get("parking").map_err(|_| AppError::Internal)?;
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
    // Même parsing que pmr : settings->>'parking' est du texte JSON ("true"/
    // "false"), pas un bool natif. Non converti auparavant, AccessInfo.parking
    // exposait la chaîne brute au lieu d'un bool (#3741).
    let parking = parking_str.as_deref() == Some("true");

    // Fallback annuaire quand `cabinet.settings` n'a pas d'adresse (#3557) : même donnée
    // que celle déjà exposée par `GET /v1/providers/:id`.
    let address = address.or_else(|| {
        establishment_address
            .as_ref()
            .and_then(format_establishment_address)
    });

    let geo = geo_val
        .and_then(|v| {
            let lat = v["lat"].as_f64()?;
            let lon = v["lon"].as_f64()?;
            Some(GeoCoord { lat, lon })
        })
        .or(match (provider_geo_lat, provider_geo_lng) {
            (Some(lat), Some(lng)) => Some(GeoCoord { lat, lon: lng }),
            _ => None,
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
    pub motif: Option<String>,
    pub on_behalf_of: Option<Uuid>,
}

// ── Directions ──────────────────────────────────────────────────────────────

/// Query params for `GET /v1/appointments/:id/directions`.
#[derive(Deserialize)]
pub struct DirectionsQuery {
    pub mode: Option<String>,
}

/// Réponse de `GET /v1/appointments/:id/directions`.
#[derive(Serialize)]
pub struct DirectionsResponse {
    pub mode: String,
    pub duration_min: Option<i32>,
    pub distance_m: Option<i32>,
    pub deeplink: String,
}

/// `GET /v1/appointments/:id/directions?mode=car` — deeplink navigation vers le cabinet.
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// MVP stub : `duration_min` et `distance_m` sont toujours null.
pub async fn get_appointment_directions(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
    Query(params): Query<DirectionsQuery>,
) -> Result<Json<DirectionsResponse>, AppError> {
    let mode = params.mode.unwrap_or_else(|| "car".to_string());

    if !matches!(mode.as_str(), "car" | "transit" | "walk") {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT cabinet_id, practitioner_id FROM appointment WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(appt_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cab_row = sqlx::query("SELECT settings->>'address' AS address FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::Internal)?;

    let address: Option<String> = cab_row.try_get("address").map_err(|_| AppError::Internal)?;

    // Jointure establishment/geo praticien : fallback quand `cabinet.settings` ne porte
    // pas d'adresse (cas du cabinet seed — cf. #3557), même donnée que celle déjà
    // exposée par `GET /v1/providers/:id`.
    let provider_row = sqlx::query(
        "SELECT e.address AS establishment_address, \
                ST_Y(p.geo::geometry) AS geo_lat, ST_X(p.geo::geometry) AS geo_lng \
         FROM provider p \
         LEFT JOIN establishment e ON e.id = p.establishment_id \
         WHERE p.practitioner_id = $1 \
         LIMIT 1",
    )
    .bind(practitioner_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let establishment_address: Option<serde_json::Value> = provider_row.as_ref().and_then(|r| {
        r.try_get::<Option<serde_json::Value>, _>("establishment_address")
            .ok()
            .flatten()
    });
    let provider_geo_lat: Option<f64> = provider_row
        .as_ref()
        .and_then(|r| r.try_get::<Option<f64>, _>("geo_lat").ok().flatten());
    let provider_geo_lng: Option<f64> = provider_row
        .as_ref()
        .and_then(|r| r.try_get::<Option<f64>, _>("geo_lng").ok().flatten());

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let resolved_address = address.or_else(|| {
        establishment_address
            .as_ref()
            .and_then(format_establishment_address)
    });

    let destination = match resolved_address {
        Some(a) => a.replace(' ', "+"),
        None => match (provider_geo_lat, provider_geo_lng) {
            (Some(lat), Some(lng)) => format!("{lat},{lng}"),
            _ => String::new(),
        },
    };
    let deeplink = format!(
        "https://www.google.com/maps/dir/?api=1&destination={}",
        destination
    );

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %appt_id,
        mode = %mode,
        "appointment directions requested"
    );

    Ok(Json(DirectionsResponse {
        mode,
        duration_min: None,
        distance_m: None,
        deeplink,
    }))
}

// ── Callback request ────────────────────────────────────────────────────────

/// Réponse de `POST /v1/appointments/:id/callback-request`.
#[derive(Serialize)]
pub struct CallbackRequestResponse {
    pub appointment_id: Uuid,
    pub callback_requested_at: String,
    pub status: String,
}

/// `POST /v1/appointments/:id/callback-request` — patient demande un rappel téléphonique.
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// Vérifie status IN ('requested','confirmed') → sinon `409 {"error":"invalid_status"}`.
/// Idempotent : si une demande existe déjà, retourne `callback_requested`.
/// Audité (`callback_request`) dans `audit_log`.
/// Notifie le cabinet via job apalis (stub pour MVP).
pub async fn callback_appointment(
    State(state): State<AppState>,
    Extension(dispatcher): Extension<std::sync::Arc<dyn JobDispatcher>>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<CallbackRequestResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, status, cabinet_id, callback_requested_at \
         FROM appointment \
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(appt_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let existing: Option<chrono::DateTime<chrono::Utc>> = row
        .try_get("callback_requested_at")
        .map_err(|_| AppError::Internal)?;

    if status != "requested" && status != "confirmed" {
        return Err(AppError::InvalidStatus);
    }

    // Idempotent : si déjà demandé, retourne callback_requested sans ré-écrire.
    if let Some(ts) = existing {
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(CallbackRequestResponse {
            appointment_id: id,
            callback_requested_at: ts.to_rfc3339(),
            status: "callback_requested".to_string(),
        }));
    }

    // Scope cabinet pour UPDATE (tenant_isolation) + audit.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE appointment \
         SET callback_requested_at = now(), updated_at = now() \
         WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let ts_row = sqlx::query("SELECT callback_requested_at FROM appointment WHERE id = $1")
        .bind(id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let callback_requested_at: chrono::DateTime<chrono::Utc> = ts_row
        .try_get("callback_requested_at")
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'request_callback', 'appointment', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    dispatcher.enqueue_notify_callback(id, cabinet_id);

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        "appointment callback requested"
    );

    Ok(Json(CallbackRequestResponse {
        appointment_id: id,
        callback_requested_at: callback_requested_at.to_rfc3339(),
        status: "callback_requested".to_string(),
    }))
}

// ── Queue ────────────────────────────────────────────────────────────────────

/// Réponse de `GET /v1/appointments/:id/queue`.
#[derive(Serialize)]
pub struct QueueResponse {
    pub position: Option<i64>,
    pub est_wait_min: Option<i64>,
    pub status: String,
}

/// `GET /v1/appointments/:id/queue` — position du patient dans la salle d'attente virtuelle.
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// `position` = nombre de rendez-vous antérieurs (checkin_at < le nôtre) pour le même praticien
/// avec status `checked_in` ou `in_progress`, bornés à la file DU JOUR (`starts_at` du jour courant),
/// comme la waiting-room (`scheduling::get_waiting_room`).
/// `est_wait_min` reste `null` (pas d'estimation de temps d'attente en MVP).
/// Si le patient n'est pas encore checké (`status` ni `checked_in` ni `in_progress`), `position`
/// vaut `null` et `status` vaut `"not_checked_in"` : le patient n'est pas dans la file d'attente.
pub async fn get_appointment_queue(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<QueueResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, status, checkin_at, practitioner_id, cabinet_id \
         FROM appointment \
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(appt_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let checkin_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("checkin_at").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;

    // Scope cabinet pour les requêtes soumises à la RLS tenant_isolation.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Compte les rendez-vous antérieurs dans la file du même praticien.
    let position: i64 = if let Some(our_checkin_at) = checkin_at {
        sqlx::query(
            "SELECT COUNT(*) AS cnt \
             FROM appointment \
             WHERE practitioner_id = $1 \
               AND status IN ('checked_in', 'in_progress') \
               AND deleted_at IS NULL \
               AND starts_at >= date_trunc('day', now()) \
               AND starts_at < date_trunc('day', now()) + interval '1 day' \
               AND checkin_at < $2 \
               AND id != $3",
        )
        .bind(practitioner_id)
        .bind(our_checkin_at)
        .bind(id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get::<i64, _>("cnt")
        .map_err(|_| AppError::Internal)?
    } else {
        // Patient pas encore checké : retourne la taille totale de la file.
        sqlx::query(
            "SELECT COUNT(*) AS cnt \
             FROM appointment \
             WHERE practitioner_id = $1 \
               AND status IN ('checked_in', 'in_progress') \
               AND deleted_at IS NULL \
               AND starts_at >= date_trunc('day', now()) \
               AND starts_at < date_trunc('day', now()) + interval '1 day'",
        )
        .bind(practitioner_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get::<i64, _>("cnt")
        .map_err(|_| AppError::Internal)?
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        position,
        "appointment queue queried"
    );

    // position 1-indexée : le patient en tête de file est en position 1.
    let position_1 = position + 1;

    // Mapping statut DB → statut file spec §7 :
    //   in_progress → "in_progress"   (patient appelé, en consultation)
    //   checked_in  → "waiting"       (en salle d'attente)
    //   sinon       → "not_checked_in" (pas encore en salle d'attente : confirmed/requested/
    //                                   cancelled/no_show/completed, etc.)
    let queue_status = match status.as_str() {
        "in_progress" => "in_progress",
        "checked_in" => "waiting",
        _ => "not_checked_in",
    };

    // Un RDV non checké n'a pas sa place dans la file : pas de position.
    let position_out = if queue_status == "not_checked_in" {
        None
    } else {
        Some(position_1)
    };

    Ok(Json(QueueResponse {
        position: position_out,
        est_wait_min: None,
        status: queue_status.to_string(),
    }))
}

fn validate_appointment_payload(starts_at: chrono::DateTime<chrono::Utc>) -> Result<(), AppError> {
    if starts_at <= chrono::Utc::now() + chrono::Duration::minutes(5) {
        return Err(AppError::StartAtNotFuture);
    }
    Ok(())
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
/// `Idempotency-Key` optionnel : si fourni, un second appel avec la même clé retourne le RDV
/// existant (`201`) sans insérer de doublon.
/// Le statut initial est toujours `"requested"` (confirmation asynchrone par le cabinet).
/// Réponse : même shape que `GET /v1/appointments/:id`.
pub async fn create_appointment(
    State(state): State<AppState>,
    Extension(hub): Extension<std::sync::Arc<crate::realtime::WsHub>>,
    claims: PatientAccountClaims,
    headers: HeaderMap,
    Json(body): Json<CreateAppointmentBody>,
) -> Result<(StatusCode, Json<AppointmentDetail>), AppError> {
    if body.slot_id.is_none() && body.starts_at.is_none() {
        return Err(AppError::ValidationError);
    }

    // Validate starts_at when provided directly (not via slot_id).
    if body.slot_id.is_none() {
        if let Some(s) = body.starts_at.as_deref() {
            let sa = s
                .parse::<chrono::DateTime<chrono::Utc>>()
                .map_err(|_| AppError::ValidationError)?;
            validate_appointment_payload(sa)?;
        }
    }

    let idempotency_key: Option<String> = headers
        .get("idempotency-key")
        .and_then(|v| v.to_str().ok())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_owned());

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
    let provider_row = sqlx::query(
        "SELECT cabinet_id, practitioner_id, display_name, specialite FROM provider WHERE id = $1",
    )
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
    let _provider_display_name: Option<String> = provider_row.try_get("display_name").ok();
    let _provider_specialty: Option<String> = provider_row.try_get("specialite").ok();

    // Scope cabinet pour les INSERTs soumis à la RLS tenant_isolation.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Fetch cabinet name + address for the response body.
    let cab_row = sqlx::query(
        "SELECT raison_sociale, settings->>'address' AS address FROM cabinet WHERE id = $1",
    )
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::Internal)?;

    let _cabinet_name: String = cab_row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;
    let _cabinet_address: Option<String> =
        cab_row.try_get("address").map_err(|_| AppError::Internal)?;

    // Idempotence : si une Idempotency-Key est fournie et qu'un RDV existe déjà pour ce
    // cabinet + clé, on retourne le RDV existant sans insérer de doublon. Une clé rejouée
    // avec une charge utile différente ne doit jamais renvoyer le RDV d'une autre requête
    // (#3632, jumeau de #3547/#3620 côté bookings.rs) -> empreinte comparée, divergence ->
    // 409 au lieu d'absorber silencieusement la 2e réservation.
    if let Some(ref key) = idempotency_key {
        let fingerprint = format!(
            "provider={}|slot={}|starts_at={}|motif={}|on_behalf_of={}",
            body.provider_id,
            body.slot_id.map(|s| s.to_string()).unwrap_or_default(),
            body.starts_at.as_deref().unwrap_or(""),
            body.motif.as_deref().unwrap_or(""),
            body.on_behalf_of.map(|s| s.to_string()).unwrap_or_default(),
        );

        let existing = sqlx::query(
            "SELECT id, status, starts_at, ends_at, motif, idempotency_fingerprint FROM appointment \
             WHERE cabinet_id = $1 AND idempotency_key = $2",
        )
        .bind(cabinet_id)
        .bind(key)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        if let Some(row) = existing {
            let cached_fingerprint: Option<String> = row
                .try_get("idempotency_fingerprint")
                .map_err(|_| AppError::Internal)?;
            if cached_fingerprint.as_deref() != Some(fingerprint.as_str()) {
                tx.commit().await.map_err(|_| AppError::Internal)?;
                tracing::warn!(
                    account_id = %claims.account_id,
                    "appointment idempotency key replayed with a different fingerprint"
                );
                return Err(AppError::IdempotencyKeyConflict);
            }

            let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            let idem_starts_at: chrono::DateTime<chrono::Utc> =
                row.try_get("starts_at").map_err(|_| AppError::Internal)?;
            let idem_ends_at: chrono::DateTime<chrono::Utc> =
                row.try_get("ends_at").map_err(|_| AppError::Internal)?;
            let idem_motif: Option<String> =
                row.try_get("motif").map_err(|_| AppError::Internal)?;

            let (prov_id, prov_name, prov_spec) =
                fetch_provider_for_response(&mut tx, practitioner_id).await?;
            let (cab_name, cab_addr) =
                fetch_cabinet_for_response(&mut tx, cabinet_id, practitioner_id).await?;

            tx.commit().await.map_err(|_| AppError::Internal)?;
            tracing::info!(
                account_id = %claims.account_id,
                appointment_id = %appointment_id,
                "appointment create idempotent hit"
            );
            return Ok((
                StatusCode::CREATED,
                Json(AppointmentDetail {
                    id: appointment_id,
                    starts_at: idem_starts_at.to_rfc3339(),
                    ends_at: idem_ends_at.to_rfc3339(),
                    status,
                    motif: idem_motif,
                    provider: ProviderDetail {
                        id: prov_id,
                        display_name: prov_name,
                        specialty: prov_spec,
                    },
                    cabinet: CabinetInfo {
                        name: cab_name,
                        address: cab_addr,
                    },
                }),
            ));
        }
    }

    // Récupère-ou-crée le dossier patient de ce cabinet (SECURITY DEFINER,
    // migration 0123 — même fonction que create_booking). Un simple SELECT
    // 404 sur un dossier absent : cas NORMAL pour un dépendant (compte géré
    // sans fiche patient tant qu'il n'a jamais consulté dans ce cabinet),
    // rendant `on_behalf_of` totalement inutilisable (#3739/#3836). NULL
    // uniquement si le compte lui-même n'existe pas → 404 légitime.
    let patient_id: Uuid =
        sqlx::query_scalar::<_, Option<Uuid>>("SELECT ensure_patient_for_cabinet($1, $2)")
            .bind(effective_account_id)
            .bind(cabinet_id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;

    // Résout starts_at / ends_at selon slot_id ou starts_at fourni.
    // status = 'open' : un créneau blocked (indispo praticien) ou held (hold
    // patient actif) ne doit pas être réservable, au même titre que le
    // chemin cabinet (create_cabinet_appointment).
    let (starts_at, ends_at, resolved_slot_id) = if let Some(slot_id) = body.slot_id {
        let slot_row = sqlx::query(
            "SELECT starts_at, ends_at FROM availability_slot \
             WHERE id = $1 AND cabinet_id = $2 AND practitioner_id = $3 \
             AND deleted_at IS NULL AND status = 'open'",
        )
        .bind(slot_id)
        .bind(cabinet_id)
        .bind(practitioner_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::SlotTaken)?;

        let sa: chrono::DateTime<chrono::Utc> = slot_row
            .try_get("starts_at")
            .map_err(|_| AppError::Internal)?;
        let ea: chrono::DateTime<chrono::Utc> = slot_row
            .try_get("ends_at")
            .map_err(|_| AppError::Internal)?;
        (sa, ea, Some(slot_id))
    } else {
        let sa = body
            .starts_at
            .as_deref()
            .and_then(|s| s.parse::<chrono::DateTime<chrono::Utc>>().ok())
            .ok_or(AppError::ValidationError)?;

        // La branche starts_at doit résoudre/exiger un availability_slot 'open'
        // du praticien, comme la branche slot_id ci-dessus et comme la
        // reprogrammation (patch_appointment) — sinon starts_at est accepté
        // sans aucun créneau réel (heure hors-agenda) et l'exclusion GiST ne
        // bloque que les chevauchements, pas les horaires impossibles (#3722).
        let slot_row = sqlx::query(
            "SELECT id, ends_at FROM availability_slot \
             WHERE cabinet_id = $1 AND practitioner_id = $2 AND starts_at = $3 \
             AND deleted_at IS NULL AND status = 'open'",
        )
        .bind(cabinet_id)
        .bind(practitioner_id)
        .bind(sa)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::SlotTaken)?;

        let resolved_id: Uuid = slot_row.try_get("id").map_err(|_| AppError::Internal)?;
        let ea: chrono::DateTime<chrono::Utc> = slot_row
            .try_get("ends_at")
            .map_err(|_| AppError::Internal)?;
        (sa, ea, Some(resolved_id))
    };

    let fingerprint = idempotency_key.as_ref().map(|_| {
        format!(
            "provider={}|slot={}|starts_at={}|motif={}|on_behalf_of={}",
            body.provider_id,
            body.slot_id.map(|s| s.to_string()).unwrap_or_default(),
            body.starts_at.as_deref().unwrap_or(""),
            body.motif.as_deref().unwrap_or(""),
            body.on_behalf_of.map(|s| s.to_string()).unwrap_or_default(),
        )
    });

    // INSERT — 23P01 (appointment_no_overlap) → 409 slot_taken.
    let result = sqlx::query(
        "INSERT INTO appointment \
         (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif, slot_id, idempotency_key, idempotency_fingerprint) \
         VALUES ($1, $2, $3, $4, $5, 'requested', $6, $7, $8, $9) \
         RETURNING id, status",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(body.motif.as_deref())
    .bind(resolved_slot_id)
    .bind(&idempotency_key)
    .bind(&fingerprint)
    .fetch_one(&mut *tx)
    .await;

    let inserted_row = match result {
        Ok(row) => row,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    let appointment_id: Uuid = inserted_row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = inserted_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;

    // Consomme le créneau : il ne doit plus apparaître dans la recherche de
    // disponibilités (`/v1/search/slots` filtre `status = 'open'`). Symétrique de
    // l'annulation qui le repasse à 'open'. Scopé cabinet (slot_cabinet_write).
    // Les deux branches ci-dessus résolvent désormais un availability_slot réel
    // (#3722), resolved_slot_id est toujours Some ici.
    if let Some(slot_id) = resolved_slot_id {
        sqlx::query(
            "UPDATE availability_slot SET status = 'booked', updated_at = now() \
             WHERE id = $1 AND cabinet_id = $2",
        )
        .bind(slot_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    // Fetch provider + cabinet pour la réponse (même shape que GET /:id).
    let (provider_id, provider_display_name, provider_specialty) =
        fetch_provider_for_response(&mut tx, practitioner_id).await?;
    let (cabinet_name, cabinet_address) =
        fetch_cabinet_for_response(&mut tx, cabinet_id, practitioner_id).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    hub.publish(
        cabinet_id,
        serde_json::json!({
            "channel": "waiting_room",
            "event": "queue_updated",
            "data": { "appointment_id": appointment_id, "status": status }
        })
        .to_string(),
    );

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %appointment_id,
        "appointment created"
    );

    Ok((
        StatusCode::CREATED,
        Json(AppointmentDetail {
            id: appointment_id,
            starts_at: starts_at.to_rfc3339(),
            ends_at: ends_at.to_rfc3339(),
            status,
            motif: body.motif,
            provider: ProviderDetail {
                id: provider_id,
                display_name: provider_display_name,
                specialty: provider_specialty,
            },
            cabinet: CabinetInfo {
                name: cabinet_name,
                address: cabinet_address,
            },
        }),
    ))
}

async fn fetch_provider_for_response(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    practitioner_id: Uuid,
) -> Result<(Option<Uuid>, Option<String>, Option<String>), AppError> {
    let row = sqlx::query(
        "SELECT id, display_name, specialite FROM provider \
         WHERE practitioner_id = $1 LIMIT 1",
    )
    .bind(practitioner_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(match row {
        Some(r) => {
            let pid: Uuid = r.try_get("id").map_err(|_| AppError::Internal)?;
            let dn: String = r.try_get("display_name").map_err(|_| AppError::Internal)?;
            let sp: Option<String> = r.try_get("specialite").map_err(|_| AppError::Internal)?;
            (Some(pid), Some(dn), sp)
        }
        None => (None, None, None),
    })
}

async fn fetch_cabinet_for_response(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    practitioner_id: Uuid,
) -> Result<(String, Option<String>), AppError> {
    let row = sqlx::query(
        "SELECT raison_sociale, settings->>'address' AS address FROM cabinet WHERE id = $1",
    )
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::Internal)?;

    let name: String = row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;
    let address: Option<String> = row.try_get("address").map_err(|_| AppError::Internal)?;

    // Fallback establishment quand `cabinet.settings` ne porte pas d'adresse
    // (cas du cabinet seed — #3557), déjà appliqué à preparation/directions
    // mais pas ici : détail/create/patch renvoyaient `address: null` (#3799).
    let address = if address.is_some() {
        address
    } else {
        let est_row = sqlx::query(
            "SELECT e.address AS establishment_address \
             FROM provider p \
             LEFT JOIN establishment e ON e.id = p.establishment_id \
             WHERE p.practitioner_id = $1 \
             LIMIT 1",
        )
        .bind(practitioner_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

        est_row
            .and_then(|r| {
                r.try_get::<Option<serde_json::Value>, _>("establishment_address")
                    .ok()
                    .flatten()
            })
            .as_ref()
            .and_then(format_establishment_address)
    };

    Ok((name, address))
}
