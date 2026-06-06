//! Handler `GET /v1/cabinet/agenda` — agenda du cabinet pour le secrétariat et le praticien.

use axum::{
    extract::{Query, State},
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
