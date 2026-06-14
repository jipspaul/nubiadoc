//! Handler `POST /v1/bookings` — consomme un hold_token et crée un appointment.
//!
//! Flux E.3.22.a : le patient a préalablement posé un hold via `POST /v1/slots/:id/hold`.
//! Ce handler valide le hold (non expiré, appartient au caller), crée l'appointment
//! et supprime le hold en une transaction atomique.

use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

/// Corps de la requête `POST /v1/bookings`.
#[derive(Deserialize)]
pub struct CreateBookingBody {
    pub slot_id: Uuid,
    pub hold_token: String,
    pub idempotency_key: Option<String>,
}

/// Réponse de `POST /v1/bookings`.
#[derive(Serialize)]
pub struct CreateBookingResponse {
    pub appointment_id: Uuid,
    pub status: String,
}

/// `POST /v1/bookings` — consomme un hold et crée un appointment (E.3.22.a).
///
/// Token `kind:"patient"` requis. Valide que le hold existe, n'est pas expiré
/// et appartient au caller. Crée l'appointment (`status = "requested"`) puis
/// supprime le hold. Contrainte d'exclusion DB (23P01) → `409 slot_taken`.
/// Idempotence optionnelle : si `idempotency_key` fournie et appointment existant
/// pour ce cabinet + clé → retourne le RDV existant.
pub async fn create_booking(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<CreateBookingBody>,
) -> Result<(StatusCode, Json<CreateBookingResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Résout le créneau pour obtenir cabinet_id + practitioner_id + starts_at/ends_at.
    let slot_row = sqlx::query(
        "SELECT id, cabinet_id, practitioner_id, starts_at, ends_at \
         FROM availability_slot \
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(body.slot_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = slot_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = slot_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let starts_at: chrono::DateTime<chrono::Utc> = slot_row
        .try_get("starts_at")
        .map_err(|_| AppError::Internal)?;
    let ends_at: chrono::DateTime<chrono::Utc> = slot_row
        .try_get("ends_at")
        .map_err(|_| AppError::Internal)?;

    // Scope cabinet pour les requêtes soumises à la RLS tenant_isolation.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Idempotence : si un appointment existe déjà pour cette clé, le retourner.
    if let Some(ref key) = body.idempotency_key {
        let existing = sqlx::query(
            "SELECT id, status FROM appointment \
             WHERE cabinet_id = $1 AND idempotency_key = $2",
        )
        .bind(cabinet_id)
        .bind(key)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        if let Some(row) = existing {
            let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            tx.commit().await.map_err(|_| AppError::Internal)?;
            tracing::info!(
                account_id = %claims.account_id,
                appointment_id = %appointment_id,
                "booking create idempotent hit"
            );
            return Ok((
                StatusCode::CREATED,
                Json(CreateBookingResponse {
                    appointment_id,
                    status,
                }),
            ));
        }
    }

    // Valide le hold : appartient au caller, non expiré.
    let hold_row = sqlx::query(
        "SELECT id FROM slot_holds \
         WHERE slot_id = $1 AND hold_token = $2 AND user_id = $3 AND expires_at > now()",
    )
    .bind(body.slot_id)
    .bind(&body.hold_token)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::HoldInvalid)?;

    let hold_id: Uuid = hold_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Scope patient pour résoudre le dossier patient dans ce cabinet.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let patient_row = sqlx::query(
        "SELECT id FROM patient \
         WHERE patient_account_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(claims.account_id)
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let patient_id: Uuid = patient_row.try_get("id").map_err(|_| AppError::Internal)?;

    // INSERT appointment — 23P01 (appointment_no_overlap) → 409 slot_taken.
    let result = sqlx::query(
        "INSERT INTO appointment \
         (cabinet_id, patient_id, practitioner_id, slot_id, starts_at, ends_at, status, idempotency_key) \
         VALUES ($1, $2, $3, $4, $5, $6, 'requested', $7) \
         RETURNING id, status",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(body.slot_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(&body.idempotency_key)
    .fetch_one(&mut *tx)
    .await;

    let row = match result {
        Ok(r) => r,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    // Consomme le créneau (status → 'booked').
    sqlx::query(
        "UPDATE availability_slot SET status = 'booked', updated_at = now() \
         WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(body.slot_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Supprime le hold.
    sqlx::query("DELETE FROM slot_holds WHERE id = $1")
        .bind(hold_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %appointment_id,
        slot_id = %body.slot_id,
        "booking created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateBookingResponse {
            appointment_id,
            status,
        }),
    ))
}

fn is_exclusion_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23P01")
    )
}
