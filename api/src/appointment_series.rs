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
/// `appointment_time_order`). `starts_at <= now()` sur une occurrence → 422
/// `start_at_not_future` (#4342 — parité avec `create_cabinet_slot`
/// `scheduling.rs` et `create_booking` `bookings.rs`, qui gardent déjà le
/// futur ; la série laissait passer des occurrences entièrement révolues).
/// Patient ou praticien hors cabinet → 404.
/// Toute occurrence chevauchant une indisponibilité praticien
/// (`availability_slot.status='blocked'`) → 409 `slot_taken` (#4344 —
/// parité avec `create_cabinet_appointment` `scheduling.rs`, qui exige un
/// slot `status='open'` ; `appointment_no_overlap` ne connaît que les
/// `appointment` entre eux, pas les `availability_slot`).
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
        if starts_at <= Utc::now() {
            return Err(AppError::StartAtNotFuture);
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

        // #4344 : une occurrence ne doit pas chevaucher une indisponibilité
        // praticien (availability_slot.status='blocked'), au meme titre que
        // create_cabinet_appointment (scheduling.rs) qui exige un slot
        // status='open'. appointment_no_overlap (EXCLUDE) ne connait que les
        // appointment entre eux, pas les availability_slot.
        let blocked = sqlx::query(
            "SELECT 1 FROM availability_slot \
             WHERE cabinet_id = $1 AND practitioner_id = $2 AND status = 'blocked' \
               AND deleted_at IS NULL \
               AND tstzrange(starts_at, ends_at) && tstzrange($3, $4)",
        )
        .bind(claims.cabinet_id)
        .bind(body.practitioner_id)
        .bind(occ.starts_at)
        .bind(occ.ends_at)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        if blocked.is_some() {
            return Err(AppError::SlotTaken);
        }

        // #4408 : contrairement à create_cabinet_appointment (scheduling.rs)
        // et create_appointment (appointments.rs), la série ne consommait
        // aucun availability_slot chevauché — un créneau 'open' publié
        // restait visible dans /search/slots (créneau fantôme) alors que
        // cette occurrence l'occupe déjà, menant à un 409 slot_taken à la
        // réservation. Consomme le slot 'open' recouvert par l'occurrence,
        // même logique que la vérification 'blocked' ci-dessus, et retient
        // son id pour le poser sur l'appointment (#4576 : sans slot_id, les
        // voies de libération — cancel/no-show/reprogrammation — ne
        // retrouvent jamais ce créneau et il reste 'booked' à vie).
        let consumed_slot_id: Option<Uuid> = sqlx::query_scalar(
            "UPDATE availability_slot SET status = 'booked', updated_at = now() \
             WHERE id = ( \
                 SELECT id FROM availability_slot \
                 WHERE cabinet_id = $1 AND practitioner_id = $2 AND status = 'open' \
                   AND deleted_at IS NULL \
                   AND tstzrange(starts_at, ends_at) && tstzrange($3, $4) \
                 LIMIT 1 \
                 FOR UPDATE \
             ) \
             RETURNING id",
        )
        .bind(claims.cabinet_id)
        .bind(body.practitioner_id)
        .bind(occ.starts_at)
        .bind(occ.ends_at)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        let result = sqlx::query(
            "INSERT INTO appointment \
             (cabinet_id, patient_id, practitioner_id, slot_id, starts_at, ends_at, status, \
              motif, recurrence_id, recurrence_index) \
             VALUES ($1, $2, $3, $4, $5, $6, 'requested', $7, $8, $9) \
             RETURNING id",
        )
        .bind(claims.cabinet_id)
        .bind(body.patient_id)
        .bind(body.practitioner_id)
        .bind(consumed_slot_id)
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
