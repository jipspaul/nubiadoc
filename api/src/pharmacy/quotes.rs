//! Devis d'officine (lot B7) — produits + prix TTC en centimes, distinct du
//! devis dentaire (`quote` : CCAM/AMO/AMC, eIDAS).
//!
//! Espace pharmacie : `GET|POST /v1/pharmacy/quotes`, `POST …/{id}/send`
//! (pharmacist/admin). Espace patient : `GET /v1/account/pharmacy-quotes`,
//! `POST …/{id}/accept|refuse`.

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
    auth::{AppError, PatientAccountClaims, PharmaMemberClaims, PharmaPharmacistClaims},
    notify,
    realtime::WsHub,
    AppState, JobDispatcher,
};

// ── DTO ───────────────────────────────────────────────────────────────────────

/// Un devis d'officine dans les réponses API (mêmes clés des deux bords).
#[derive(Serialize)]
pub struct QuoteDto {
    pub id: Uuid,
    pub pharmacy_id: Uuid,
    pub pharmacy_name: String,
    pub patient_display_name: String,
    pub order_id: Option<Uuid>,
    pub items: serde_json::Value,
    pub total_cents: i64,
    pub status: String,
    pub created_at: String,
    pub sent_at: Option<String>,
    pub decided_at: Option<String>,
}

const QUOTE_COLUMNS: &str = "id, pharmacy_id, pharmacy_name, patient_display_name, order_id, \
     items, total_cents, status, created_at, sent_at, decided_at";

fn quote_from_row(row: &PgRow) -> Result<QuoteDto, AppError> {
    let to_rfc3339 = |value: chrono::DateTime<chrono::Utc>| value.to_rfc3339();
    Ok(QuoteDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        pharmacy_id: row.try_get("pharmacy_id").map_err(|_| AppError::Internal)?,
        pharmacy_name: row
            .try_get("pharmacy_name")
            .map_err(|_| AppError::Internal)?,
        patient_display_name: row
            .try_get("patient_display_name")
            .map_err(|_| AppError::Internal)?,
        order_id: row.try_get("order_id").map_err(|_| AppError::Internal)?,
        items: row.try_get("items").map_err(|_| AppError::Internal)?,
        total_cents: row.try_get("total_cents").map_err(|_| AppError::Internal)?,
        status: row.try_get("status").map_err(|_| AppError::Internal)?,
        created_at: to_rfc3339(row.try_get("created_at").map_err(|_| AppError::Internal)?),
        sent_at: row
            .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("sent_at")
            .map_err(|_| AppError::Internal)?
            .map(to_rfc3339),
        decided_at: row
            .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("decided_at")
            .map_err(|_| AppError::Internal)?
            .map(to_rfc3339),
    })
}

/// Réponse liste : `{ data: [...] }`.
#[derive(Serialize)]
pub struct QuotesResponse {
    pub data: Vec<QuoteDto>,
}

// ── Espace pharmacie ──────────────────────────────────────────────────────────

/// Une ligne du body de création.
#[derive(Deserialize)]
pub struct QuoteItemInput {
    pub label: String,
    pub qty: i64,
    pub unit_price_cents: i64,
}

/// Body de `POST /v1/pharmacy/quotes`.
#[derive(Deserialize)]
pub struct CreateQuoteBody {
    /// Commande à laquelle rattacher le devis (l'identité patient en découle).
    pub order_id: Uuid,
    pub items: Vec<QuoteItemInput>,
}

/// `POST /v1/pharmacy/quotes` — crée un devis (statut `draft`) rattaché à une
/// commande de la pharmacie (404 hors tenant). Items vides, libellé vide,
/// quantité ou prix négatif → 422. Le total est calculé côté serveur.
/// Commande d'ancrage hors statut actif (`received`/`preparing`/`ready`) —
/// donc `picked_up`/`cancelled`/`rejected` → 409 `invalid_status` (#4415).
pub async fn create_pharmacy_quote(
    State(state): State<AppState>,
    claims: PharmaPharmacistClaims,
    Json(body): Json<CreateQuoteBody>,
) -> Result<(StatusCode, Json<QuoteDto>), AppError> {
    const MAX_QTY: i64 = 1_000_000;
    const MAX_UNIT_PRICE_CENTS: i64 = 100_000_000;

    if body.items.is_empty()
        || body.items.iter().any(|item| {
            item.label.trim().is_empty()
                || item.qty <= 0
                || item.qty > MAX_QTY
                || item.unit_price_cents < 0
                || item.unit_price_cents > MAX_UNIT_PRICE_CENTS
        })
    {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // La commande ancre le devis : identité patient et nom dénormalisés.
    let order = sqlx::query(
        "SELECT patient_account_id, pharmacy_name, patient_display_name, status \
         FROM pharmacy_order WHERE id = $1",
    )
    .bind(body.order_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    // #4415 : une commande terminale (picked_up/cancelled/rejected) ne doit
    // plus pouvoir ancrer un nouveau devis payable — sinon un devis peut
    // être créé, envoyé, accepté et payé sur une commande jamais délivrée
    // (charge fantôme) ou déjà retirée.
    let order_status: String = order.try_get("status").map_err(|_| AppError::Internal)?;
    if !matches!(order_status.as_str(), "received" | "preparing" | "ready") {
        return Err(AppError::InvalidStatus);
    }

    let patient_account_id: Uuid = order
        .try_get("patient_account_id")
        .map_err(|_| AppError::Internal)?;
    let pharmacy_name: String = order
        .try_get("pharmacy_name")
        .map_err(|_| AppError::Internal)?;
    let patient_display_name: String = order
        .try_get("patient_display_name")
        .map_err(|_| AppError::Internal)?;

    let total_cents: i64 = body
        .items
        .iter()
        .try_fold(0i64, |acc, item| {
            item.qty
                .checked_mul(item.unit_price_cents)
                .and_then(|line_total| acc.checked_add(line_total))
        })
        .ok_or(AppError::ValidationError)?;
    let items = serde_json::json!(body
        .items
        .iter()
        .map(|item| {
            serde_json::json!({
                "label": item.label.trim(),
                "qty": item.qty,
                "unit_price_cents": item.unit_price_cents,
            })
        })
        .collect::<Vec<_>>());

    let row = sqlx::query(&format!(
        "INSERT INTO pharmacy_quote \
         (pharmacy_id, patient_account_id, order_id, pharmacy_name, \
          patient_display_name, items, total_cents) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) \
         RETURNING {QUOTE_COLUMNS}",
    ))
    .bind(claims.pharmacy_id)
    .bind(patient_account_id)
    .bind(body.order_id)
    .bind(&pharmacy_name)
    .bind(&patient_display_name)
    .bind(&items)
    .bind(total_cents)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok((StatusCode::CREATED, Json(quote_from_row(&row)?)))
}

/// `GET /v1/pharmacy/quotes` — devis de la pharmacie (brouillons compris).
pub async fn list_pharmacy_quotes(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
) -> Result<Json<QuotesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&format!(
        "SELECT {QUOTE_COLUMNS} FROM pharmacy_quote ORDER BY created_at DESC LIMIT 200",
    ))
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(quote_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(QuotesResponse { data }))
}

/// `POST /v1/pharmacy/quotes/{id}/send` — draft → sent (pharmacist/admin).
/// Notifie le patient (sans PII) et publie sur son canal WS.
pub async fn send_pharmacy_quote(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PharmaPharmacistClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<QuoteDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(&format!(
        "UPDATE pharmacy_quote SET status = 'sent', sent_at = now(), updated_at = now() \
         WHERE id = $1 AND status = 'draft' \
         RETURNING {QUOTE_COLUMNS}",
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        let exists = sqlx::query("SELECT 1 FROM pharmacy_quote WHERE id = $1")
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

    let quote = quote_from_row(&row)?;

    let patient_account_id: Uuid =
        sqlx::query("SELECT patient_account_id FROM pharmacy_quote WHERE id = $1")
            .bind(id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .try_get("patient_account_id")
            .map_err(|_| AppError::Internal)?;

    // Notification patient (zéro PII — lot B4).
    let pushed = notify::notify_patient_account(
        &mut tx,
        patient_account_id,
        "pharmacy_quote_sent",
        "Un devis vous attend",
        serde_json::json!({ "pharmacy_quote_id": id, "status": "sent" }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    if let Some((app_user_id, notification_id)) = pushed {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("account_orders:{patient_account_id}"),
        serde_json::json!({
            "channel": format!("account_orders:{patient_account_id}"),
            "event": "pharmacy_quote_sent",
            "data": { "pharmacy_quote_id": id, "status": "sent" }
        })
        .to_string(),
    );

    Ok(Json(quote))
}

// ── Espace patient ────────────────────────────────────────────────────────────

/// `GET /v1/account/pharmacy-quotes` — devis reçus (jamais les brouillons, RLS).
pub async fn list_account_pharmacy_quotes(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<QuotesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&format!(
        "SELECT {QUOTE_COLUMNS} FROM pharmacy_quote ORDER BY created_at DESC LIMIT 100",
    ))
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(quote_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(QuotesResponse { data }))
}

async fn decide_quote(
    state: &AppState,
    hub: &WsHub,
    dispatcher: &Arc<dyn JobDispatcher>,
    account_id: Uuid,
    id: Uuid,
    decision: &str,
) -> Result<QuoteDto, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // #4415/#5476 : la commande ancre doit rester active (received/preparing/
    // ready) au moment de la décision — sinon un devis envoyé avant un rejet
    // de commande resterait acceptable (puis payable) sur une commande jamais
    // délivrée (charge fantôme).
    let row = sqlx::query(&format!(
        "UPDATE pharmacy_quote \
         SET status = $2, decided_at = now(), updated_at = now() \
         WHERE id = $1 AND status = 'sent' \
         AND EXISTS ( \
             SELECT 1 FROM pharmacy_order po \
             WHERE po.id = pharmacy_quote.order_id \
             AND po.status IN ('received', 'preparing', 'ready') \
         ) \
         RETURNING {QUOTE_COLUMNS}",
    ))
    .bind(id)
    .bind(decision)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        let exists = sqlx::query("SELECT 1 FROM pharmacy_quote WHERE id = $1")
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

    let quote = quote_from_row(&row)?;

    // Notification du staff pharmacie — la pharmacie doit savoir que le
    // patient a décidé (symétrique de la notification patient dans
    // `send_pharmacy_quote`, jusqu'ici absente : voir #3505).
    let title = if decision == "accepted" {
        "Devis accepté par le patient"
    } else {
        "Devis refusé par le patient"
    };
    let staff = notify::notify_pharmacy_staff(
        &mut tx,
        quote.pharmacy_id,
        "pharmacy_quote_decided",
        title,
        serde_json::json!({ "pharmacy_quote_id": id, "status": decision }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    for (app_user_id, notification_id) in staff {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("pharmacy_orders:{}", quote.pharmacy_id),
        serde_json::json!({
            "channel": format!("pharmacy_orders:{}", quote.pharmacy_id),
            "event": "pharmacy_quote_decided",
            "data": { "pharmacy_quote_id": id, "status": decision }
        })
        .to_string(),
    );

    Ok(quote)
}

/// `POST /v1/account/pharmacy-quotes/{id}/accept` — sent → accepted.
/// Notifie le staff pharmacie de la décision (lot B4).
pub async fn accept_pharmacy_quote(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<QuoteDto>, AppError> {
    let quote = decide_quote(&state, &hub, &dispatcher, claims.account_id, id, "accepted").await?;
    Ok(Json(quote))
}

/// `POST /v1/account/pharmacy-quotes/{id}/refuse` — sent → refused.
/// Notifie le staff pharmacie de la décision (lot B4).
pub async fn refuse_pharmacy_quote(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<QuoteDto>, AppError> {
    let quote = decide_quote(&state, &hub, &dispatcher, claims.account_id, id, "refused").await?;
    Ok(Json(quote))
}
