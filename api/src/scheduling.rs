//! Handler `GET /v1/cabinet/agenda` — agenda du cabinet pour le secrétariat et le praticien.

use axum::{
    extract::{Path, Query, State},
    Json,
};
use chrono::TimeZone;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims, ProSecretaryPlusClaims},
    AppState,
};

#[derive(Deserialize)]
pub struct AgendaQuery {
    /// "day" (défaut) ou "week".
    pub view: Option<String>,
    /// Filtre optionnel sur un praticien.
    pub practitioner_id: Option<Uuid>,
    /// Date ISO 8601 "YYYY-MM-DD" (défaut : aujourd'hui UTC).
    pub date: Option<String>,
}

#[derive(Serialize)]
pub struct PractitionerItem {
    pub id: Uuid,
    pub display_name: Option<String>,
    pub specialite: Option<String>,
}

#[derive(Serialize)]
pub struct AgendaSlot {
    pub id: Uuid,
    pub practitioner_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub status: String,
    /// Motif administratif (R.4127-72 : visible secrétariat+).
    pub motif_admin: Option<String>,
}

#[derive(Serialize)]
pub struct AgendaResponse {
    pub practitioners: Vec<PractitionerItem>,
    pub slots: Vec<AgendaSlot>,
}

/// `GET /v1/cabinet/agenda` — agenda du cabinet (praticiens + créneaux).
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT, jamais du query string (invariant tenancy).
/// RLS scopé via `app.current_cabinet_id`. Secrétariat : `motif_admin` uniquement (R.4127-72).
/// Query params : `view=day|week`, `practitioner_id=<uuid>`, `date=YYYY-MM-DD`.
pub async fn get_cabinet_agenda(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<AgendaQuery>,
) -> Result<Json<AgendaResponse>, AppError> {
    let base_date = params
        .date
        .as_deref()
        .and_then(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").ok())
        .unwrap_or_else(|| chrono::Utc::now().date_naive());

    let ndt = base_date
        .and_hms_opt(0, 0, 0)
        .ok_or(AppError::ValidationError)?;
    let range_start: chrono::DateTime<chrono::Utc> = chrono::Utc.from_utc_datetime(&ndt);

    let days: i64 = if params.view.as_deref() == Some("week") {
        7
    } else {
        1
    };
    let range_end = range_start + chrono::Duration::days(days);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Tous les praticiens du cabinet avec leur profil public si disponible.
    let pract_rows = sqlx::query(
        "SELECT p.id, pr.display_name, p.specialite \
         FROM practitioner p \
         LEFT JOIN provider pr ON pr.practitioner_id = p.id \
         WHERE p.cabinet_id = $1 \
         ORDER BY pr.display_name NULLS LAST, p.id",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let practitioners = pract_rows
        .into_iter()
        .map(|row| {
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let display_name: Option<String> = row
                .try_get("display_name")
                .map_err(|_| AppError::Internal)?;
            let specialite: Option<String> =
                row.try_get("specialite").map_err(|_| AppError::Internal)?;
            Ok(PractitionerItem {
                id,
                display_name,
                specialite,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    // Créneaux dans la plage, filtrés optionnellement par praticien.
    let slot_rows = if let Some(pid) = params.practitioner_id {
        sqlx::query(
            "SELECT id, practitioner_id, starts_at, ends_at, status, motif \
             FROM appointment \
             WHERE deleted_at IS NULL \
               AND starts_at >= $1 AND starts_at < $2 \
               AND practitioner_id = $3 \
             ORDER BY starts_at",
        )
        .bind(range_start)
        .bind(range_end)
        .bind(pid)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    } else {
        sqlx::query(
            "SELECT id, practitioner_id, starts_at, ends_at, status, motif \
             FROM appointment \
             WHERE deleted_at IS NULL \
               AND starts_at >= $1 AND starts_at < $2 \
             ORDER BY starts_at",
        )
        .bind(range_start)
        .bind(range_end)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Cloisonnement R.4127-72 : le secrétariat voit le motif admin uniquement.
    // Lorsque motif_clinique sera ajouté au schéma, l'exclure si role == "secretary".
    let _show_clinical = claims.role != "secretary";

    let slots = slot_rows
        .into_iter()
        .map(|row| {
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let practitioner_id: Uuid = row
                .try_get("practitioner_id")
                .map_err(|_| AppError::Internal)?;
            let starts_at: chrono::DateTime<chrono::Utc> =
                row.try_get("starts_at").map_err(|_| AppError::Internal)?;
            let ends_at: chrono::DateTime<chrono::Utc> =
                row.try_get("ends_at").map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            let motif_admin: Option<String> =
                row.try_get("motif").map_err(|_| AppError::Internal)?;
            Ok(AgendaSlot {
                id,
                practitioner_id,
                starts_at: starts_at.to_rfc3339(),
                ends_at: ends_at.to_rfc3339(),
                status,
                motif_admin,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        role = %claims.role,
        date = %base_date,
        slot_count = slots.len(),
        "cabinet agenda queried"
    );

    Ok(Json(AgendaResponse {
        practitioners,
        slots,
    }))
}

#[derive(Serialize)]
pub struct CallNextResponse {
    pub called: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub appointment_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub patient_display_name: Option<String>,
}

/// `POST /v1/cabinet/waiting-room/call-next` — appelle le prochain patient checked-in.
///
/// Token pro practitioner+ requis (secretary → 403, patient → 403).
/// RLS scopé via `app.current_cabinet_id`. Passe le statut `checked_in` → `in_progress`.
/// Aucun patient en file → `{ called: false }`. Notification stub (NUB-T3).
pub async fn call_next_patient(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
) -> Result<Json<CallNextResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Prochain rendez-vous checked_in (FIFO sur checkin_at).
    // FOR UPDATE SKIP LOCKED évite les doubles appels concurrents.
    let maybe_apt = sqlx::query(
        "SELECT id, patient_id FROM appointment \
         WHERE status = 'checked_in' AND deleted_at IS NULL \
         ORDER BY checkin_at ASC NULLS LAST, starts_at ASC \
         LIMIT 1 \
         FOR UPDATE SKIP LOCKED",
    )
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(apt_row) = maybe_apt else {
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(CallNextResponse {
            called: false,
            appointment_id: None,
            patient_display_name: None,
        }));
    };

    let appointment_id: Uuid = apt_row.try_get("id").map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = apt_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

    sqlx::query("UPDATE appointment SET status = 'in_progress', updated_at = now() WHERE id = $1")
        .bind(appointment_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let pat_row = sqlx::query(
        "SELECT first_name, last_name FROM patient WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let patient_display_name = if let Some(row) = pat_row {
        let first: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
        let last: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
        format!("{first} {last}")
    } else {
        String::new()
    };

    // Stub : notification push + event WebSocket (NUB-T3).

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        appointment_id = %appointment_id,
        "waiting room: called next patient"
    );

    Ok(Json(CallNextResponse {
        called: true,
        appointment_id: Some(appointment_id),
        patient_display_name: Some(patient_display_name),
    }))
}

// ── Waiting room (file du jour) ───────────────────────────────────────────────

/// Un poste dans la file d'attente temps-réel (patients checked_in ou in_progress aujourd'hui).
#[derive(Serialize)]
pub struct WaitingRoomEntry {
    pub appointment_id: Uuid,
    pub patient_id: Uuid,
    pub status: String,
    /// Horodatage du check-in (null si non encore renseigné).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub checkin_at: Option<String>,
}

/// Réponse de `GET /v1/cabinet/waiting-room`.
#[derive(Serialize)]
pub struct WaitingRoomResponse {
    pub entries: Vec<WaitingRoomEntry>,
}

/// `GET /v1/cabinet/waiting-room` — file d'attente temps-réel du cabinet (§13).
///
/// Retourne les rendez-vous du jour en statut `checked_in` ou `in_progress`,
/// triés FIFO (checkin_at ASC NULLS LAST, starts_at ASC).
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT. RLS via `app.current_cabinet_id`.
/// Pas de PII dans le payload (patient_id uniquement, pas de nom).
pub async fn get_waiting_room(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<WaitingRoomResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, patient_id, status, checkin_at \
         FROM appointment \
         WHERE deleted_at IS NULL \
           AND status IN ('checked_in', 'in_progress') \
           AND starts_at >= date_trunc('day', now()) \
           AND starts_at < date_trunc('day', now()) + interval '1 day' \
         ORDER BY checkin_at ASC NULLS LAST, starts_at ASC",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let entries = rows
        .into_iter()
        .map(|row| -> Result<WaitingRoomEntry, AppError> {
            let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            let checkin_at: Option<chrono::DateTime<chrono::Utc>> =
                row.try_get("checkin_at").map_err(|_| AppError::Internal)?;
            Ok(WaitingRoomEntry {
                appointment_id,
                patient_id,
                status,
                checkin_at: checkin_at.map(|dt| dt.to_rfc3339()),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        count = entries.len(),
        "waiting room queried"
    );

    Ok(Json(WaitingRoomResponse { entries }))
}

// ── Waiting list (liste d'attente) ────────────────────────────────────────────

/// Entrée de liste d'attente (waiting_list_entry) exposée au secrétariat+.
#[derive(Serialize)]
pub struct WaitingListItem {
    pub id: Uuid,
    pub patient_id: Uuid,
    /// Fenêtre souhaitée (JSON libre — desired_window).
    pub desired_window: serde_json::Value,
    pub score: f64,
    pub status: String,
    pub created_at: String,
}

/// Réponse de `GET /v1/cabinet/waiting-list`.
#[derive(Serialize)]
pub struct WaitingListResponse {
    pub data: Vec<WaitingListItem>,
}

/// `GET /v1/cabinet/waiting-list` — liste d'attente du cabinet (§13).
///
/// Retourne les entrées actives (`status = 'active'`) triées par score DESC puis created_at ASC.
/// RBAC : `secretary+` (`ProSecretaryPlusClaims`) — praticien seul → pas de restriction
/// supplémentaire (both roles are covered by ProSecretaryPlusClaims).
/// `cabinet_id` extrait du JWT. RLS via `app.current_cabinet_id`.
pub async fn get_waiting_list(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<WaitingListResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, patient_id, desired_window, score::float8 AS score, status, created_at \
         FROM waiting_list_entry \
         WHERE status = 'active' \
         ORDER BY score DESC, created_at ASC",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .into_iter()
        .map(|row| -> Result<WaitingListItem, AppError> {
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
            let desired_window: serde_json::Value = row
                .try_get("desired_window")
                .map_err(|_| AppError::Internal)?;
            let score: f64 = row.try_get("score").map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            let created_at: chrono::DateTime<chrono::Utc> =
                row.try_get("created_at").map_err(|_| AppError::Internal)?;
            Ok(WaitingListItem {
                id,
                patient_id,
                desired_window,
                score,
                status,
                created_at: created_at.to_rfc3339(),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        count = data.len(),
        "waiting list queried"
    );

    Ok(Json(WaitingListResponse { data }))
}

// ── Offer (proposer un créneau libéré) ───────────────────────────────────────

/// Corps de `POST /v1/cabinet/waiting-list/:id/offer`.
#[derive(Deserialize)]
pub struct OfferSlotBody {
    /// Créneau proposé (ISO 8601 UTC).
    pub proposed_at: String,
}

/// Réponse de `POST /v1/cabinet/waiting-list/:id/offer`.
#[derive(Serialize)]
pub struct OfferSlotResponse {
    pub waiting_list_entry_id: Uuid,
    pub notified: bool,
}

/// `POST /v1/cabinet/waiting-list/:id/offer` — propose un créneau libéré (§13).
///
/// Vérifie que l'entrée est `active` et appartient au cabinet (RLS fail-closed).
/// Passe le statut → `fulfilled`. Notification stub (NUB-T3) — aucun PII dans le payload.
/// RBAC : `secretary+`. `cabinet_id` extrait du JWT.
pub async fn offer_waiting_list_slot(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    axum::extract::Path(entry_id): axum::extract::Path<Uuid>,
    Json(body): Json<OfferSlotBody>,
) -> Result<Json<OfferSlotResponse>, AppError> {
    // Valide le format de la date proposée avant toute requête DB.
    body.proposed_at
        .parse::<chrono::DateTime<chrono::Utc>>()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie existence + statut actif (RLS garantit l'appartenance au cabinet).
    let row = sqlx::query("SELECT id, status FROM waiting_list_entry WHERE id = $1")
        .bind(entry_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    if status != "active" {
        return Err(AppError::InvalidStatus);
    }

    sqlx::query("UPDATE waiting_list_entry SET status = 'fulfilled' WHERE id = $1")
        .bind(entry_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Stub : notification push au patient (NUB-T3) — pas de PII dans le payload.

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        entry_id = %entry_id,
        "waiting list: slot offered"
    );

    Ok(Json(OfferSlotResponse {
        waiting_list_entry_id: entry_id,
        notified: true,
    }))
}

// ── Cabinet appointments list ────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct CabinetAppointmentsQuery {
    /// Filtre optionnel sur le statut.
    pub status: Option<String>,
    /// Date ISO 8601 "YYYY-MM-DD" — restreint aux RDV de ce jour.
    pub date: Option<String>,
}

#[derive(Serialize)]
pub struct CabinetAppointmentItem {
    pub id: Uuid,
    pub practitioner_id: Uuid,
    pub patient_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub status: String,
    /// Motif administratif visible par secrétariat+.
    pub motif_admin: Option<String>,
}

#[derive(Serialize)]
pub struct CabinetAppointmentsResponse {
    pub data: Vec<CabinetAppointmentItem>,
}

/// `GET /v1/cabinet/appointments` — liste les RDV du cabinet (secrétariat, praticien, admin).
///
/// Token pro requis (secretary, practitioner, admin). `cabinet_id` extrait du JWT.
/// RLS scopé via `app.current_cabinet_id`. RBAC R.4127-72 : secrétariat voit `motif` uniquement
/// (pas de champ clinique distinct à ce stade — le motif unique est l'admin).
/// Query : `status=<statut>`, `date=YYYY-MM-DD` (filtre sur `starts_at` du jour).
pub async fn get_cabinet_appointments(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<CabinetAppointmentsQuery>,
) -> Result<Json<CabinetAppointmentsResponse>, AppError> {
    let date_filter: Option<(chrono::DateTime<chrono::Utc>, chrono::DateTime<chrono::Utc>)> =
        if let Some(date_str) = &params.date {
            let d = chrono::NaiveDate::parse_from_str(date_str, "%Y-%m-%d")
                .map_err(|_| AppError::ValidationError)?;
            let ndt_start = d.and_hms_opt(0, 0, 0).ok_or(AppError::ValidationError)?;
            let range_start = chrono::Utc.from_utc_datetime(&ndt_start);
            let range_end = range_start + chrono::Duration::days(1);
            Some((range_start, range_end))
        } else {
            None
        };

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Construit la requête dynamiquement selon les filtres optionnels.
    let rows = match (&params.status, &date_filter) {
        (Some(status), Some((ds, de))) => sqlx::query(
            "SELECT id, practitioner_id, patient_id, starts_at, ends_at, status, motif \
             FROM appointment \
             WHERE deleted_at IS NULL \
               AND cabinet_id = $1 \
               AND status = $2 \
               AND starts_at >= $3 AND starts_at < $4 \
             ORDER BY starts_at",
        )
        .bind(claims.cabinet_id)
        .bind(status)
        .bind(ds)
        .bind(de)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?,

        (Some(status), None) => sqlx::query(
            "SELECT id, practitioner_id, patient_id, starts_at, ends_at, status, motif \
             FROM appointment \
             WHERE deleted_at IS NULL \
               AND cabinet_id = $1 \
               AND status = $2 \
             ORDER BY starts_at",
        )
        .bind(claims.cabinet_id)
        .bind(status)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?,

        (None, Some((ds, de))) => sqlx::query(
            "SELECT id, practitioner_id, patient_id, starts_at, ends_at, status, motif \
             FROM appointment \
             WHERE deleted_at IS NULL \
               AND cabinet_id = $1 \
               AND starts_at >= $2 AND starts_at < $3 \
             ORDER BY starts_at",
        )
        .bind(claims.cabinet_id)
        .bind(ds)
        .bind(de)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?,

        (None, None) => sqlx::query(
            "SELECT id, practitioner_id, patient_id, starts_at, ends_at, status, motif \
             FROM appointment \
             WHERE deleted_at IS NULL \
               AND cabinet_id = $1 \
             ORDER BY starts_at",
        )
        .bind(claims.cabinet_id)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?,
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // RBAC R.4127-72 : secrétariat voit motif administratif uniquement.
    // Le motif unique courant est déjà le motif admin ; lorsque motif_clinique
    // sera ajouté, l'exclure si role == "secretary".
    let mut data: Vec<CabinetAppointmentItem> = Vec::with_capacity(rows.len());
    for row in &rows {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let practitioner_id: Uuid = row
            .try_get("practitioner_id")
            .map_err(|_| AppError::Internal)?;
        let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
        let starts_at: chrono::DateTime<chrono::Utc> =
            row.try_get("starts_at").map_err(|_| AppError::Internal)?;
        let ends_at: chrono::DateTime<chrono::Utc> =
            row.try_get("ends_at").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        let motif_admin: Option<String> = row.try_get("motif").map_err(|_| AppError::Internal)?;
        data.push(CabinetAppointmentItem {
            id,
            practitioner_id,
            patient_id,
            starts_at: starts_at.to_rfc3339(),
            ends_at: ends_at.to_rfc3339(),
            status,
            motif_admin,
        });
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        role = %claims.role,
        count = data.len(),
        "cabinet appointments listed"
    );

    Ok(Json(CabinetAppointmentsResponse { data }))
}

// ── Confirm appointment ───────────────────────────────────────────────────────

#[derive(Serialize)]
pub struct ConfirmAppointmentResponse {
    pub appointment_id: Uuid,
    pub status: String,
}

/// `POST /v1/cabinet/appointments/:id/confirm` — confirme un RDV en attente (`requested → confirmed`).
///
/// Token pro requis (secretary+). `cabinet_id` extrait du JWT — jamais du body.
/// RLS scopé via `app.current_cabinet_id` : 404 si le RDV n'appartient pas au cabinet.
/// Statut attendu : `requested` → `409 invalid_status` sinon.
/// Toute confirmation est auditée dans `audit_log`.
pub async fn confirm_appointment(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<ConfirmAppointmentResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, status FROM appointment \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(appt_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    if status != "requested" {
        return Err(AppError::InvalidStatus);
    }

    sqlx::query("UPDATE appointment SET status = 'confirmed', updated_at = now() WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'confirm_appointment', 'appointment', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        appointment_id = %id,
        "appointment confirmed"
    );

    Ok(Json(ConfirmAppointmentResponse {
        appointment_id: id,
        status: "confirmed".to_string(),
    }))
}

// ── Cabinet PATCH appointment ─────────────────────────────────────────────────

/// Corps de la requête `PATCH /v1/cabinet/appointments/:id`.
#[derive(Deserialize)]
pub struct PatchCabinetAppointmentBody {
    /// Nouveau créneau de début (ISO 8601 UTC). La durée est préservée.
    pub starts_at: Option<String>,
    /// Nouveau motif administratif.
    pub motif: Option<String>,
}

/// Réponse de `PATCH /v1/cabinet/appointments/:id`.
#[derive(Serialize)]
pub struct PatchCabinetAppointmentResponse {
    pub appointment_id: Uuid,
    pub status: String,
}

fn is_exclusion_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23P01")
    )
}

/// `PATCH /v1/cabinet/appointments/:id` — déplace ou édite un RDV côté cabinet.
///
/// Token pro requis (secretary+). `cabinet_id` extrait du JWT. 404 si le RDV
/// n'appartient pas au cabinet (RLS). Statut valide pour modification :
/// `requested` ou `confirmed` → `409 invalid_status` sinon.
/// Conflit créneau (contrainte PG `23P01`) → `409 slot_taken`.
/// Toute modification est auditée dans `audit_log`.
pub async fn patch_cabinet_appointment(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(appt_id): Path<Uuid>,
    Json(body): Json<PatchCabinetAppointmentBody>,
) -> Result<Json<PatchCabinetAppointmentResponse>, AppError> {
    let new_starts_at: Option<chrono::DateTime<chrono::Utc>> = body
        .starts_at
        .as_deref()
        .map(|s| s.parse::<chrono::DateTime<chrono::Utc>>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, status FROM appointment \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(appt_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    if status != "requested" && status != "confirmed" {
        return Err(AppError::InvalidStatus);
    }

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
         VALUES ($1, $2, $3, 'update_appointment', 'appointment', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        appointment_id = %id,
        "cabinet appointment patched"
    );

    Ok(Json(PatchCabinetAppointmentResponse {
        appointment_id,
        status: new_status,
    }))
}
