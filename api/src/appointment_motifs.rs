//! CRUD `/v1/cabinet/appointment-motifs` (#4085) — gestion du catalogue de
//! motifs de RDV paramétrable par cabinet (table `appointment_motif`,
//! migration 0172).
//!
//! Quand : back-office cabinet configurant ses motifs récurrents et leur
//! durée type, consommés ensuite à la création d'un RDV (préremplissage).
//!
//! Pourquoi cette approche : lecture ouverte à tout rôle pro (`secretary`
//! inclus — nécessaire pour préremplir l'agenda côté secrétariat), écriture
//! (création/modification/suppression) réservée aux `admin` — spec explicite
//! de l'issue (#4085 : "403 pour un rôle secretary si la création est
//! admin-only").
//!
//! Modes d'échec : `label` vide (après trim) ou `default_duration_minutes`
//! <= 0 → 422 `validation_error`. Motif hors cabinet courant (RLS) → 404.
//! PATCH sans aucun champ fourni → 422 (rien à modifier). PATCH ne permet
//! pas d'effacer un `default_duration_minutes` déjà positionné (mettre à
//! NULL) — non demandé par l'issue ; recréer le motif si besoin.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminClaims, ProSecretaryPlusClaims},
    AppState,
};

#[derive(Serialize)]
pub struct AppointmentMotifItem {
    pub id: Uuid,
    pub label: String,
    pub default_duration_minutes: Option<i32>,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct ListAppointmentMotifsResponse {
    pub data: Vec<AppointmentMotifItem>,
}

fn row_to_item(row: &sqlx::postgres::PgRow) -> Result<AppointmentMotifItem, AppError> {
    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
    let default_duration_minutes: Option<i32> = row
        .try_get("default_duration_minutes")
        .map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    Ok(AppointmentMotifItem {
        id,
        label,
        default_duration_minutes,
        created_at: created_at.to_rfc3339(),
    })
}

/// `GET /v1/cabinet/appointment-motifs` — liste les motifs du cabinet
/// courant. Tout rôle pro (secretary+).
pub async fn list_appointment_motifs(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<ListAppointmentMotifsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, label, default_duration_minutes, created_at FROM appointment_motif \
         ORDER BY label ASC",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(row_to_item)
        .collect::<Result<Vec<_>, _>>()?;

    Ok(Json(ListAppointmentMotifsResponse { data }))
}

/// Corps de la requête `POST /v1/cabinet/appointment-motifs`.
#[derive(Deserialize)]
pub struct CreateAppointmentMotifBody {
    pub label: String,
    pub default_duration_minutes: Option<i32>,
}

fn validate_label(label: &str) -> Result<String, AppError> {
    let trimmed = label.trim().to_string();
    if trimmed.is_empty() {
        return Err(AppError::ValidationError);
    }
    // #4600 : NUL byte non filtré → bind Postgres échoue, masqué en 500.
    crate::text_validation::reject_nul_byte(&trimmed)?;
    Ok(trimmed)
}

fn validate_duration(duration: Option<i32>) -> Result<(), AppError> {
    if let Some(minutes) = duration {
        if minutes <= 0 {
            return Err(AppError::ValidationError);
        }
    }
    Ok(())
}

/// `POST /v1/cabinet/appointment-motifs` — crée un motif. Admin uniquement.
pub async fn create_appointment_motif(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Json(body): Json<CreateAppointmentMotifBody>,
) -> Result<(StatusCode, Json<AppointmentMotifItem>), AppError> {
    let label = validate_label(&body.label)?;
    validate_duration(body.default_duration_minutes)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO appointment_motif (cabinet_id, label, default_duration_minutes) \
         VALUES ($1, $2, $3) \
         RETURNING id, label, default_duration_minutes, created_at",
    )
    .bind(claims.cabinet_id)
    .bind(&label)
    .bind(body.default_duration_minutes)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok((StatusCode::CREATED, Json(row_to_item(&row)?)))
}

/// Corps de la requête `PATCH /v1/cabinet/appointment-motifs/:id`.
#[derive(Deserialize)]
pub struct UpdateAppointmentMotifBody {
    pub label: Option<String>,
    pub default_duration_minutes: Option<i32>,
}

/// `PATCH /v1/cabinet/appointment-motifs/:id` — modifie un motif. Admin
/// uniquement. Au moins un champ requis, sinon 422.
pub async fn update_appointment_motif(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Path(motif_id): Path<Uuid>,
    Json(body): Json<UpdateAppointmentMotifBody>,
) -> Result<Json<AppointmentMotifItem>, AppError> {
    if body.label.is_none() && body.default_duration_minutes.is_none() {
        return Err(AppError::ValidationError);
    }
    let label = body.label.as_deref().map(validate_label).transpose()?;
    validate_duration(body.default_duration_minutes)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "UPDATE appointment_motif \
         SET label = COALESCE($1, label), \
             default_duration_minutes = COALESCE($2, default_duration_minutes) \
         WHERE id = $3 \
         RETURNING id, label, default_duration_minutes, created_at",
    )
    .bind(label)
    .bind(body.default_duration_minutes)
    .bind(motif_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        return Err(AppError::NotFound);
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(row_to_item(&row)?))
}

/// `DELETE /v1/cabinet/appointment-motifs/:id` — supprime un motif. Admin
/// uniquement.
pub async fn delete_appointment_motif(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Path(motif_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let deleted = sqlx::query("DELETE FROM appointment_motif WHERE id = $1 RETURNING id")
        .bind(motif_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if deleted.is_none() {
        return Err(AppError::NotFound);
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(StatusCode::NO_CONTENT)
}
