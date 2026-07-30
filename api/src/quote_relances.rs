//! Handler `GET /v1/cabinet/quotes/:id/relances` — historique de relance
//! d'un devis (#4126). Fichier dédié plutôt qu'ajouté à `cabinet_quotes.rs`
//! (déjà au plafond absolu CLAUDE.md, 700+ lignes).

use axum::{
    extract::{Path, State},
    Json,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Une relance enregistrée (`quote_relance`, migration 0207).
#[derive(Serialize)]
pub struct QuoteRelanceItem {
    pub milestone: String,
    pub sent_at: String,
}

/// Réponse de `GET /v1/cabinet/quotes/:id/relances`.
#[derive(Serialize)]
pub struct QuoteRelancesResponse {
    pub data: Vec<QuoteRelanceItem>,
}

/// `GET /v1/cabinet/quotes/:id/relances` — historique de relance J+3/J+7
/// d'un devis (#4126).
///
/// Praticien/secrétaire (`ProSecretaryPlusClaims`) — `cabinet_id` extrait du
/// JWT. Devis inexistant ou hors tenant → `404`. Trié `sent_at ASC`
/// (chronologique : `j3` avant `j7`). Aucune relance encore envoyée →
/// `{ data: [] }`.
pub async fn list_quote_relances(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(quote_id): Path<Uuid>,
) -> Result<Json<QuoteRelancesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let quote_exists =
        sqlx::query("SELECT 1 FROM quote WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL")
            .bind(quote_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if quote_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let rows = sqlx::query(
        "SELECT milestone, sent_at FROM quote_relance \
         WHERE quote_id = $1 AND cabinet_id = $2 \
         ORDER BY sent_at ASC",
    )
    .bind(quote_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data: Vec<QuoteRelanceItem> = Vec::with_capacity(rows.len());
    for row in rows {
        let milestone: String = row.try_get("milestone").map_err(|_| AppError::Internal)?;
        let sent_at: chrono::DateTime<chrono::Utc> =
            row.try_get("sent_at").map_err(|_| AppError::Internal)?;
        data.push(QuoteRelanceItem {
            milestone,
            sent_at: sent_at.to_rfc3339(),
        });
    }

    Ok(Json(QuoteRelancesResponse { data }))
}
