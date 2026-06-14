//! Handler `GET /v1/cabinet/agenda` — agenda du cabinet pour le secrétariat et le praticien.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
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

    // R10 : secrétaires scopées au secrétariat actif — praticiens assignés uniquement.
    // Praticiens du cabinet (tous rôles) ou filtrés par secrétariat (role=secretary).
    let pract_rows = if claims.role == "secretary" {
        if let Some(sid) = claims.secretariat_id {
            sqlx::query(
                "SELECT p.id, pr.display_name, p.specialite \
                 FROM practitioner p \
                 LEFT JOIN provider pr ON pr.practitioner_id = p.id \
                 WHERE p.cabinet_id = $1 \
                   AND EXISTS ( \
                       SELECT 1 FROM provider_secretariat ps \
                       WHERE ps.provider_id = pr.id \
                         AND ps.secretariat_id = $2 \
                         AND ps.active = true \
                   ) \
                 ORDER BY pr.display_name NULLS LAST, p.id",
            )
            .bind(claims.cabinet_id)
            .bind(sid)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
        } else {
            // Secrétaire sans secrétariat actif : aucun praticien visible.
            vec![]
        }
    } else {
        sqlx::query(
            "SELECT p.id, pr.display_name, p.specialite \
             FROM practitioner p \
             LEFT JOIN provider pr ON pr.practitioner_id = p.id \
             WHERE p.cabinet_id = $1 \
             ORDER BY pr.display_name NULLS LAST, p.id",
        )
        .bind(claims.cabinet_id)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    };

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
    // R10 : secrétaires scopées au secrétariat actif via provider_secretariat.
    let slot_rows = if let Some(pid) = params.practitioner_id {
        if claims.role == "secretary" {
            if let Some(sid) = claims.secretariat_id {
                sqlx::query(
                    "SELECT a.id, a.practitioner_id, a.starts_at, a.ends_at, a.status, a.motif \
                     FROM appointment a \
                     WHERE a.deleted_at IS NULL \
                       AND a.starts_at >= $1 AND a.starts_at < $2 \
                       AND a.practitioner_id = $3 \
                       AND EXISTS ( \
                           SELECT 1 FROM provider pr \
                           JOIN provider_secretariat ps ON ps.provider_id = pr.id \
                           WHERE pr.practitioner_id = a.practitioner_id \
                             AND ps.secretariat_id = $4 \
                             AND ps.active = true \
                       ) \
                     ORDER BY a.starts_at",
                )
                .bind(range_start)
                .bind(range_end)
                .bind(pid)
                .bind(sid)
                .fetch_all(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
            } else {
                vec![]
            }
        } else {
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
        }
    } else if claims.role == "secretary" {
        if let Some(sid) = claims.secretariat_id {
            sqlx::query(
                "SELECT a.id, a.practitioner_id, a.starts_at, a.ends_at, a.status, a.motif \
                 FROM appointment a \
                 WHERE a.deleted_at IS NULL \
                   AND a.starts_at >= $1 AND a.starts_at < $2 \
                   AND EXISTS ( \
                       SELECT 1 FROM provider pr \
                       JOIN provider_secretariat ps ON ps.provider_id = pr.id \
                       WHERE pr.practitioner_id = a.practitioner_id \
                         AND ps.secretariat_id = $3 \
                         AND ps.active = true \
                   ) \
                 ORDER BY a.starts_at",
            )
            .bind(range_start)
            .bind(range_end)
            .bind(sid)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
        } else {
            vec![]
        }
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
        "SELECT first_name, last_name, app_user_id FROM patient WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (patient_display_name, patient_app_user_id) = if let Some(row) = pat_row {
        let first: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
        let last: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
        let uid: Option<Uuid> = row.try_get("app_user_id").map_err(|_| AppError::Internal)?;
        (format!("{first} {last}"), uid)
    } else {
        (String::new(), None)
    };

    // Notification in-app au patient (si compte rattaché).
    if let Some(uid) = patient_app_user_id {
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(uid.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        sqlx::query(
            "INSERT INTO notification \
             (app_user_id, kind, title, body_ciphertext, body_key_ref, data) \
             VALUES ($1, 'waiting_room_called', 'C''est votre tour', '\\x00'::bytea, 'stub', $2)",
        )
        .bind(uid)
        .bind(serde_json::json!({ "appointment_id": appointment_id }))
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

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

/// `GET /v1/cabinet/waiting-room` — file d'attente temps-réel du cabinet (§13 E.2.14).
///
/// Retourne les rendez-vous du jour avec `checkin_at IS NOT NULL AND started_at IS NULL`
/// (patients arrivés mais consultation non encore commencée), triés FIFO (checkin_at ASC NULLS LAST).
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT. RLS via `app.current_cabinet_id`.
/// Pas de PII dans le payload (patient_id uniquement, pas de nom).
/// R10 : secrétaires scopées au secrétariat JWT (`secretariat_id`).
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

    // R10 : secrétaires scopées au secrétariat actif — seulement les RDV des praticiens assignés.
    let rows = if claims.role == "secretary" {
        if let Some(sid) = claims.secretariat_id {
            sqlx::query(
                "SELECT a.id, a.patient_id, a.status, a.checkin_at \
                 FROM appointment a \
                 WHERE a.deleted_at IS NULL \
                   AND a.checkin_at IS NOT NULL \
                   AND a.started_at IS NULL \
                   AND a.starts_at >= date_trunc('day', now()) \
                   AND a.starts_at < date_trunc('day', now()) + interval '1 day' \
                   AND EXISTS ( \
                       SELECT 1 FROM provider pr \
                       JOIN provider_secretariat ps ON ps.provider_id = pr.id \
                       WHERE pr.practitioner_id = a.practitioner_id \
                         AND ps.secretariat_id = $1 \
                         AND ps.active = true \
                   ) \
                 ORDER BY a.checkin_at ASC NULLS LAST, a.starts_at ASC",
            )
            .bind(sid)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
        } else {
            vec![]
        }
    } else {
        sqlx::query(
            "SELECT id, patient_id, status, checkin_at \
             FROM appointment \
             WHERE deleted_at IS NULL \
               AND checkin_at IS NOT NULL \
               AND started_at IS NULL \
               AND starts_at >= date_trunc('day', now()) \
               AND starts_at < date_trunc('day', now()) + interval '1 day' \
             ORDER BY checkin_at ASC NULLS LAST, starts_at ASC",
        )
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    };

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

// ── Create appointment (secrétariat) ─────────────────────────────────────────

/// Corps de la requête `POST /v1/cabinet/appointments`.
#[derive(Deserialize)]
pub struct CreateCabinetAppointmentBody {
    /// Dossier patient dans le cabinet (FK `patient.id`).
    pub patient_id: Uuid,
    /// Créneau à réserver (`availability_slot.id`). Obligatoire pour l'instant.
    pub slot_id: Uuid,
    /// Note administrative optionnelle (motif visible secrétariat+).
    pub notes: Option<String>,
}

/// Réponse de `POST /v1/cabinet/appointments`.
#[derive(Serialize)]
pub struct CreateCabinetAppointmentResponse {
    pub appointment_id: Uuid,
    pub status: String,
}

/// `POST /v1/cabinet/appointments` — création d'un RDV par le secrétariat.
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT, jamais du body.
/// RLS scopé via `app.current_cabinet_id` : vérifie que le patient appartient
/// au cabinet (404 sinon). Le créneau est résolu depuis `availability_slot`.
/// Contrainte d'exclusion DB (23P01) → `409 slot_taken`.
/// Statut initial : `"requested"`.
pub async fn create_cabinet_appointment(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateCabinetAppointmentBody>,
) -> Result<(StatusCode, Json<CreateCabinetAppointmentResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS + filtre explicite).
    let patient_row = sqlx::query(
        "SELECT id FROM patient \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(body.patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let patient_id: Uuid = patient_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Résout le créneau pour starts_at / ends_at / practitioner_id.
    let slot_row = sqlx::query(
        "SELECT starts_at, ends_at, practitioner_id \
         FROM availability_slot \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(body.slot_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let starts_at: chrono::DateTime<chrono::Utc> = slot_row
        .try_get("starts_at")
        .map_err(|_| AppError::Internal)?;
    let ends_at: chrono::DateTime<chrono::Utc> = slot_row
        .try_get("ends_at")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = slot_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    // INSERT — 23P01 (appointment_no_overlap) → 409 slot_taken.
    let result = sqlx::query(
        "INSERT INTO appointment \
         (cabinet_id, patient_id, practitioner_id, slot_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, $5, $6, 'requested', $7) \
         RETURNING id, status",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(body.slot_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(body.notes.as_deref())
    .fetch_one(&mut *tx)
    .await;

    let row = match result {
        Ok(r) => r,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    // Consomme le créneau pour qu'il disparaisse de la recherche de dispo
    // (`/v1/search/slots` filtre `status = 'open'`).
    sqlx::query(
        "UPDATE availability_slot SET status = 'booked', updated_at = now() \
         WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(body.slot_id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'create_appointment', 'appointment', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(appointment_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        role = %claims.role,
        appointment_id = %appointment_id,
        "cabinet appointment created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateCabinetAppointmentResponse {
            appointment_id,
            status,
        }),
    ))
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

    // R10 : clause supplémentaire pour les secrétaires — filtre sur les praticiens du secrétariat.
    // Le placeholder du secrétariat dépend du nombre de binds posés par la branche
    // appelante ; la colonne du RDV doit être qualifiée (`appointment.`), sinon
    // `practitioner_id` se résout sur `pr` et la clause est une tautologie.
    let mk_sec_filter = |n: usize| -> String {
        if claims.role == "secretary" {
            format!(
                " AND EXISTS ( \
                     SELECT 1 FROM provider pr \
                     JOIN provider_secretariat ps ON ps.provider_id = pr.id \
                     WHERE pr.practitioner_id = appointment.practitioner_id \
                       AND ps.secretariat_id = ${n} \
                       AND ps.active = true \
                 )"
            )
        } else {
            String::new()
        }
    };
    // Secrétaire sans secrétariat actif : aucun résultat.
    if claims.role == "secretary" && claims.secretariat_id.is_none() {
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(CabinetAppointmentsResponse { data: vec![] }));
    }
    let sid = claims.secretariat_id;

    // Construit la requête dynamiquement selon les filtres optionnels.
    let rows = match (&params.status, &date_filter) {
        (Some(status), Some((ds, de))) => {
            let sql = format!(
                "SELECT id, practitioner_id, patient_id, starts_at, ends_at, status, motif \
                 FROM appointment \
                 WHERE deleted_at IS NULL \
                   AND cabinet_id = $1 \
                   AND status = $2 \
                   AND starts_at >= $3 AND starts_at < $4{} \
                 ORDER BY starts_at",
                mk_sec_filter(5),
            );
            let q = sqlx::query(&sql)
                .bind(claims.cabinet_id)
                .bind(status)
                .bind(ds)
                .bind(de);
            if let Some(s) = sid { q.bind(s) } else { q }
                .fetch_all(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
        }

        (Some(status), None) => {
            let sql = format!(
                "SELECT id, practitioner_id, patient_id, starts_at, ends_at, status, motif \
                 FROM appointment \
                 WHERE deleted_at IS NULL \
                   AND cabinet_id = $1 \
                   AND status = $2{} \
                 ORDER BY starts_at",
                mk_sec_filter(3),
            );
            let q = sqlx::query(&sql).bind(claims.cabinet_id).bind(status);
            if let Some(s) = sid { q.bind(s) } else { q }
                .fetch_all(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
        }

        (None, Some((ds, de))) => {
            let sql = format!(
                "SELECT id, practitioner_id, patient_id, starts_at, ends_at, status, motif \
                 FROM appointment \
                 WHERE deleted_at IS NULL \
                   AND cabinet_id = $1 \
                   AND starts_at >= $2 AND starts_at < $3{} \
                 ORDER BY starts_at",
                mk_sec_filter(4),
            );
            let q = sqlx::query(&sql).bind(claims.cabinet_id).bind(ds).bind(de);
            if let Some(s) = sid { q.bind(s) } else { q }
                .fetch_all(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
        }

        (None, None) => {
            let sql = format!(
                "SELECT id, practitioner_id, patient_id, starts_at, ends_at, status, motif \
                 FROM appointment \
                 WHERE deleted_at IS NULL \
                   AND cabinet_id = $1{} \
                 ORDER BY starts_at",
                mk_sec_filter(2),
            );
            let q = sqlx::query(&sql).bind(claims.cabinet_id);
            if let Some(s) = sid { q.bind(s) } else { q }
                .fetch_all(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
        }
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

// ── Start consultation ────────────────────────────────────────────────────────

/// Réponse de `POST /v1/cabinet/appointments/:id/start`.
#[derive(Serialize)]
pub struct StartConsultationResponse {
    pub appointment_id: Uuid,
    pub status: String,
    pub started_at: String,
}

/// `POST /v1/cabinet/appointments/:id/start` — démarre une séance de consultation au fauteuil.
///
/// Token pro praticien requis (secretary → 403, R.4127-72 §07 §4.1).
/// `cabinet_id` extrait du JWT, jamais du body. RLS via `app.current_cabinet_id`.
/// Transition d'état : `confirmed → in_progress` ; toute autre transition → `409 invalid_status`.
/// Pose `started_at = now()` sur l'appointment. Audité (`start_consultation`, `appointment`).
pub async fn start_consultation(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<StartConsultationResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, status, practitioner_id FROM appointment \
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
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    if status != "confirmed" && status != "checked_in" {
        return Err(AppError::InvalidStatus);
    }

    let updated = sqlx::query(
        "UPDATE appointment \
         SET status = 'in_progress', started_at = now(), updated_at = now() \
         WHERE id = $1 \
         RETURNING started_at",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let started_at: chrono::DateTime<chrono::Utc> = updated
        .try_get("started_at")
        .map_err(|_| AppError::Internal)?;

    // Crée la séance de consultation liée à ce rendez-vous.
    sqlx::query(
        "INSERT INTO consultation_session \
         (cabinet_id, appointment_id, practitioner_id) \
         VALUES ($1, $2, $3)",
    )
    .bind(claims.cabinet_id)
    .bind(id)
    .bind(practitioner_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'practitioner', 'start_consultation', 'appointment', $3)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        appointment_id = %id,
        "consultation started"
    );

    Ok(Json(StartConsultationResponse {
        appointment_id: id,
        status: "in_progress".to_string(),
        started_at: started_at.to_rfc3339(),
    }))
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

// ── BO slot management (§13) ──────────────────────────────────────────────────

/// Réponse d'un créneau cabinet.
#[derive(Serialize)]
pub struct CabinetSlotResponse {
    pub id: Uuid,
    pub practitioner_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub status: String,
    pub online_booking: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub motif: Option<String>,
}

/// Corps de `POST /v1/cabinet/slots`.
#[derive(Deserialize)]
pub struct CreateSlotBody {
    pub practitioner_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub status: Option<String>,
    pub motif: Option<String>,
}

/// `POST /v1/cabinet/slots` — ouvre ou bloque un créneau cabinet (§13).
///
/// Statuts autorisés : `open` (par défaut) ou `blocked`.
/// Contrainte d'exclusion praticien (23P01) → 409 slot_taken.
/// `cabinet_id` extrait du JWT. RBAC : secretary+.
pub async fn create_cabinet_slot(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateSlotBody>,
) -> Result<(StatusCode, Json<CabinetSlotResponse>), AppError> {
    let starts_at = body
        .starts_at
        .parse::<chrono::DateTime<chrono::Utc>>()
        .map_err(|_| AppError::ValidationError)?;
    let ends_at = body
        .ends_at
        .parse::<chrono::DateTime<chrono::Utc>>()
        .map_err(|_| AppError::ValidationError)?;
    if ends_at <= starts_at {
        return Err(AppError::ValidationError);
    }

    let status = body.status.as_deref().unwrap_or("open").to_string();
    if status != "open" && status != "blocked" {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le praticien appartient au cabinet (RLS garantit l'isolation).
    let pract = sqlx::query("SELECT id FROM practitioner WHERE id = $1 AND cabinet_id = $2")
        .bind(body.practitioner_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;
    let practitioner_id: Uuid = pract.try_get("id").map_err(|_| AppError::Internal)?;

    // Trouve le provider associé au praticien pour le lien marketplace.
    let maybe_provider = sqlx::query(
        "SELECT id FROM provider WHERE practitioner_id = $1 AND cabinet_id = $2 LIMIT 1",
    )
    .bind(practitioner_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let provider_id: Option<Uuid> = if let Some(row) = maybe_provider {
        Some(row.try_get("id").map_err(|_| AppError::Internal)?)
    } else {
        None
    };

    let slot_id = Uuid::new_v4();

    let result = sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status, motif, online_booking) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false) \
         RETURNING id, practitioner_id, starts_at, ends_at, status, motif, online_booking",
    )
    .bind(slot_id)
    .bind(provider_id)
    .bind(claims.cabinet_id)
    .bind(practitioner_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(&status)
    .bind(body.motif.as_deref())
    .fetch_one(&mut *tx)
    .await;

    let row = match result {
        Ok(r) => r,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let pid: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let sa: chrono::DateTime<chrono::Utc> =
        row.try_get("starts_at").map_err(|_| AppError::Internal)?;
    let ea: chrono::DateTime<chrono::Utc> =
        row.try_get("ends_at").map_err(|_| AppError::Internal)?;
    let st: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let motif: Option<String> = row.try_get("motif").map_err(|_| AppError::Internal)?;
    let online_booking: bool = row
        .try_get("online_booking")
        .map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        slot_id = %id,
        "cabinet slot created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CabinetSlotResponse {
            id,
            practitioner_id: pid,
            starts_at: sa.to_rfc3339(),
            ends_at: ea.to_rfc3339(),
            status: st,
            online_booking,
            motif,
        }),
    ))
}

/// Corps de `PATCH /v1/cabinet/slots/:id`.
#[derive(Deserialize)]
pub struct PatchSlotBody {
    pub starts_at: Option<String>,
    pub ends_at: Option<String>,
    pub status: Option<String>,
    pub motif: Option<String>,
}

/// `PATCH /v1/cabinet/slots/:id` — édite un créneau cabinet (§13).
///
/// Un créneau `booked` ne peut pas être modifié (409 invalid_status).
/// Conflit d'exclusion (23P01) → 409 slot_taken.
/// RBAC : secretary+. `cabinet_id` extrait du JWT.
pub async fn patch_cabinet_slot(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(slot_id): Path<Uuid>,
    Json(body): Json<PatchSlotBody>,
) -> Result<Json<CabinetSlotResponse>, AppError> {
    let new_starts_at: Option<chrono::DateTime<chrono::Utc>> = body
        .starts_at
        .as_deref()
        .map(|s| s.parse::<chrono::DateTime<chrono::Utc>>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;
    let new_ends_at: Option<chrono::DateTime<chrono::Utc>> = body
        .ends_at
        .as_deref()
        .map(|s| s.parse::<chrono::DateTime<chrono::Utc>>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    if let (Some(sa), Some(ea)) = (new_starts_at, new_ends_at) {
        if ea <= sa {
            return Err(AppError::ValidationError);
        }
    }

    if let Some(s) = &body.status {
        if s != "open" && s != "blocked" {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing = sqlx::query(
        "SELECT id, status FROM availability_slot \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(slot_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let current_status: String = existing.try_get("status").map_err(|_| AppError::Internal)?;
    if current_status == "booked" {
        return Err(AppError::InvalidStatus);
    }

    let result = sqlx::query(
        "UPDATE availability_slot \
         SET starts_at     = COALESCE($1, starts_at), \
             ends_at       = COALESCE($2, ends_at), \
             status        = COALESCE($3, status), \
             motif         = COALESCE($4, motif), \
             updated_at    = now() \
         WHERE id = $5 \
         RETURNING id, practitioner_id, starts_at, ends_at, status, motif, online_booking",
    )
    .bind(new_starts_at)
    .bind(new_ends_at)
    .bind(body.status.as_deref())
    .bind(body.motif.as_deref())
    .bind(slot_id)
    .fetch_one(&mut *tx)
    .await;

    let row = match result {
        Ok(r) => r,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let sa: chrono::DateTime<chrono::Utc> =
        row.try_get("starts_at").map_err(|_| AppError::Internal)?;
    let ea: chrono::DateTime<chrono::Utc> =
        row.try_get("ends_at").map_err(|_| AppError::Internal)?;
    let st: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let motif: Option<String> = row.try_get("motif").map_err(|_| AppError::Internal)?;
    let online_booking: bool = row
        .try_get("online_booking")
        .map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        slot_id = %id,
        "cabinet slot patched"
    );

    Ok(Json(CabinetSlotResponse {
        id,
        practitioner_id,
        starts_at: sa.to_rfc3339(),
        ends_at: ea.to_rfc3339(),
        status: st,
        online_booking,
        motif,
    }))
}

/// `DELETE /v1/cabinet/slots/:id` — supprime un créneau cabinet (§13).
///
/// Un créneau `booked` ne peut pas être supprimé (409 invalid_status).
/// Soft-delete via `deleted_at`. RBAC : secretary+. `cabinet_id` extrait du JWT.
pub async fn delete_cabinet_slot(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(slot_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, status FROM availability_slot \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(slot_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let current_status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    if current_status == "booked" {
        return Err(AppError::InvalidStatus);
    }

    sqlx::query(
        "UPDATE availability_slot SET deleted_at = now(), updated_at = now() WHERE id = $1",
    )
    .bind(slot_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        slot_id = %slot_id,
        "cabinet slot deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}

/// Réponse de `PUT /v1/cabinet/slots/:id/online`.
#[derive(Serialize)]
pub struct SlotOnlineResponse {
    pub id: Uuid,
    pub online_booking: bool,
}

/// `PUT /v1/cabinet/slots/:id/online` — bascule le flag `online_booking` (§13).
///
/// Corps : `{ "online_booking": true|false }`. RBAC : secretary+.
/// `cabinet_id` extrait du JWT.
#[derive(Deserialize)]
pub struct PutSlotOnlineBody {
    pub online_booking: bool,
}

pub async fn put_cabinet_slot_online(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(slot_id): Path<Uuid>,
    Json(body): Json<PutSlotOnlineBody>,
) -> Result<Json<SlotOnlineResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "UPDATE availability_slot \
         SET online_booking = $1, updated_at = now() \
         WHERE id = $2 AND cabinet_id = $3 AND deleted_at IS NULL \
         RETURNING id, online_booking",
    )
    .bind(body.online_booking)
    .bind(slot_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let online_booking: bool = row
        .try_get("online_booking")
        .map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        slot_id = %id,
        online_booking = %online_booking,
        "cabinet slot online flag toggled"
    );

    Ok(Json(SlotOnlineResponse { id, online_booking }))
}
