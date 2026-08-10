//! Handlers `GET/POST /v1/cabinet/ccam-stock-mappings` et
//! `DELETE /v1/cabinet/ccam-stock-mappings/:id` (#4798), sur
//! `ccam_act_stock_consumption` (migration 0192, #4143) : le mapping
//! catalogue — quelle quantité d'un `stock_item` est consommée par un acte
//! CCAM donné — nécessaire pour que `apply_stock_consumption`
//! (`consultation_act_stock.rs`, #4145/#4438) trouve des lignes. La table
//! existait déjà (RLS + GRANT complets) mais n'avait AUCUN point d'entrée
//! API ni seed : `apply_stock_consumption` renvoyait donc systématiquement
//! zéro ligne, rendant la décrémentation automatique du stock
//! structurellement inatteignable en pratique.
//!
//! `ProSecretaryPlusClaims` (secretary/practitioner/admin/manager) : même
//! périmètre que la gestion des `stock_item` eux-mêmes (`stock_items.rs`,
//! #4144) — tâche opérationnelle du cabinet, pas une décision clinique.

use axum::{
    extract::{Path, State},
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

/// Un mapping CCAM → stock, tel que consommé par `apply_stock_consumption`.
#[derive(Serialize)]
pub struct CcamStockMappingDto {
    pub id: Uuid,
    pub ccam_code: String,
    pub stock_item_id: Uuid,
    pub quantity: i32,
}

/// `GET /v1/cabinet/ccam-stock-mappings` — liste les mappings du cabinet.
pub async fn list_ccam_stock_mappings(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<Vec<CcamStockMappingDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, ccam_code, stock_item_id, quantity \
         FROM ccam_act_stock_consumption \
         WHERE cabinet_id = $1 \
         ORDER BY ccam_code",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut mappings = Vec::with_capacity(rows.len());
    for row in &rows {
        mappings.push(CcamStockMappingDto {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            ccam_code: row.try_get("ccam_code").map_err(|_| AppError::Internal)?,
            stock_item_id: row
                .try_get("stock_item_id")
                .map_err(|_| AppError::Internal)?,
            quantity: row.try_get("quantity").map_err(|_| AppError::Internal)?,
        });
    }

    Ok(Json(mappings))
}

/// Body de `POST /v1/cabinet/ccam-stock-mappings`.
#[derive(Deserialize)]
pub struct CreateCcamStockMappingBody {
    pub ccam_code: String,
    pub stock_item_id: Uuid,
    pub quantity: i32,
}

/// Réponse de `POST /v1/cabinet/ccam-stock-mappings`.
#[derive(Serialize)]
pub struct CreateCcamStockMappingResponse {
    pub mapping_id: Uuid,
}

/// `POST /v1/cabinet/ccam-stock-mappings` — crée un mapping : `quantity`
/// unités de `stock_item_id` seront décrémentées à chaque facturation d'un
/// acte `ccam_code` dans ce cabinet.
///
/// `quantity` doit être strictement positif (`CHECK`, migration 0192) → 422
/// sinon. `ccam_code` doit exister dans le catalogue actif → 422 sinon
/// (même choix que `practitioner_favorite_acts.rs::create_favorite_act`).
/// `stock_item_id` doit exister dans ce cabinet → 404 sinon (FK composite
/// `(stock_item_id, cabinet_id)`, migration 0190 — pré-vérifié plutôt que
/// laisser remonter la contrainte en 500). Mapping déjà existant pour ce
/// triplet `(cabinet_id, ccam_code, stock_item_id)` → `409
/// stock_mapping_already_exists` (index unique, migration 0192).
pub async fn create_ccam_stock_mapping(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateCcamStockMappingBody>,
) -> Result<(StatusCode, Json<CreateCcamStockMappingResponse>), AppError> {
    if body.quantity <= 0 {
        return Err(AppError::ValidationError);
    }
    crate::text_validation::reject_nul_byte(&body.ccam_code)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let ccam_exists = sqlx::query("SELECT 1 FROM ccam_act WHERE code = $1 AND active = true")
        .bind(&body.ccam_code)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if ccam_exists.is_none() {
        return Err(AppError::ValidationError);
    }

    let stock_item_exists =
        sqlx::query("SELECT 1 FROM stock_item WHERE id = $1 AND cabinet_id = $2")
            .bind(body.stock_item_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if stock_item_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let row = sqlx::query(
        "INSERT INTO ccam_act_stock_consumption \
         (cabinet_id, ccam_code, stock_item_id, quantity) \
         VALUES ($1, $2, $3, $4) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(&body.ccam_code)
    .bind(body.stock_item_id)
    .bind(body.quantity)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            AppError::StockMappingAlreadyExists
        }
        _ => AppError::Internal,
    })?;

    let mapping_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        mapping_id = %mapping_id,
        ccam_code = %body.ccam_code,
        stock_item_id = %body.stock_item_id,
        "ccam stock mapping created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateCcamStockMappingResponse { mapping_id }),
    ))
}

/// `DELETE /v1/cabinet/ccam-stock-mappings/:id` — retire un mapping.
/// `404` si absent/hors tenant.
pub async fn delete_ccam_stock_mapping(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(mapping_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let deleted = sqlx::query(
        "DELETE FROM ccam_act_stock_consumption \
         WHERE id = $1 AND cabinet_id = $2 \
         RETURNING id",
    )
    .bind(mapping_id)
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
        mapping_id = %mapping_id,
        "ccam stock mapping deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}
