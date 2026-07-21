//! `POST /v1/cabinet/appointments/series` (#4088) — création atomique d'une
//! série de RDV liés (ortho, parodonto, chirurgie multi-séances), consommant
//! `appointment.recurrence_id`/`recurrence_index` (migration 0173, #4087).
//!
//! Module dédié plutôt qu'ajout à `scheduling.rs` (2506 lignes, déjà bien
//! au-delà du plafond CLAUDE.md de 700) — cf. règle "refactor obligatoire
//! avant tout nouvel ajout".
//!
//! Contrairement à `create_cabinet_appointment` (`scheduling.rs`), pas de
//! résolution via `availability_slot` : les créneaux d'une série sont saisis
//! directement (dates/heures libres, pas nécessairement pré-publiées comme
//! créneaux réservables). Une seule transaction pour toute la série — la
//! moindre violation de `appointment_no_overlap` (23P01) sur N'IMPORTE
//! LEQUEL des créneaux annule l'insertion des autres (rollback implicite au
//! drop de la transaction, jamais commitée).

use axum::{extract::State, http::StatusCode, Json};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{auth::AppError, auth::ProSecretaryPlusClaims, AppState};

/// `starts_at`/`ends_at` en `String` (RFC3339), pas `chrono::DateTime`
/// directement : `chrono` n'a pas la feature `serde` activée dans ce crate
/// (cf. `PatchCabinetAppointmentBody` dans `scheduling.rs`, même pattern).
#[derive(Deserialize)]
pub struct OccurrenceInput {
    pub starts_at: String,
    pub ends_at: String,
}

#[derive(Deserialize)]
pub struct CreateAppointmentSeriesBody {
    pub practitioner_id: Uuid,
    pub patient_id: Uuid,
    pub motif: Option<String>,
    pub occurrences: Vec<OccurrenceInput>,
}

struct ParsedOccurrence {
    starts_at: DateTime<Utc>,
    ends_at: DateTime<Utc>,
}

#[derive(Serialize)]
pub struct AppointmentSeriesItem {
    pub id: Uuid,
    pub recurrence_index: i32,
    pub starts_at: String,
    pub ends_at: String,
}

#[derive(Serialize)]
pub struct CreateAppointmentSeriesResponse {
    pub recurrence_id: Uuid,
    pub appointments: Vec<AppointmentSeriesItem>,
}

fn is_exclusion_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23P01")
    )
}

/// `POST /v1/cabinet/appointments/series` — crée N `appointment` liés par un
/// `recurrence_id` commun, en une seule transaction.
///
/// Token pro requis (secretary+). `occurrences` vide → 422. `ends_at <=
/// starts_at` sur une occurrence → 422 (avant tout INSERT, anticipe le CHECK
/// `appointment_time_order`). Patient ou praticien hors cabinet → 404.
/// Toute occurrence en conflit (23P01, `appointment_no_overlap`) → 409
/// `slot_taken`, la transaction entière est abandonnée (aucun RDV créé).
pub async fn create_appointment_series(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateAppointmentSeriesBody>,
) -> Result<(StatusCode, Json<CreateAppointmentSeriesResponse>), AppError> {
    if body.occurrences.is_empty() {
        return Err(AppError::ValidationError);
    }
    let mut occurrences = Vec::with_capacity(body.occurrences.len());
    for occ in &body.occurrences {
        let starts_at = occ
            .starts_at
            .parse::<DateTime<Utc>>()
            .map_err(|_| AppError::ValidationError)?;
        let ends_at = occ
            .ends_at
            .parse::<DateTime<Utc>>()
            .map_err(|_| AppError::ValidationError)?;
        if ends_at <= starts_at {
            return Err(AppError::ValidationError);
        }
        occurrences.push(ParsedOccurrence { starts_at, ends_at });
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT id FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL")
        .bind(body.patient_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    sqlx::query("SELECT id FROM practitioner WHERE id = $1 AND cabinet_id = $2")
        .bind(body.practitioner_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let recurrence_id = Uuid::new_v4();
    let mut appointments = Vec::with_capacity(occurrences.len());

    for (i, occ) in occurrences.iter().enumerate() {
        let recurrence_index = (i + 1) as i32;
        let result = sqlx::query(
            "INSERT INTO appointment \
             (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif, \
              recurrence_id, recurrence_index) \
             VALUES ($1, $2, $3, $4, $5, 'requested', $6, $7, $8) \
             RETURNING id",
        )
        .bind(claims.cabinet_id)
        .bind(body.patient_id)
        .bind(body.practitioner_id)
        .bind(occ.starts_at)
        .bind(occ.ends_at)
        .bind(body.motif.as_deref())
        .bind(recurrence_id)
        .bind(recurrence_index)
        .fetch_one(&mut *tx)
        .await;

        let row = match result {
            Ok(r) => r,
            Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
            Err(_) => return Err(AppError::Internal),
        };

        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        appointments.push(AppointmentSeriesItem {
            id,
            recurrence_index,
            starts_at: occ.starts_at.to_rfc3339(),
            ends_at: occ.ends_at.to_rfc3339(),
        });
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok((
        StatusCode::CREATED,
        Json(CreateAppointmentSeriesResponse {
            recurrence_id,
            appointments,
        }),
    ))
}
