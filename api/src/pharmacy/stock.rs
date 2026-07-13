//! Demandes de stock cabinet → pharmacie (lot B5).
//!
//! Espace cabinet : `POST|GET /v1/cabinet/stock-requests`,
//! `POST …/{id}/cancel` (tant que `sent`).
//! Espace pharmacie : `GET /v1/pharmacy/stock-requests`,
//! `POST …/{id}/accept|reject|fulfill`.
//! Les items sont du jsonb `[{label, qty, note?}]` — jamais de donnée patient.

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::postgres::PgRow;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PharmaMemberClaims, ProSecretaryPlusClaims},
    notify,
    realtime::WsHub,
    AppState, JobDispatcher,
};

// ── DTO ───────────────────────────────────────────────────────────────────────

/// Une demande de stock dans les réponses API (mêmes clés des deux bords).
#[derive(Serialize)]
pub struct StockRequestDto {
    pub id: Uuid,
    pub pharmacy_id: Uuid,
    pub cabinet_name: String,
    pub items: serde_json::Value,
    pub status: String,
    pub response_note: Option<String>,
    pub created_at: String,
}

const STOCK_COLUMNS: &str =
    "id, pharmacy_id, cabinet_name, items, status, response_note, created_at";

fn stock_from_row(row: &PgRow) -> Result<StockRequestDto, AppError> {
    Ok(StockRequestDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        pharmacy_id: row.try_get("pharmacy_id").map_err(|_| AppError::Internal)?,
        cabinet_name: row
            .try_get("cabinet_name")
            .map_err(|_| AppError::Internal)?,
        items: row.try_get("items").map_err(|_| AppError::Internal)?,
        status: row.try_get("status").map_err(|_| AppError::Internal)?,
        response_note: row
            .try_get("response_note")
            .map_err(|_| AppError::Internal)?,
        created_at: row
            .try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
            .map_err(|_| AppError::Internal)?
            .to_rfc3339(),
    })
}

/// Réponse liste : `{ data: [...] }`.
#[derive(Serialize)]
pub struct StockRequestsResponse {
    pub data: Vec<StockRequestDto>,
}

// ── Espace cabinet ────────────────────────────────────────────────────────────

/// Une ligne du body de création.
#[derive(Deserialize)]
pub struct StockItemInput {
    pub label: String,
    pub qty: i64,
    pub note: Option<String>,
}

/// Body de `POST /v1/cabinet/stock-requests`.
#[derive(Deserialize)]
pub struct CreateStockRequestBody {
    pub pharmacy_id: Uuid,
    pub items: Vec<StockItemInput>,
}

/// `POST /v1/cabinet/stock-requests` — émet une demande vers une pharmacie
/// listée (404 sinon). Items vides ou libellé vide → 422.
pub async fn create_stock_request(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateStockRequestBody>,
) -> Result<(StatusCode, Json<StockRequestDto>), AppError> {
    if body.items.is_empty()
        || body
            .items
            .iter()
            .any(|item| item.label.trim().is_empty() || item.qty <= 0 || item.qty > 9999)
    {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Pharmacie listée uniquement (policy annuaire public).
    sqlx::query("SELECT 1 FROM pharmacy WHERE id = $1 AND is_listed")
        .bind(body.pharmacy_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let cabinet_name: String = sqlx::query("SELECT raison_sociale FROM cabinet WHERE id = $1")
        .bind(claims.cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;

    let items = serde_json::json!(body
        .items
        .iter()
        .map(|item| {
            serde_json::json!({
                "label": item.label.trim(),
                "qty": item.qty,
                "note": item.note,
            })
        })
        .collect::<Vec<_>>());

    let row = sqlx::query(&format!(
        "INSERT INTO stock_request (cabinet_id, pharmacy_id, created_by, cabinet_name, items) \
         VALUES ($1, $2, $3, $4, $5) \
         RETURNING {STOCK_COLUMNS}",
    ))
    .bind(claims.cabinet_id)
    .bind(body.pharmacy_id)
    .bind(claims.sub)
    .bind(&cabinet_name)
    .bind(&items)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let request = stock_from_row(&row)?;

    // Notification du staff pharmacie (lot B4).
    let staff = notify::notify_pharmacy_staff(
        &mut tx,
        body.pharmacy_id,
        "stock_request_received",
        "Nouvelle demande de stock",
        serde_json::json!({ "stock_request_id": request.id, "status": "sent" }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    for (app_user_id, notification_id) in staff {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("pharmacy_orders:{}", body.pharmacy_id),
        serde_json::json!({
            "channel": format!("pharmacy_orders:{}", body.pharmacy_id),
            "event": "stock_request_received",
            "data": { "stock_request_id": request.id, "status": "sent" }
        })
        .to_string(),
    );

    Ok((StatusCode::CREATED, Json(request)))
}

/// `GET /v1/cabinet/stock-requests` — demandes émises par le cabinet.
pub async fn list_cabinet_stock_requests(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<StockRequestsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&format!(
        "SELECT {STOCK_COLUMNS} FROM stock_request ORDER BY created_at DESC LIMIT 200",
    ))
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(stock_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(StockRequestsResponse { data }))
}

/// `POST /v1/cabinet/stock-requests/{id}/cancel` — annulation tant que `sent`.
pub async fn cancel_stock_request(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<StockRequestDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(&format!(
        "UPDATE stock_request SET status = 'cancelled', updated_at = now() \
         WHERE id = $1 AND status = 'sent' \
         RETURNING {STOCK_COLUMNS}",
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        let exists = sqlx::query("SELECT 1 FROM stock_request WHERE id = $1")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        tx.rollback().await.ok();
        return Err(if exists.is_none() {
            AppError::NotFound
        } else {
            AppError::InvalidStatus
        });
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok(Json(stock_from_row(&row)?))
}

// ── Espace pharmacie ──────────────────────────────────────────────────────────

/// `GET /v1/pharmacy/stock-requests` — demandes reçues par la pharmacie.
pub async fn list_pharmacy_stock_requests(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
) -> Result<Json<StockRequestsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&format!(
        "SELECT {STOCK_COLUMNS} FROM stock_request ORDER BY created_at DESC LIMIT 200",
    ))
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(stock_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(StockRequestsResponse { data }))
}

/// Body optionnel de `POST /v1/pharmacy/stock-requests/{id}/reject`.
#[derive(Deserialize, Default)]
pub struct RespondStockBody {
    pub note: Option<String>,
}

async fn stock_response(
    state: &AppState,
    pharmacy_id: Uuid,
    id: Uuid,
    expected: &[&str],
    next: &str,
    note: Option<&str>,
) -> Result<StockRequestDto, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let expected_list = expected
        .iter()
        .map(|s| format!("'{s}'"))
        .collect::<Vec<_>>()
        .join(", ");
    let row = sqlx::query(&format!(
        "UPDATE stock_request \
         SET status = $2, response_note = COALESCE($3, response_note), updated_at = now() \
         WHERE id = $1 AND status IN ({expected_list}) \
         RETURNING {STOCK_COLUMNS}",
    ))
    .bind(id)
    .bind(next)
    .bind(note)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        let exists = sqlx::query("SELECT 1 FROM stock_request WHERE id = $1")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        tx.rollback().await.ok();
        return Err(if exists.is_none() {
            AppError::NotFound
        } else {
            AppError::InvalidStatus
        });
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;
    stock_from_row(&row)
}

/// `POST /v1/pharmacy/stock-requests/{id}/accept` — sent → accepted.
pub async fn accept_stock_request(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<StockRequestDto>, AppError> {
    let request =
        stock_response(&state, claims.pharmacy_id, id, &["sent"], "accepted", None).await?;
    Ok(Json(request))
}

/// `POST /v1/pharmacy/stock-requests/{id}/reject` — sent → rejected (note optionnelle).
pub async fn reject_stock_request(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
    Path(id): Path<Uuid>,
    body: Option<Json<RespondStockBody>>,
) -> Result<Json<StockRequestDto>, AppError> {
    let note = body.as_ref().and_then(|b| b.note.as_deref());
    let request =
        stock_response(&state, claims.pharmacy_id, id, &["sent"], "rejected", note).await?;
    Ok(Json(request))
}

/// `POST /v1/pharmacy/stock-requests/{id}/fulfill` — accepted → fulfilled.
pub async fn fulfill_stock_request(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<StockRequestDto>, AppError> {
    let request = stock_response(
        &state,
        claims.pharmacy_id,
        id,
        &["accepted"],
        "fulfilled",
        None,
    )
    .await?;
    Ok(Json(request))
}
