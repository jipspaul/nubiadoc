//! Handlers CRUD `cr_template` (#4124) : `GET`/`POST
//! /v1/cabinet/cr-templates`, `PATCH`/`DELETE /v1/cabinet/cr-templates/:id`.
//!
//! S'appuie sur `cr_template` (migration 0186, #4123) : entité tenant
//! (RLS `tenant_isolation` sur `cabinet_id`), `ccam_code` nullable + FK vers
//! `ccam_act(code)`. Praticien uniquement, pas de restriction de propriété
//! au-delà du cabinet (contrairement à `consultation_act_create.rs` — un
//! modèle de CR est un outil partagé du cabinet, pas lié à une séance).

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

/// Un modèle de compte rendu, vu du cabinet courant.
#[derive(Serialize)]
pub struct CrTemplateDto {
    pub id: Uuid,
    pub ccam_code: Option<String>,
    pub title: String,
    pub body_template: String,
}

// ── GET /v1/cabinet/cr-templates ─────────────────────────────────────────────

/// `GET /v1/cabinet/cr-templates` — liste les modèles du cabinet.
///
/// Praticien uniquement. RLS tenant-scoped via `app.current_cabinet_id`.
pub async fn list_cr_templates(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
) -> Result<Json<Vec<CrTemplateDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, ccam_code, title, body_template \
         FROM cr_template \
         ORDER BY title",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut templates = Vec::with_capacity(rows.len());
    for row in &rows {
        templates.push(CrTemplateDto {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            ccam_code: row.try_get("ccam_code").map_err(|_| AppError::Internal)?,
            title: row.try_get("title").map_err(|_| AppError::Internal)?,
            body_template: row
                .try_get("body_template")
                .map_err(|_| AppError::Internal)?,
        });
    }

    Ok(Json(templates))
}

// ── POST /v1/cabinet/cr-templates ────────────────────────────────────────────

/// Corps de `POST /v1/cabinet/cr-templates`.
#[derive(Deserialize)]
pub struct CreateCrTemplateBody {
    pub ccam_code: Option<String>,
    pub title: String,
    pub body_template: String,
}

/// Réponse de `POST /v1/cabinet/cr-templates`.
#[derive(Serialize)]
pub struct CreateCrTemplateResponse {
    pub id: Uuid,
}

/// `POST /v1/cabinet/cr-templates` — crée un modèle propre au cabinet.
///
/// `title`/`body_template` non vides/blancs → 422 sinon. `ccam_code` s'il est
/// fourni doit référencer un code du catalogue `ccam_act` → 422 sinon (même
/// vérification applicative préalable qu'ailleurs dans le code, plutôt que de
/// laisser remonter la violation FK 23503 en 500, cf. `prescriptions.rs`).
pub async fn create_cr_template(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Json(body): Json<CreateCrTemplateBody>,
) -> Result<(StatusCode, Json<CreateCrTemplateResponse>), AppError> {
    if body.title.trim().is_empty() || body.body_template.trim().is_empty() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if let Some(code) = &body.ccam_code {
        let exists = sqlx::query("SELECT 1 FROM ccam_act WHERE code = $1")
            .bind(code)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::ValidationError);
        }
    }

    let row = sqlx::query(
        "INSERT INTO cr_template (cabinet_id, ccam_code, title, body_template) \
         VALUES ($1, $2, $3, $4) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.ccam_code.as_deref())
    .bind(body.title.trim())
    .bind(body.body_template.trim())
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        template_id = %id,
        "cr template created"
    );

    Ok((StatusCode::CREATED, Json(CreateCrTemplateResponse { id })))
}

// ── PATCH /v1/cabinet/cr-templates/:id ───────────────────────────────────────

/// Corps de `PATCH /v1/cabinet/cr-templates/:id`.
#[derive(Deserialize)]
pub struct PatchCrTemplateBody {
    pub ccam_code: Option<String>,
    pub title: Option<String>,
    pub body_template: Option<String>,
}

/// `PATCH /v1/cabinet/cr-templates/:id` — modifie un modèle du cabinet.
///
/// Champs absents = inchangés (`COALESCE`, même convention que
/// `consultation_acts::patch_consultation_act` — pas de remise à `NULL`
/// explicite de `ccam_code` supportée). 404 si le modèle est absent ou hors
/// tenant (RLS). `ccam_code` fourni doit référencer `ccam_act` → 422 sinon.
pub async fn patch_cr_template(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchCrTemplateBody>,
) -> Result<Json<CreateCrTemplateResponse>, AppError> {
    if body.title.as_deref().is_some_and(|s| s.trim().is_empty())
        || body
            .body_template
            .as_deref()
            .is_some_and(|s| s.trim().is_empty())
    {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if let Some(code) = &body.ccam_code {
        let exists = sqlx::query("SELECT 1 FROM ccam_act WHERE code = $1")
            .bind(code)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::ValidationError);
        }
    }

    let updated = sqlx::query(
        "UPDATE cr_template \
         SET ccam_code     = COALESCE($1, ccam_code), \
             title         = COALESCE($2, title), \
             body_template = COALESCE($3, body_template), \
             updated_at    = now() \
         WHERE id = $4 AND cabinet_id = $5 \
         RETURNING id",
    )
    .bind(body.ccam_code.as_deref())
    .bind(body.title.as_deref().map(str::trim))
    .bind(body.body_template.as_deref().map(str::trim))
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let updated_id: Uuid = updated.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        template_id = %updated_id,
        "cr template patched"
    );

    Ok(Json(CreateCrTemplateResponse { id: updated_id }))
}

// ── DELETE /v1/cabinet/cr-templates/:id ──────────────────────────────────────

/// `DELETE /v1/cabinet/cr-templates/:id` — supprime un modèle du cabinet.
///
/// 404 si le modèle est absent ou hors tenant (RLS).
pub async fn delete_cr_template(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let deleted =
        sqlx::query("DELETE FROM cr_template WHERE id = $1 AND cabinet_id = $2 RETURNING id")
            .bind(id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    if deleted.is_none() {
        return Err(AppError::NotFound);
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        template_id = %id,
        "cr template deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}
