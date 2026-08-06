//! Handlers `provider_unavailability` (migration 0116) — indisponibilités
//! génériques d'un praticien (vacances, formation, congés). La table existait
//! en base (0116, étendue par #4158) sans aucune route ni handler applicatif :
//! ni pour la déclarer, ni pour la consulter — un praticien ne pouvait donc
//! jamais bloquer génériquement son agenda (#4647).

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Corps de `POST /v1/cabinet/unavailability`.
#[derive(Deserialize)]
pub struct CreateUnavailabilityBody {
    pub practitioner_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub reason: Option<String>,
}

/// Réponse d'une indisponibilité praticien.
#[derive(Serialize)]
pub struct UnavailabilityItem {
    pub id: Uuid,
    pub practitioner_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub reason: Option<String>,
}

/// `POST /v1/cabinet/unavailability` — déclare une plage d'indisponibilité
/// praticien (vacances, formation, congés).
///
/// Token pro requis (secretary, practitioner, admin). Un praticien ne peut
/// déclarer que sa propre indisponibilité (403 sinon) ; secretary/admin
/// peuvent la déclarer pour n'importe quel praticien du cabinet.
/// `cabinet_id` extrait du JWT, jamais du body. RLS scopée via
/// `app.current_cabinet_id` (transitive via `provider.cabinet_id`, 0116).
pub async fn create_unavailability(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateUnavailabilityBody>,
) -> Result<(StatusCode, Json<UnavailabilityItem>), AppError> {
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

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le praticien appartient au cabinet (RLS garantit l'isolation).
    let pract =
        sqlx::query("SELECT id, user_id FROM practitioner WHERE id = $1 AND cabinet_id = $2")
            .bind(body.practitioner_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;

    // Un praticien ne déclare que sa propre indisponibilité — même politique
    // de rôle que create_cabinet_slot pour secretary/admin, mais ici le
    // praticien EST autorisé à agir sur son propre agenda (contrairement aux
    // créneaux, gérés uniquement par le secrétariat).
    if claims.role == "practitioner" {
        let owner_user_id: Option<Uuid> =
            pract.try_get("user_id").map_err(|_| AppError::Internal)?;
        if owner_user_id != Some(claims.sub) {
            return Err(AppError::Forbidden);
        }
    }

    let provider_id: Uuid = sqlx::query(
        "SELECT id FROM provider WHERE practitioner_id = $1 AND cabinet_id = $2 LIMIT 1",
    )
    .bind(body.practitioner_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?
    .try_get("id")
    .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO provider_unavailability (provider_id, starts_at, ends_at, reason) \
         VALUES ($1, $2, $3, $4) \
         RETURNING id, starts_at, ends_at, reason",
    )
    .bind(provider_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(body.reason.as_deref())
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let sa: chrono::DateTime<chrono::Utc> =
        row.try_get("starts_at").map_err(|_| AppError::Internal)?;
    let ea: chrono::DateTime<chrono::Utc> =
        row.try_get("ends_at").map_err(|_| AppError::Internal)?;
    let reason: Option<String> = row.try_get("reason").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        practitioner_id = %body.practitioner_id,
        unavailability_id = %id,
        "provider unavailability created"
    );

    Ok((
        StatusCode::CREATED,
        Json(UnavailabilityItem {
            id,
            practitioner_id: body.practitioner_id,
            starts_at: sa.to_rfc3339(),
            ends_at: ea.to_rfc3339(),
            reason,
        }),
    ))
}

/// Query params de `GET /v1/cabinet/unavailability`.
#[derive(Deserialize)]
pub struct ListUnavailabilityQuery {
    pub practitioner_id: Option<Uuid>,
}

/// `GET /v1/cabinet/unavailability` — liste les indisponibilités déclarées du cabinet.
///
/// Token pro requis (secretary, practitioner, admin). `cabinet_id` extrait du
/// JWT, RLS scopée via `app.current_cabinet_id`. Filtre optionnel `practitioner_id`.
pub async fn list_unavailability(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<ListUnavailabilityQuery>,
) -> Result<Json<Vec<UnavailabilityItem>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT pu.id, p.practitioner_id, pu.starts_at, pu.ends_at, pu.reason \
         FROM provider_unavailability pu \
         JOIN provider p ON p.id = pu.provider_id \
         WHERE ($1::uuid IS NULL OR p.practitioner_id = $1) \
         ORDER BY pu.starts_at",
    )
    .bind(params.practitioner_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let items = rows
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
            let reason: Option<String> = row.try_get("reason").map_err(|_| AppError::Internal)?;
            Ok(UnavailabilityItem {
                id,
                practitioner_id,
                starts_at: starts_at.to_rfc3339(),
                ends_at: ends_at.to_rfc3339(),
                reason,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(items))
}

/// `DELETE /v1/cabinet/unavailability/:id` — annule une indisponibilité déclarée.
///
/// Token pro requis (secretary, practitioner, admin). Même politique de rôle
/// que `create_unavailability` : un praticien ne supprime que la sienne.
pub async fn delete_unavailability(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT p.practitioner_id, pr.user_id \
         FROM provider_unavailability pu \
         JOIN provider p ON p.id = pu.provider_id \
         JOIN practitioner pr ON pr.id = p.practitioner_id \
         WHERE pu.id = $1",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    if claims.role == "practitioner" {
        let owner_user_id: Option<Uuid> = row.try_get("user_id").map_err(|_| AppError::Internal)?;
        if owner_user_id != Some(claims.sub) {
            return Err(AppError::Forbidden);
        }
    }

    sqlx::query("DELETE FROM provider_unavailability WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        unavailability_id = %id,
        "provider unavailability deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}
