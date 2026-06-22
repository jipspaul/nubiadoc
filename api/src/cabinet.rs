//! Handler `POST /v1/cabinet/slots` — secrétariat/admin crée un créneau disponible (§E.2).

use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

#[derive(Deserialize)]
pub struct CreateSlotBody {
    pub starts_at: String,
    pub ends_at: String,
    pub capacity: Option<i32>,
    pub provider_id: Uuid,
}

#[derive(Serialize)]
pub struct CreateSlotResponse {
    pub id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub capacity: i32,
    pub status: String,
}

fn is_exclusion_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23P01")
    )
}

/// `POST /v1/cabinet/slots` — secrétariat/admin crée un créneau disponible (§E.2).
///
/// Auth : admin ou secretary ; practitioner → 403.
/// `SET LOCAL app.current_cabinet_id` + policy `tenant_isolation`.
/// Conflit d'exclusion praticien (23P01) → 409 slot_taken.
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

    let capacity = body.capacity.unwrap_or(1).max(1);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let prov_row =
        sqlx::query("SELECT id, practitioner_id FROM provider WHERE id = $1 AND cabinet_id = $2")
            .bind(body.provider_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;

    let practitioner_id: Option<Uuid> = prov_row.try_get("practitioner_id").unwrap_or(None);

    let result = sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status, online_booking) \
         VALUES ($1, $2, $3, $4, $5, $6, 'open', false) \
         RETURNING id, starts_at, ends_at",
    )
    .bind(Uuid::new_v4())
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
