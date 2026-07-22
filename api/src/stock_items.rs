//! Handlers inventaire cabinet (#4144), sur `stock_item`/`stock_movement`
//! (migration 0192, #4143) :
//! - `GET/POST /v1/cabinet/stock-items`
//! - `POST /v1/cabinet/stock-items/:id/movements`
//!
//! `ProSecretaryPlusClaims` (secretary/practitioner/admin/manager) : la
//! gestion d'inventaire est une tâche opérationnelle du cabinet, pas une
//! décision clinique — même pattern que `sterilization.rs`.

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

const VALID_REASONS: [&str; 4] = ["reception", "consumption", "adjustment", "peremption"];

// ── GET/POST /v1/cabinet/stock-items ─────────────────────────────────────────

/// Un article d'inventaire cabinet.
#[derive(Serialize)]
pub struct StockItemDto {
    pub id: Uuid,
    pub reference: String,
    pub label: String,
    pub unit: String,
    pub quantity_on_hand: i32,
    pub alert_threshold: Option<i32>,
}

/// `GET /v1/cabinet/stock-items` — liste les articles du cabinet, par référence.
pub async fn list_stock_items(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<Vec<StockItemDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, reference, label, unit, quantity_on_hand, alert_threshold \
         FROM stock_item \
         WHERE cabinet_id = $1 \
         ORDER BY reference",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut items = Vec::with_capacity(rows.len());
    for row in &rows {
        items.push(StockItemDto {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            reference: row.try_get("reference").map_err(|_| AppError::Internal)?,
            label: row.try_get("label").map_err(|_| AppError::Internal)?,
            unit: row.try_get("unit").map_err(|_| AppError::Internal)?,
            quantity_on_hand: row
                .try_get("quantity_on_hand")
                .map_err(|_| AppError::Internal)?,
            alert_threshold: row
                .try_get("alert_threshold")
                .map_err(|_| AppError::Internal)?,
        });
    }

    Ok(Json(items))
}

/// Body de `POST /v1/cabinet/stock-items`.
#[derive(Deserialize)]
pub struct CreateStockItemBody {
    pub reference: String,
    pub label: String,
    pub unit: String,
    pub alert_threshold: Option<i32>,
}

/// Réponse de `POST /v1/cabinet/stock-items`.
#[derive(Serialize)]
pub struct CreateStockItemResponse {
    pub item_id: Uuid,
}

/// `POST /v1/cabinet/stock-items` — crée un article, `quantity_on_hand`
/// démarre à 0 (alimenté ensuite par des mouvements de réception).
///
/// `reference`/`label`/`unit` non vides → 422 sinon. `reference` déjà
/// utilisée dans ce cabinet → `409 stock_reference_already_used` (index
/// unique `(cabinet_id, reference)`, migration 0192).
pub async fn create_stock_item(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateStockItemBody>,
) -> Result<(StatusCode, Json<CreateStockItemResponse>), AppError> {
    if body.reference.trim().is_empty()
        || body.label.trim().is_empty()
        || body.unit.trim().is_empty()
    {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO stock_item (cabinet_id, reference, label, unit, alert_threshold) \
         VALUES ($1, $2, $3, $4, $5) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.reference.trim())
    .bind(body.label.trim())
    .bind(body.unit.trim())
    .bind(body.alert_threshold)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            AppError::StockReferenceAlreadyUsed
        }
        _ => AppError::Internal,
    })?;

    let item_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        item_id = %item_id,
        "stock item created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateStockItemResponse { item_id }),
    ))
}

// ── POST /v1/cabinet/stock-items/:id/movements ───────────────────────────────

/// Body de `POST /v1/cabinet/stock-items/:id/movements`.
#[derive(Deserialize)]
pub struct AddStockMovementBody {
    pub delta: i32,
    pub reason: String,
    pub expiry_date: Option<String>,
    pub consultation_act_id: Option<Uuid>,
}

/// Réponse de `POST /v1/cabinet/stock-items/:id/movements`.
#[derive(Serialize)]
pub struct AddStockMovementResponse {
    pub movement_id: Uuid,
    pub quantity_on_hand: i32,
}

/// `POST /v1/cabinet/stock-items/:id/movements` — réception, consommation,
/// ajustement ou péremption manuelle ; met à jour `quantity_on_hand` de
/// façon atomique dans la même transaction que l'insertion du mouvement.
///
/// Article inexistant/hors tenant → 404. `delta` non nul et `reason` ∈
/// `VALID_REASONS` → 422 sinon. `consultation_act_id` (si fourni) doit
/// exister dans ce cabinet → 404 sinon (FK composite (id, cabinet_id),
/// migration 0192 — pré-vérifié pour ne pas laisser remonter la contrainte
/// en 500, cf. précédent `sterilization.rs`).
pub async fn add_stock_movement(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(item_id): Path<Uuid>,
    Json(body): Json<AddStockMovementBody>,
) -> Result<(StatusCode, Json<AddStockMovementResponse>), AppError> {
    if body.delta == 0 || !VALID_REASONS.contains(&body.reason.as_str()) {
        return Err(AppError::ValidationError);
    }
    let expiry_date = body
        .expiry_date
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let item_exists = sqlx::query("SELECT 1 FROM stock_item WHERE id = $1 AND cabinet_id = $2")
        .bind(item_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if item_exists.is_none() {
        return Err(AppError::NotFound);
    }

    if let Some(act_id) = body.consultation_act_id {
        let act_exists =
            sqlx::query("SELECT 1 FROM consultation_act WHERE id = $1 AND cabinet_id = $2")
                .bind(act_id)
                .bind(claims.cabinet_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
        if act_exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    let row = sqlx::query(
        "INSERT INTO stock_movement \
         (cabinet_id, stock_item_id, delta, reason, expiry_date, consultation_act_id) \
         VALUES ($1, $2, $3, $4, $5, $6) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(item_id)
    .bind(body.delta)
    .bind(&body.reason)
    .bind(expiry_date)
    .bind(body.consultation_act_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let movement_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    let updated = sqlx::query(
        "UPDATE stock_item SET quantity_on_hand = quantity_on_hand + $1 \
         WHERE id = $2 AND cabinet_id = $3 \
         RETURNING quantity_on_hand",
    )
    .bind(body.delta)
    .bind(item_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let quantity_on_hand: i32 = updated
        .try_get("quantity_on_hand")
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        item_id = %item_id,
        movement_id = %movement_id,
        delta = body.delta,
        reason = %body.reason,
        quantity_on_hand,
        "stock movement added"
    );

    Ok((
        StatusCode::CREATED,
        Json(AddStockMovementResponse {
            movement_id,
            quantity_on_hand,
        }),
    ))
}
