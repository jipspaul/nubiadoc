//! Handler `GET /v1/cabinet/agenda` — agenda du cabinet pour le secrétariat et le praticien.

use std::sync::Arc;

use axum::{
    extract::{rejection::JsonRejection, Extension, Path, Query, State},
    http::StatusCode,
    Json,
};
use chrono::TimeZone;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims, ProSecretaryPlusClaims},
    notify, AppState,
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
    /// Nom du patient (donnée administrative, visible secrétariat+) —
    /// sans lui l'agenda titrait par le motif technique (#3371).
    pub patient_name: Option<String>,
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
                    "SELECT a.id, a.practitioner_id, a.starts_at, a.ends_at, a.status, a.motif, \
                            NULLIF(TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')), '') AS patient_name \
                     FROM appointment a \
                     LEFT JOIN patient p ON p.id = a.patient_id AND p.deleted_at IS NULL \
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
                "SELECT a.id, a.practitioner_id, a.starts_at, a.ends_at, a.status, a.motif, \
                        NULLIF(TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')), '') AS patient_name \
                 FROM appointment a \
                 LEFT JOIN patient p ON p.id = a.patient_id AND p.deleted_at IS NULL \
                 WHERE a.deleted_at IS NULL \
                   AND a.starts_at >= $1 AND a.starts_at < $2 \
                   AND a.practitioner_id = $3 \
                 ORDER BY a.starts_at",
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
                "SELECT a.id, a.practitioner_id, a.starts_at, a.ends_at, a.status, a.motif, \
                        NULLIF(TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')), '') AS patient_name \
                 FROM appointment a \
                 LEFT JOIN patient p ON p.id = a.patient_id AND p.deleted_at IS NULL \
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
            "SELECT a.id, a.practitioner_id, a.starts_at, a.ends_at, a.status, a.motif, \
                    NULLIF(TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')), '') AS patient_name \
             FROM appointment a \
             LEFT JOIN patient p ON p.id = a.patient_id AND p.deleted_at IS NULL \
             WHERE a.deleted_at IS NULL \
               AND a.starts_at >= $1 AND a.starts_at < $2 \
             ORDER BY a.starts_at",
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
            let patient_name: Option<String> = row
                .try_get("patient_name")
                .map_err(|_| AppError::Internal)?;
            Ok(AgendaSlot {
                id,
                practitioner_id,
                starts_at: starts_at.to_rfc3339(),
                ends_at: ends_at.to_rfc3339(),
                status,
                motif_admin,
                patient_name,
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
    Extension(hub): Extension<Arc<crate::realtime::WsHub>>,
    claims: ProPractitionerClaims,
) -> Result<Json<CallNextResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Un praticien n'appelle que ses propres patients — l'admin voit tout le cabinet.
    let practitioner_filter: Option<Uuid> = if claims.role == "practitioner" {
        let prac_row =
            sqlx::query("SELECT id FROM practitioner WHERE cabinet_id = $1 AND user_id = $2")
                .bind(claims.cabinet_id)
                .bind(claims.sub)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
                .ok_or(AppError::Forbidden)?;
        Some(prac_row.try_get("id").map_err(|_| AppError::Internal)?)
    } else {
        None
    };

    // Prochain rendez-vous checked_in (FIFO sur checkin_at).
    // FOR UPDATE SKIP LOCKED évite les doubles appels concurrents.
    let maybe_apt = if let Some(practitioner_id) = practitioner_filter {
        sqlx::query(
            "SELECT id, patient_id FROM appointment \
             WHERE status = 'checked_in' AND deleted_at IS NULL AND practitioner_id = $1 \
               AND starts_at >= date_trunc('day', now()) \
               AND starts_at < date_trunc('day', now()) + interval '1 day' \
             ORDER BY checkin_at ASC NULLS LAST, starts_at ASC \
             LIMIT 1 \
             FOR UPDATE SKIP LOCKED",
        )
        .bind(practitioner_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    } else {
        sqlx::query(
            "SELECT id, patient_id FROM appointment \
             WHERE status = 'checked_in' AND deleted_at IS NULL \
               AND starts_at >= date_trunc('day', now()) \
               AND starts_at < date_trunc('day', now()) + interval '1 day' \
             ORDER BY checkin_at ASC NULLS LAST, starts_at ASC \
             LIMIT 1 \
             FOR UPDATE SKIP LOCKED",
        )
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    };

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
        "SELECT first_name, last_name, app_user_id, patient_account_id FROM patient WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (patient_display_name, patient_app_user_id, patient_account_id) = if let Some(row) = pat_row
    {
        let first: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
        let last: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
        let uid: Option<Uuid> = row.try_get("app_user_id").map_err(|_| AppError::Internal)?;
        let account_id: Option<Uuid> = row
            .try_get("patient_account_id")
            .map_err(|_| AppError::Internal)?;
        (format!("{first} {last}"), uid, account_id)
    } else {
        (String::new(), None, None)
    };

    // Notification in-app au patient (via app_user_id direct, sinon via le
    // compte patient rattaché — cas des patients liés par patient_account_id, #3480).
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
    } else if let Some(account_id) = patient_account_id {
        notify::notify_patient_account(
            &mut tx,
            account_id,
            "waiting_room_called",
            "C'est votre tour",
            serde_json::json!({ "appointment_id": appointment_id }),
        )
        .await?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Temps réel : « c'est votre tour » vers le patient abonné + salle d'attente — #3238.
    let queue_channel = format!("patient_queue:{appointment_id}");
    hub.publish_named(
        &queue_channel,
        serde_json::json!({
            "channel": queue_channel,
            "event": "your_turn",
            "data": { "appointment_id": appointment_id }
        })
        .to_string(),
    );
    hub.publish(
        claims.cabinet_id,
        serde_json::json!({
            "channel": "waiting_room",
            "event": "queue_updated",
            "data": { "appointment_id": appointment_id, "status": "in_progress" }
        })
        .to_string(),
    );

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

/// Un poste dans la file d'attente temps-réel (patients checked_in ou in_consultation aujourd'hui).
#[derive(Serialize)]
pub struct WaitingRoomEntry {
    pub appointment_id: Uuid,
    /// Nom complet (pro/admin) ou initiales (secrétariat) — cloisonnement clinique RBAC.
    pub patient_name_initials: String,
    pub checkin_at: Option<String>,
    pub wait_minutes: i64,
    pub status: String,
}

/// Réponse de `GET /v1/cabinet/waiting-room`.
#[derive(Serialize)]
pub struct WaitingRoomResponse {
    pub data: Vec<WaitingRoomEntry>,
}

/// `GET /v1/cabinet/waiting-room` — file d'attente temps-réel du cabinet (§E.2).
///
/// Retourne les RDV du jour `checked_in` (arrivé, en attente) et `in_progress`
/// (consultation en cours, exposé comme `in_consultation`), triés FIFO.
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT. RLS via `app.current_cabinet_id`.
/// Cloisonnement clinique : secrétariat reçoit initiales du patient, pro reçoit nom complet.
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
                "SELECT a.id, a.status, a.checkin_at, \
                        p.first_name, p.last_name, \
                        GREATEST(0, EXTRACT(EPOCH FROM (now() - a.checkin_at))::bigint / 60) AS wait_minutes \
                 FROM appointment a \
                 LEFT JOIN patient p ON p.id = a.patient_id AND p.deleted_at IS NULL \
                 WHERE a.deleted_at IS NULL \
                   AND a.checkin_at IS NOT NULL \
                   AND a.status IN ('checked_in', 'in_progress') \
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
    } else if claims.role == "practitioner" {
        // Un praticien ne voit que sa propre file d'attente, pas celle du cabinet entier.
        sqlx::query(
            "SELECT a.id, a.status, a.checkin_at, \
                    p.first_name, p.last_name, \
                    GREATEST(0, EXTRACT(EPOCH FROM (now() - a.checkin_at))::bigint / 60) AS wait_minutes \
             FROM appointment a \
             LEFT JOIN patient p ON p.id = a.patient_id AND p.deleted_at IS NULL \
             JOIN practitioner pr ON pr.id = a.practitioner_id \
             WHERE a.deleted_at IS NULL \
               AND a.checkin_at IS NOT NULL \
               AND a.status IN ('checked_in', 'in_progress') \
               AND a.starts_at >= date_trunc('day', now()) \
               AND a.starts_at < date_trunc('day', now()) + interval '1 day' \
               AND pr.cabinet_id = $1 \
               AND pr.user_id = $2 \
             ORDER BY a.checkin_at ASC NULLS LAST, a.starts_at ASC",
        )
        .bind(claims.cabinet_id)
        .bind(claims.sub)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    } else {
        sqlx::query(
            "SELECT a.id, a.status, a.checkin_at, \
                    p.first_name, p.last_name, \
                    GREATEST(0, EXTRACT(EPOCH FROM (now() - a.checkin_at))::bigint / 60) AS wait_minutes \
             FROM appointment a \
             LEFT JOIN patient p ON p.id = a.patient_id AND p.deleted_at IS NULL \
             WHERE a.deleted_at IS NULL \
               AND a.checkin_at IS NOT NULL \
               AND a.status IN ('checked_in', 'in_progress') \
               AND a.starts_at >= date_trunc('day', now()) \
               AND a.starts_at < date_trunc('day', now()) + interval '1 day' \
             ORDER BY a.checkin_at ASC NULLS LAST, a.starts_at ASC",
        )
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let is_secretary = claims.role == "secretary";

    let data = rows
        .into_iter()
        .map(|row| -> Result<WaitingRoomEntry, AppError> {
            let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let db_status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            let checkin_at: Option<chrono::DateTime<chrono::Utc>> =
                row.try_get("checkin_at").map_err(|_| AppError::Internal)?;
            let wait_minutes: i64 = row
                .try_get("wait_minutes")
                .map_err(|_| AppError::Internal)?;
            let first: Option<String> =
                row.try_get("first_name").map_err(|_| AppError::Internal)?;
            let last: Option<String> = row.try_get("last_name").map_err(|_| AppError::Internal)?;

            let patient_name_initials = match (first.as_deref(), last.as_deref()) {
                (Some(f), Some(l)) if is_secretary => format!(
                    "{}{}",
                    f.chars().next().unwrap_or('?'),
                    l.chars().next().unwrap_or('?')
                ),
                (Some(f), Some(l)) => format!("{f} {l}"),
                _ => String::new(),
            };

            let status = if db_status == "in_progress" {
                "in_consultation".to_string()
            } else {
                db_status
            };

            Ok(WaitingRoomEntry {
                appointment_id,
                patient_name_initials,
                checkin_at: checkin_at.map(|dt| dt.to_rfc3339()),
                wait_minutes,
                status,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        count = data.len(),
        "waiting room queried"
    );

    Ok(Json(WaitingRoomResponse { data }))
}

// ── Waiting list (liste d'attente) ────────────────────────────────────────────

/// Entrée de liste d'attente (waiting_list_entry) exposée au secrétariat+.
#[derive(Serialize)]
pub struct WaitingListItem {
    pub id: Uuid,
    pub patient_id: Uuid,
    /// Nom du patient (non-clinique) — sans lui la liste est inexploitable
    /// par la secrétaire (#3364). Vide si le patient a été supprimé.
    pub patient_name: String,
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
        "SELECT w.id, w.patient_id, w.desired_window, w.score::float8 AS score, \
                w.status, w.created_at, \
                COALESCE(TRIM(p.first_name || ' ' || p.last_name), '') AS patient_name \
         FROM waiting_list_entry w \
         LEFT JOIN patient p ON p.id = w.patient_id AND p.deleted_at IS NULL \
         WHERE w.status = 'active' \
         ORDER BY w.score DESC, w.created_at ASC",
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
            let patient_name: String = row
                .try_get("patient_name")
                .map_err(|_| AppError::Internal)?;
            Ok(WaitingListItem {
                id,
                patient_id,
                patient_name,
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
/// Notifie réellement le patient (via `app_user_id` direct ou `patient_account_id`,
/// même mécanisme que `call_next`, #3480) avant de passer le statut → `fulfilled`.
/// `notified` dans la réponse reflète l'envoi effectif (`false` si le patient
/// n'a aucun compte applicatif rattaché — l'entrée reste tout de même `fulfilled`
/// côté planning, le créneau étant physiquement proposé par le secrétariat).
/// RBAC : `secretary+`. `cabinet_id` extrait du JWT.
pub async fn offer_waiting_list_slot(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    axum::extract::Path(entry_id): axum::extract::Path<Uuid>,
    Json(body): Json<OfferSlotBody>,
) -> Result<Json<OfferSlotResponse>, AppError> {
    // Valide le format de la date proposée, et qu'elle est bien dans le futur
    // (même règle que la création de RDV, `appointments.rs::create_appointment`).
    let proposed_at = body
        .proposed_at
        .parse::<chrono::DateTime<chrono::Utc>>()
        .map_err(|_| AppError::ValidationError)?;
    if proposed_at <= chrono::Utc::now() + chrono::Duration::minutes(5) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie existence + statut actif (RLS garantit l'appartenance au cabinet).
    let row = sqlx::query("SELECT id, patient_id, status FROM waiting_list_entry WHERE id = $1")
        .bind(entry_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    if status != "active" {
        return Err(AppError::InvalidStatus);
    }
    let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;

    let pat_row = sqlx::query(
        "SELECT app_user_id, patient_account_id FROM patient WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (patient_app_user_id, patient_account_id) = if let Some(row) = pat_row {
        let uid: Option<Uuid> = row.try_get("app_user_id").map_err(|_| AppError::Internal)?;
        let account_id: Option<Uuid> = row
            .try_get("patient_account_id")
            .map_err(|_| AppError::Internal)?;
        (uid, account_id)
    } else {
        (None, None)
    };

    let notify_data = serde_json::json!({
        "waiting_list_entry_id": entry_id,
        "proposed_at": body.proposed_at,
    });
    let notified = if let Some(uid) = patient_app_user_id {
        notify::notify_user(
            &mut tx,
            uid,
            "waiting_list_slot_offered",
            "Un créneau vous est proposé",
            notify_data,
        )
        .await?;
        true
    } else if let Some(account_id) = patient_account_id {
        notify::notify_patient_account(
            &mut tx,
            account_id,
            "waiting_list_slot_offered",
            "Un créneau vous est proposé",
            notify_data,
        )
        .await?
        .is_some()
    } else {
        false
    };

    sqlx::query("UPDATE waiting_list_entry SET status = 'fulfilled' WHERE id = $1")
        .bind(entry_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        entry_id = %entry_id,
        notified,
        "waiting list: slot offered"
    );

    Ok(Json(OfferSlotResponse {
        waiting_list_entry_id: entry_id,
        notified,
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
    Extension(hub): Extension<Arc<crate::realtime::WsHub>>,
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
    // status = 'open' : un créneau blocked (indispo praticien) ou held (hold
    // patient actif) ne doit pas être réservable par un walk-in cabinet, au
    // même titre que claim_and_hold_slot() côté patient.
    let slot_row = sqlx::query(
        "SELECT starts_at, ends_at, practitioner_id \
         FROM availability_slot \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL AND status = 'open'",
    )
    .bind(body.slot_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::SlotTaken)?;

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

    hub.publish(
        claims.cabinet_id,
        serde_json::json!({
            "channel": "waiting_room",
            "event": "queue_updated",
            "data": { "appointment_id": appointment_id, "status": status }
        })
        .to_string(),
    );

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
    /// Horodatage de la demande de rappel patient (`POST .../callback-request`), si présente.
    pub callback_requested_at: Option<String>,
    pub patient_name: Option<String>,
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
    // appelante ; la colonne du RDV doit être qualifiée (`a.`), sinon
    // `practitioner_id` se résout sur `pr` et la clause est une tautologie.
    let mk_sec_filter = |n: usize| -> String {
        if claims.role == "secretary" {
            format!(
                " AND EXISTS ( \
                     SELECT 1 FROM provider pr \
                     JOIN provider_secretariat ps ON ps.provider_id = pr.id \
                     WHERE pr.practitioner_id = a.practitioner_id \
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
    // Le bind du secrétariat ne doit exister QUE pour un secrétaire : `mk_sec_filter`
    // ne pose son placeholder (`$n`) que dans ce cas. Un admin/manager/praticien dont
    // le JWT porte un `secretariat_id` (cf. contexte multi-rôle) ajouterait sinon un
    // paramètre lié sans placeholder correspondant → « bind message supplies N
    // parameters » côté Postgres → 500 (#3405). On neutralise donc `sid` hors secrétaire.
    let sid = if claims.role == "secretary" {
        claims.secretariat_id
    } else {
        None
    };

    // Construit la requête dynamiquement selon les filtres optionnels.
    let rows = match (&params.status, &date_filter) {
        (Some(status), Some((ds, de))) => {
            let sql = format!(
                "SELECT a.id, a.practitioner_id, a.patient_id, a.starts_at, a.ends_at, a.status, a.motif, a.callback_requested_at, \
                        NULLIF(TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')), '') AS patient_name \
                 FROM appointment a \
                 LEFT JOIN patient p ON p.id = a.patient_id AND p.deleted_at IS NULL \
                 WHERE a.deleted_at IS NULL \
                   AND a.cabinet_id = $1 \
                   AND a.status = $2 \
                   AND a.starts_at >= $3 AND a.starts_at < $4{} \
                 ORDER BY a.starts_at",
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
                "SELECT a.id, a.practitioner_id, a.patient_id, a.starts_at, a.ends_at, a.status, a.motif, a.callback_requested_at, \
                        NULLIF(TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')), '') AS patient_name \
                 FROM appointment a \
                 LEFT JOIN patient p ON p.id = a.patient_id AND p.deleted_at IS NULL \
                 WHERE a.deleted_at IS NULL \
                   AND a.cabinet_id = $1 \
                   AND a.status = $2{} \
                 ORDER BY a.starts_at",
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
                "SELECT a.id, a.practitioner_id, a.patient_id, a.starts_at, a.ends_at, a.status, a.motif, a.callback_requested_at, \
                        NULLIF(TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')), '') AS patient_name \
                 FROM appointment a \
                 LEFT JOIN patient p ON p.id = a.patient_id AND p.deleted_at IS NULL \
                 WHERE a.deleted_at IS NULL \
                   AND a.cabinet_id = $1 \
                   AND a.starts_at >= $2 AND a.starts_at < $3{} \
                 ORDER BY a.starts_at",
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
                "SELECT a.id, a.practitioner_id, a.patient_id, a.starts_at, a.ends_at, a.status, a.motif, a.callback_requested_at, \
                        NULLIF(TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')), '') AS patient_name \
                 FROM appointment a \
                 LEFT JOIN patient p ON p.id = a.patient_id AND p.deleted_at IS NULL \
                 WHERE a.deleted_at IS NULL \
                   AND a.cabinet_id = $1{} \
                 ORDER BY a.starts_at",
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
        let callback_requested_at: Option<chrono::DateTime<chrono::Utc>> = row
            .try_get("callback_requested_at")
            .map_err(|_| AppError::Internal)?;
        let patient_name: Option<String> = row
            .try_get("patient_name")
            .map_err(|_| AppError::Internal)?;
        data.push(CabinetAppointmentItem {
            id,
            practitioner_id,
            patient_id,
            starts_at: starts_at.to_rfc3339(),
            ends_at: ends_at.to_rfc3339(),
            status,
            motif_admin,
            callback_requested_at: callback_requested_at.map(|ts| ts.to_rfc3339()),
            patient_name,
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
    Extension(hub): Extension<Arc<crate::realtime::WsHub>>,
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

    hub.publish(
        claims.cabinet_id,
        serde_json::json!({
            "channel": "waiting_room",
            "event": "queue_updated",
            "data": { "appointment_id": id, "status": "confirmed" }
        })
        .to_string(),
    );

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
    /// Transition de clôture explicite — seule valeur acceptée : `no_show`,
    /// pour sortir un RDV `checked_in` (jour passé ou non) de la file (#3670).
    pub status: Option<String>,
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
    pub consultation_id: Uuid,
    pub status: String,
    pub started_at: String,
}

/// `POST /v1/cabinet/appointments/:id/start` — démarre une séance de consultation au fauteuil.
///
/// Token pro praticien requis (secretary → 403, R.4127-72 §07 §4.1).
/// `cabinet_id` extrait du JWT, jamais du body. RLS via `app.current_cabinet_id`.
/// Transition d'état : `confirmed|checked_in → in_progress`. Accepte aussi `in_progress`
/// sans `consultation_session` existante (RDV appelé via call-next, #3477) ; si une
/// session existe déjà pour ce RDV → `409 invalid_status` (double démarrage).
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

    if status != "confirmed" && status != "checked_in" && status != "in_progress" {
        return Err(AppError::InvalidStatus);
    }

    // `in_progress` sans consultation_session = patient appelé via call-next mais pas
    // encore ouvert (#3477) : on laisse passer. Si une session existe déjà, le RDV a
    // déjà été démarré → 409 pour éviter une double séance.
    if status == "in_progress" {
        let existing_session =
            sqlx::query("SELECT id FROM consultation_session WHERE appointment_id = $1")
                .bind(id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;

        if existing_session.is_some() {
            return Err(AppError::InvalidStatus);
        }
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
    let session_row = sqlx::query(
        "INSERT INTO consultation_session \
         (cabinet_id, appointment_id, practitioner_id) \
         VALUES ($1, $2, $3) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(id)
    .bind(practitioner_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let consultation_id: Uuid = session_row.try_get("id").map_err(|_| AppError::Internal)?;

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
        consultation_id = %consultation_id,
        "consultation started"
    );

    Ok(Json(StartConsultationResponse {
        appointment_id: id,
        consultation_id,
        status: "in_progress".to_string(),
        started_at: started_at.to_rfc3339(),
    }))
}

/// `PATCH /v1/cabinet/appointments/:id` — déplace ou édite un RDV côté cabinet.
///
/// Token pro requis (secretary+). `cabinet_id` extrait du JWT. 404 si le RDV
/// n'appartient pas au cabinet (RLS). Statut valide pour modification :
/// `requested` ou `confirmed` → `409 invalid_status` sinon.
/// `status: "no_show"` : clôture cabinet d'un RDV `checked_in` (seule
/// transition acceptée en entrée) → `409 invalid_status` si le RDV n'est pas
/// `checked_in`, `422`/`400 validation_error` si une autre valeur est fournie.
/// Nouveau `starts_at` : doit être dans le futur et correspondre à un
/// `availability_slot` `open` du praticien → `409 slot_unavailable` sinon
/// (même garde que `patch_appointment` côté patient, #3558).
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
        "SELECT id, status, slot_id, practitioner_id FROM appointment \
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
    let slot_id: Option<Uuid> = row.try_get("slot_id").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    // Clôture cabinet d'un `checked_in` (typiquement périmé, d'un jour passé,
    // donc absent de waiting-room/queue) : seule sortie de file possible avant
    // ce correctif était un cul-de-sac (#3670). Même statut cible que le
    // patient sortant lui-même de la file (cancel_appointment, appointments.rs).
    if let Some(target_status) = body.status.as_deref() {
        if target_status != "no_show" {
            return Err(AppError::ValidationError);
        }
        if status != "checked_in" {
            return Err(AppError::InvalidStatus);
        }

        sqlx::query(
            "UPDATE appointment \
             SET status = 'no_show', cancelled_at = now(), \
                 cancel_reason = COALESCE($2, cancel_reason), updated_at = now() \
             WHERE id = $1",
        )
        .bind(id)
        .bind(body.motif.as_deref())
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

        return Ok(Json(PatchCabinetAppointmentResponse {
            appointment_id: id,
            status: "no_show".to_string(),
        }));
    }

    if status != "requested" && status != "confirmed" {
        return Err(AppError::InvalidStatus);
    }

    // Reprogrammation cabinet : même garde que patch_appointment côté patient
    // (#3558) — le nouveau starts_at doit être (a) dans le futur ET (b)
    // correspondre à un availability_slot 'open' du praticien, sinon le RDV
    // se retrouve délié de tout créneau (slot_id NULL) et fantôme dans l'agenda.
    if let Some(new_ts) = new_starts_at {
        if new_ts <= chrono::Utc::now() {
            return Err(AppError::SlotUnavailable);
        }
        let has_open_slot: bool = sqlx::query_scalar(
            "SELECT EXISTS( \
               SELECT 1 FROM availability_slot s \
               JOIN provider p ON p.id = s.provider_id \
               WHERE p.practitioner_id = $1 \
                 AND s.starts_at = $2 \
                 AND s.status = 'open' \
                 AND s.deleted_at IS NULL \
             )",
        )
        .bind(practitioner_id)
        .bind(new_ts)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        if !has_open_slot {
            return Err(AppError::SlotUnavailable);
        }
    }

    // Préserve la durée si starts_at change. 23P01 → slot_taken.
    // Un starts_at différent délie le RDV de son créneau d'origine (le nouvel
    // horaire n'est adossé à aucun availability_slot) : slot_id est remis à
    // NULL pour rester cohérent avec starts_at.
    let result = sqlx::query(
        "UPDATE appointment \
         SET \
           starts_at  = COALESCE($1, starts_at), \
           ends_at    = CASE WHEN $1 IS NOT NULL \
                             THEN $1 + (ends_at - starts_at) \
                             ELSE ends_at END, \
           motif      = COALESCE($2, motif), \
           slot_id    = CASE WHEN $1 IS NOT NULL THEN NULL ELSE slot_id END, \
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

    // Libère l'ancien créneau (comme cancel_appointment) puisqu'il n'est plus occupé.
    if new_starts_at.is_some() {
        if let Some(sid) = slot_id {
            sqlx::query("UPDATE availability_slot SET status = 'open' WHERE id = $1")
                .bind(sid)
                .execute(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
        }
    }

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
    // On accepte le rejet de l'extracteur JSON pour le convertir en `AppError`
    // (corps JSON standard `{"code":"validation_error"}`) : sinon Axum renvoie
    // un 400/422 en texte brut (« Failed to deserialize… ») qui casse le front (#3413).
    body: Result<Json<CreateSlotBody>, JsonRejection>,
) -> Result<(StatusCode, Json<CabinetSlotResponse>), AppError> {
    let Json(body) = body.map_err(|_| AppError::ValidationError)?;
    if claims.role == "practitioner" {
        return Err(AppError::Forbidden);
    }
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

/// Élément de la liste `GET /v1/cabinet/slots` (contrat front `SlotDto`).
#[derive(Serialize)]
pub struct CabinetSlotListItem {
    pub id: Uuid,
    pub cabinet_id: Uuid,
    pub practitioner_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    /// `true` si le créneau est ouvert (statut `open`), `false` sinon.
    pub is_available: bool,
}

/// Query params de `GET /v1/cabinet/slots`.
#[derive(Deserialize)]
pub struct ListSlotsQuery {
    pub from: Option<String>,
    pub to: Option<String>,
    pub practitioner_id: Option<Uuid>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    /// Capté uniquement pour rejeter explicitement `?page` (non supporté ici :
    /// cet endpoint pagine via `limit`/`offset`). Avant #3521 le param était
    /// désérialisé dans le néant et ignoré silencieusement.
    pub page: Option<String>,
}

/// `GET /v1/cabinet/slots` — liste les créneaux réservables du cabinet (§13).
///
/// Token pro requis (secretary, practitioner, admin, manager). `cabinet_id`
/// extrait du JWT, RLS scopée via `app.current_cabinet_id` (fail-closed).
/// Filtres optionnels `from`/`to` (ISO 8601) et `practitioner_id`.
/// `limit` (défaut 200, max 500) et `offset` bornent le résultat (#3516 :
/// sans ça l'endpoint renvoyait tous les créneaux du cabinet, ~1.2 Mo/appel).
pub async fn list_cabinet_slots(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<ListSlotsQuery>,
) -> Result<Json<Vec<CabinetSlotListItem>>, AppError> {
    if params.page.is_some() {
        return Err(AppError::UnsupportedPageParam);
    }
    let from = params
        .from
        .as_deref()
        .and_then(|s| s.parse::<chrono::DateTime<chrono::Utc>>().ok());
    let to = params
        .to
        .as_deref()
        .and_then(|s| s.parse::<chrono::DateTime<chrono::Utc>>().ok());
    let limit: i64 = params.limit.unwrap_or(200).clamp(1, 500);
    let offset: i64 = params.offset.unwrap_or(0).max(0);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, cabinet_id, practitioner_id, starts_at, ends_at, status \
         FROM availability_slot \
         WHERE cabinet_id = $1 \
           AND deleted_at IS NULL \
           AND ($2::timestamptz IS NULL OR starts_at >= $2) \
           AND ($3::timestamptz IS NULL OR starts_at < $3) \
           AND ($4::uuid IS NULL OR practitioner_id = $4) \
         ORDER BY starts_at \
         LIMIT $5 OFFSET $6",
    )
    .bind(claims.cabinet_id)
    .bind(from)
    .bind(to)
    .bind(params.practitioner_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let items = rows
        .into_iter()
        .map(|row| {
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
            let practitioner_id: Uuid = row
                .try_get("practitioner_id")
                .map_err(|_| AppError::Internal)?;
            let starts_at: chrono::DateTime<chrono::Utc> =
                row.try_get("starts_at").map_err(|_| AppError::Internal)?;
            let ends_at: chrono::DateTime<chrono::Utc> =
                row.try_get("ends_at").map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            Ok(CabinetSlotListItem {
                id,
                cabinet_id,
                practitioner_id,
                starts_at: starts_at.to_rfc3339(),
                ends_at: ends_at.to_rfc3339(),
                is_available: status == "open",
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        count = items.len(),
        "cabinet slots listed"
    );

    Ok(Json(items))
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

    sqlx::query(
        "SELECT id FROM availability_slot \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(slot_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let booking_row = sqlx::query(
        "SELECT EXISTS(\
           SELECT 1 FROM appointment \
           WHERE slot_id = $1 \
           AND status NOT IN ('cancelled', 'no_show')\
         )",
    )
    .bind(slot_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let has_booking: bool = booking_row.try_get(0).map_err(|_| AppError::Internal)?;
    if has_booking {
        return Err(AppError::HasBooking);
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
