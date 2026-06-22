//! Handler `POST /v1/cabinet/slots` — crée un créneau disponible (admin/secrétariat).
//!
//! RBAC : admin ou secrétariat uniquement ; praticien → 403.
//! RLS tenant via `app.current_cabinet_id`.
//! Contrainte d'exclusion praticien (23P01) → 409 slot_taken.

use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Corps de `POST /v1/cabinet/slots`.
#[derive(Deserialize)]
pub struct CreateSlotBody {
    pub starts_at: String,
    pub ends_at: String,
    pub capacity: Option<i32>,
    pub provider_id: Uuid,
}

/// Réponse de `POST /v1/cabinet/slots`.
#[derive(Serialize)]
pub struct CreateSlotResponse {
    pub id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub capacity: i32,
    pub status: String,
}

/// `POST /v1/cabinet/slots` — ouvre un créneau disponible pour le cabinet.
///
/// Auth : admin ou secrétariat ; praticien → 403.
/// `cabinet_id` extrait du JWT (invariant tenancy).
pub async fn create_slot(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateSlotBody>,
) -> Result<(StatusCode, Json<CreateSlotResponse>), AppError> {
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

    let capacity = body.capacity.unwrap_or(1);
    if capacity < 1 {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le provider appartient au cabinet et récupère le practitioner_id.
    let prov_row =
        sqlx::query("SELECT id, practitioner_id FROM provider WHERE id = $1 AND cabinet_id = $2")
            .bind(body.provider_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;

    let practitioner_id: Uuid = prov_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    let slot_id = Uuid::new_v4();

    let result = sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status, online_booking) \
         VALUES ($1, $2, $3, $4, $5, $6, 'open', false) \
         RETURNING id, starts_at, ends_at",
    )
    .bind(slot_id)
    .bind(body.provider_id)
    .bind(claims.cabinet_id)
    .bind(practitioner_id)
    .bind(starts_at)
    .bind(ends_at)
    .fetch_one(&mut *tx)
    .await;

    let row = match result {
        Ok(r) => r,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let sa: chrono::DateTime<chrono::Utc> =
        row.try_get("starts_at").map_err(|_| AppError::Internal)?;
    let ea: chrono::DateTime<chrono::Utc> =
        row.try_get("ends_at").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        slot_id = %id,
        "cabinet slot created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateSlotResponse {
            id,
            starts_at: sa.to_rfc3339(),
            ends_at: ea.to_rfc3339(),
            capacity,
            status: "available".to_string(),
        }),
    ))
}

fn is_exclusion_violation(e: &sqlx::Error) -> bool {
    if let sqlx::Error::Database(db_err) = e {
        return db_err.code().as_deref() == Some("23P01");
    }
    false
}
