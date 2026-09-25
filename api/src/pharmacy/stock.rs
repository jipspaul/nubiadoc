//! Demandes de stock cabinet → pharmacie (lot B5).
//!
//! Espace cabinet : `POST|GET /v1/cabinet/stock-requests`,
//! `POST …/{id}/cancel` (tant que `sent`).
//! Espace pharmacie : `GET /v1/pharmacy/stock-requests`,
//! `POST …/{id}/accept|reject|fulfill`.
//! Les items sont du jsonb `[{label, qty, note?}]` — jamais de donnée patient.

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, Query, State},
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
///
/// `pharmacy_name`/`pharmacy_address`/`pharmacy_phone` (#6195, suite #5192) :
/// résolus en direct depuis `pharmacy` (pas de snapshot stocké, contrairement
/// à `cabinet_name`) — `None` si la pharmacie n'est plus listée (RLS
/// `pharmacy_public_read`), même réserve que `OrderDto::pharmacy_address`.
#[derive(Serialize)]
pub struct StockRequestDto {
    pub id: Uuid,
    pub pharmacy_id: Uuid,
    pub pharmacy_name: Option<String>,
    pub pharmacy_address: Option<serde_json::Value>,
    pub pharmacy_phone: Option<String>,
    pub cabinet_name: String,
    pub items: serde_json::Value,
    pub status: String,
    pub response_note: Option<String>,
    pub created_at: String,
    pub fulfilled_at: Option<String>,
}

const STOCK_COLUMNS: &str = "id, pharmacy_id, cabinet_name, items, status, response_note, \
     created_at, fulfilled_at, \
     (SELECT p.raison_sociale FROM pharmacy p WHERE p.id = stock_request.pharmacy_id) AS pharmacy_name, \
     (SELECT p.address FROM pharmacy p WHERE p.id = stock_request.pharmacy_id) AS pharmacy_address, \
     (SELECT p.phone FROM pharmacy p WHERE p.id = stock_request.pharmacy_id) AS pharmacy_phone";

fn stock_from_row(row: &PgRow) -> Result<StockRequestDto, AppError> {
    Ok(StockRequestDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        pharmacy_id: row.try_get("pharmacy_id").map_err(|_| AppError::Internal)?,
        pharmacy_name: row
            .try_get("pharmacy_name")
            .map_err(|_| AppError::Internal)?,
        pharmacy_address: row
            .try_get("pharmacy_address")
            .map_err(|_| AppError::Internal)?,
        pharmacy_phone: row
            .try_get("pharmacy_phone")
            .map_err(|_| AppError::Internal)?,
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
        fulfilled_at: row
            .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("fulfilled_at")
            .map_err(|_| AppError::Internal)?
            .map(|dt| dt.to_rfc3339()),
    })
}

/// Réponse liste : `{ data: [...] }`.
#[derive(Serialize)]
pub struct StockRequestsResponse {
    pub data: Vec<StockRequestDto>,
}

/// Paramètres de `GET /v1/cabinet/stock-requests` et `GET /v1/pharmacy/stock-requests`.
///
/// `limit` (défaut 200, max 500) et `offset` bornent le résultat (#7322 :
/// avant, `LIMIT 200` était codé en dur sans aucun paramètre accepté — les
/// lignes au-delà du plafond devenaient irrécupérables).
///
/// `status` filtre sur `VALID_STOCK_REQUEST_STATUSES`, `422` sinon (#7139 :
/// avant, `status` (même une valeur bidon) était silencieusement ignoré et
/// renvoyait toujours la même liste non filtrée).
#[derive(Deserialize)]
pub struct ListStockRequestsQuery {
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Énum `stock_request.status` (CHECK, migration 0125) — même doctrine que
/// `VALID_QUOTE_STATUSES` : une valeur hors énum → `422`, jamais une liste
/// silencieusement non filtrée (#7139).
const VALID_STOCK_REQUEST_STATUSES: [&str; 5] =
    ["sent", "accepted", "rejected", "fulfilled", "cancelled"];

// ── Espace cabinet ────────────────────────────────────────────────────────────

/// Une ligne du body de création.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct StockItemInput {
    pub label: String,
    pub qty: i64,
    pub note: Option<String>,
}

/// Body de `POST /v1/cabinet/stock-requests`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateStockRequestBody {
    pub pharmacy_id: Uuid,
    pub items: Vec<StockItemInput>,
}

/// Plafond métier réaliste (#7019) : la garde bornait déjà chaque item
/// (`qty <= 9999`, libellé non vide, NUL rejeté) mais jamais le NOMBRE
/// d'items — une demande de 1 000 lignes passait en 201 et le volet de
/// détail secrétariat les rendait toutes sans troncature, repoussant son
/// action principale à ~15 000 px sous le viewport. Un réassort cabinet →
/// officine dépasse rarement quelques dizaines de références.
pub(crate) const MAX_STOCK_REQUEST_ITEMS: usize = 200;

/// Plafonds de longueur (#7138) : la garde bornait déjà `qty`, le vide et le
/// NUL byte, mais jamais la longueur de `label`/`note` — un libellé de
/// 50 000 caractères et une note de 100 000 passaient en 201, persistaient
/// tels quels dans le JSONB et repartaient intégralement vers l'officine.
/// Mêmes ordres de grandeur que `MAX_QUOTE_ITEM_LABEL_LEN` (libellé d'article,
/// `cabinet_quotes.rs`) et `MAX_MOTIF_LEN` (note libre, `waiting_list.rs`).
pub(crate) const MAX_STOCK_ITEM_LABEL_LEN: usize = 500;
pub(crate) const MAX_STOCK_ITEM_NOTE_LEN: usize = 2_000;

/// `POST /v1/cabinet/stock-requests` — émet une demande vers une pharmacie
/// listée (404 sinon). Items vides, en nombre excessif, libellé vide, ou
/// libellé/note trop long → 422.
pub async fn create_stock_request(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateStockRequestBody>,
) -> Result<(StatusCode, Json<StockRequestDto>), AppError> {
    if body.items.is_empty()
        || body.items.len() > MAX_STOCK_REQUEST_ITEMS
        || body
            .items
            .iter()
            .any(|item| item.label.trim().is_empty() || item.qty <= 0 || item.qty > 9999)
    {
        return Err(AppError::ValidationError);
    }
    // #4600 : NUL byte non filtré → bind Postgres échoue, masqué en 500.
    for item in &body.items {
        crate::text_validation::reject_nul_byte(&item.label)?;
        crate::text_validation::validate_max_len(&item.label, MAX_STOCK_ITEM_LABEL_LEN)?;
        if let Some(note) = &item.note {
            crate::text_validation::reject_nul_byte(note)?;
            crate::text_validation::validate_max_len(note, MAX_STOCK_ITEM_NOTE_LEN)?;
        }
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

/// `GET /v1/cabinet/stock-requests?status=&limit=&offset=` — demandes émises par le
/// cabinet, triées `created_at DESC` (#7322).
pub async fn list_cabinet_stock_requests(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<ListStockRequestsQuery>,
) -> Result<Json<StockRequestsResponse>, AppError> {
    if let Some(ref status) = params.status {
        if !VALID_STOCK_REQUEST_STATUSES.contains(&status.as_str()) {
            return Err(AppError::ValidationError);
        }
    }
    let limit: i64 = params.limit.unwrap_or(200).clamp(1, 500);
    let offset: i64 = params.offset.unwrap_or(0).max(0);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = if let Some(status) = &params.status {
        sqlx::query(&format!(
            "SELECT {STOCK_COLUMNS} FROM stock_request WHERE status = $1 \
             ORDER BY created_at DESC LIMIT $2 OFFSET $3",
        ))
        .bind(status)
        .bind(limit)
        .bind(offset)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    } else {
        sqlx::query(&format!(
            "SELECT {STOCK_COLUMNS} FROM stock_request ORDER BY created_at DESC LIMIT $1 OFFSET $2",
        ))
        .bind(limit)
        .bind(offset)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    };
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(stock_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(StockRequestsResponse { data }))
}

/// `GET /v1/cabinet/stock-requests/{id}` — détail d'une demande de stock émise
/// par le cabinet (404 hors tenant). Ajoutée avec la pagination (#7322) : sans
/// cette route, une demande sortie de la page par écriture ultérieure était
/// définitivement irrécupérable.
pub async fn get_cabinet_stock_request(
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
        "SELECT {STOCK_COLUMNS} FROM stock_request WHERE id = $1",
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok(Json(stock_from_row(&row)?))
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

/// `POST /v1/cabinet/stock-requests/{id}/resend` — relance manuelle tant que
/// `sent` : renvoie la notification au staff pharmacie, sans changer de statut
/// (le geste quotidien de l'écran Stock — #5183).
pub async fn resend_stock_request(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
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
        "UPDATE stock_request SET updated_at = now() \
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

    let request = stock_from_row(&row)?;

    let staff = notify::notify_pharmacy_staff(
        &mut tx,
        request.pharmacy_id,
        "stock_request_received",
        "Relance : demande de stock",
        serde_json::json!({ "stock_request_id": request.id, "status": "sent" }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    for (app_user_id, notification_id) in staff {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("pharmacy_orders:{}", request.pharmacy_id),
        serde_json::json!({
            "channel": format!("pharmacy_orders:{}", request.pharmacy_id),
            "event": "stock_request_received",
            "data": { "stock_request_id": request.id, "status": "sent" }
        })
        .to_string(),
    );

    Ok(Json(request))
}

// ── Espace pharmacie ──────────────────────────────────────────────────────────

/// `GET /v1/pharmacy/stock-requests?status=&limit=&offset=` — demandes reçues par la
/// pharmacie, triées `created_at DESC` (#7322).
pub async fn list_pharmacy_stock_requests(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
    Query(params): Query<ListStockRequestsQuery>,
) -> Result<Json<StockRequestsResponse>, AppError> {
    if let Some(ref status) = params.status {
        if !VALID_STOCK_REQUEST_STATUSES.contains(&status.as_str()) {
            return Err(AppError::ValidationError);
        }
    }
    let limit: i64 = params.limit.unwrap_or(200).clamp(1, 500);
    let offset: i64 = params.offset.unwrap_or(0).max(0);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = if let Some(status) = &params.status {
        sqlx::query(&format!(
            "SELECT {STOCK_COLUMNS} FROM stock_request WHERE status = $1 \
             ORDER BY created_at DESC LIMIT $2 OFFSET $3",
        ))
        .bind(status)
        .bind(limit)
        .bind(offset)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    } else {
        sqlx::query(&format!(
            "SELECT {STOCK_COLUMNS} FROM stock_request ORDER BY created_at DESC LIMIT $1 OFFSET $2",
        ))
        .bind(limit)
        .bind(offset)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    };
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(stock_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(StockRequestsResponse { data }))
}

/// Body de `POST /v1/pharmacy/stock-requests/{id}/accept|reject`
/// (optionnel pour `accept`, `note` obligatoire pour `reject`).
#[derive(Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct RespondStockBody {
    pub note: Option<String>,
}

/// Cabinet notifié de la réponse officine — praticien + secrétariat, même
/// périmètre que `QUOTE_SIGNED_NOTIFY_ROLES`/`MESSAGE_RECEIVED_NOTIFY_ROLES`
/// (billing.rs/messaging.rs) : ce sont les rôles qui émettent la demande
/// initiale (`create_stock_request` requiert `ProSecretaryPlusClaims`).
const STOCK_REQUEST_ANSWERED_NOTIFY_ROLES: [&str; 2] = ["practitioner", "secretary"];

fn stock_response_title(next: &str) -> &'static str {
    match next {
        "accepted" => "Demande de stock acceptée",
        "rejected" => "Demande de stock refusée",
        "fulfilled" => "Demande de stock honorée",
        _ => "Réponse à une demande de stock",
    }
}

/// Tronc commun de `accept|reject|fulfill_stock_request`. Notifie le cabinet
/// de la réponse (#7017 : jusqu'ici seul l'aller cabinet → pharmacie était
/// notifié via `notify_pharmacy_staff`, le retour officine → cabinet ne
/// créait aucune notification et le secrétariat n'apprenait un refus qu'en
/// rouvrant l'écran Stock).
#[allow(clippy::too_many_arguments)]
async fn stock_response(
    state: &AppState,
    hub: &WsHub,
    dispatcher: &Arc<dyn JobDispatcher>,
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
         SET status = $2, response_note = COALESCE($3, response_note), \
             fulfilled_at = CASE WHEN $2 = 'fulfilled' THEN now() ELSE fulfilled_at END, \
             updated_at = now() \
         WHERE id = $1 AND status IN ({expected_list}) \
         RETURNING {STOCK_COLUMNS}, cabinet_id",
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

    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let request = stock_from_row(&row)?;

    let staff = notify::notify_cabinet_staff(
        &mut tx,
        cabinet_id,
        &STOCK_REQUEST_ANSWERED_NOTIFY_ROLES,
        "stock_request_answered",
        stock_response_title(next),
        serde_json::json!({ "stock_request_id": request.id, "status": next }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    for (app_user_id, notification_id) in staff {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("cabinet_stock_requests:{cabinet_id}"),
        serde_json::json!({
            "channel": format!("cabinet_stock_requests:{cabinet_id}"),
            "event": "stock_request_answered",
            "data": { "stock_request_id": request.id, "status": next }
        })
        .to_string(),
    );

    Ok(request)
}

/// `POST /v1/pharmacy/stock-requests/{id}/accept` — sent → accepted (note optionnelle).
pub async fn accept_stock_request(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PharmaMemberClaims,
    Path(id): Path<Uuid>,
    body: Option<Json<RespondStockBody>>,
) -> Result<Json<StockRequestDto>, AppError> {
    let note = body.as_ref().and_then(|b| b.note.as_deref());
    let request = stock_response(
        &state,
        &hub,
        &dispatcher,
        claims.pharmacy_id,
        id,
        &["sent"],
        "accepted",
        note,
    )
    .await?;
    Ok(Json(request))
}

/// `POST /v1/pharmacy/stock-requests/{id}/reject` — sent → rejected.
/// Motif obligatoire → 422 si absent/vide (même règle que `reject_pharmacy_order`).
pub async fn reject_stock_request(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PharmaMemberClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<RespondStockBody>,
) -> Result<Json<StockRequestDto>, AppError> {
    let note = body.note.as_deref().unwrap_or("").trim();
    if note.is_empty() {
        return Err(AppError::ValidationError);
    }
    let request = stock_response(
        &state,
        &hub,
        &dispatcher,
        claims.pharmacy_id,
        id,
        &["sent"],
        "rejected",
        Some(note),
    )
    .await?;
    Ok(Json(request))
}

/// `POST /v1/pharmacy/stock-requests/{id}/fulfill` — accepted → fulfilled.
pub async fn fulfill_stock_request(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PharmaMemberClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<StockRequestDto>, AppError> {
    let request = stock_response(
        &state,
        &hub,
        &dispatcher,
        claims.pharmacy_id,
        id,
        &["accepted"],
        "fulfilled",
        None,
    )
    .await?;
    Ok(Json(request))
}
