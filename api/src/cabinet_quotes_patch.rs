//! `PATCH /v1/cabinet/quotes/:id` — édition d'un devis non signé (#4065).
//!
//! Extrait de `cabinet_quotes.rs` (CLAUDE.md plafond 700 lignes : ce fichier
//! était déjà à 601 lignes avant cette route) — même contrat/tenant que les
//! autres handlers `/v1/cabinet/quotes`.
//!
//! Quoi : remplace intégralement les lignes (`quote_item`) d'un devis
//! `draft`/`sent` et recalcule `total_amount`, incrémente `version`.
//! Quand : édition d'un devis avant envoi/signature (doc12 §16).
//! Pourquoi cette approche : remplacement complet plutôt que diff ligne à
//! ligne — un devis n'a pas d'identité stable par ligne côté client (pas
//! d'UI d'édition ligne par ligne aujourd'hui), et ça réutilise directement
//! `validate_quote_items`/le pattern INSERT de `create_cabinet_quote`.
//! Modes d'échec : devis signé → 409 `quote_locked` (trigger
//! `enforce_quote_immutable`, migration 0051) ; devis inexistant/hors
//! tenant → 404 ; lignes invalides → 422 (mêmes règles que la création).

use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    cabinet_quotes::{validate_quote_items, QuoteItemInput},
    AppState,
};

/// Body de `PATCH /v1/cabinet/quotes/:id`. Mêmes lignes que la création
/// (remplacement complet) ; `deposit_pct` inchangé si absent.
#[derive(Deserialize)]
pub struct PatchCabinetQuoteBody {
    pub items: Vec<QuoteItemInput>,
    pub deposit_pct: Option<f64>,
}

/// Réponse de `PATCH /v1/cabinet/quotes/:id`.
#[derive(Serialize)]
pub struct PatchCabinetQuoteResponse {
    pub quote_id: Uuid,
    pub version: i32,
    pub total_amount_cents: i64,
}

/// `PATCH /v1/cabinet/quotes/:id` — édite un devis tant qu'il n'est pas signé.
///
/// - Auth JWT pro `practitioner`/`admin` requis (doc12 §16) — `secretary` → 403.
/// - `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`.
/// - `items` remplace intégralement les lignes existantes (validation
///   identique à `create_cabinet_quote` : non vide, montants bornés, libellé
///   non blanc, `amo`/`amc` non négatifs) → 422 sinon.
/// - `deposit_pct` doit être entre 0 et 100 si fourni → 422 sinon.
/// - Devis inexistant/hors cabinet → 404.
/// - Devis signé (`enforce_quote_immutable`, migration 0051) → 409 `quote_locked`.
/// - `version` incrémentée à chaque édition acceptée.
pub async fn patch_cabinet_quote(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchCabinetQuoteBody>,
) -> Result<Json<PatchCabinetQuoteResponse>, AppError> {
    validate_quote_items(&body.items)?;
    if let Some(pct) = body.deposit_pct {
        if !(0.0..=100.0).contains(&pct) {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let exists =
        sqlx::query("SELECT 1 FROM quote WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL")
            .bind(id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if exists.is_none() {
        return Err(AppError::NotFound);
    }

    let total_cents: i64 = body.items.iter().map(|i| i.amount_cents).sum();

    // UPDATE quote D'ABORD : déclenche enforce_quote_immutable (migration
    // 0051, → 409 quote_locked) avant de toucher aux quote_item — sur un
    // devis signé, on ne veut pas avoir déjà supprimé les lignes existantes
    // quand l'échec survient (le trigger ne porte que sur `quote`, pas
    // `quote_item` ; échouer tôt évite un aller-retour DELETE/INSERT inutile
    // avant le rollback transactionnel).
    let updated = sqlx::query(
        "UPDATE quote \
         SET total_amount = $1::numeric / 100, \
             deposit_pct = coalesce($2, deposit_pct), \
             version = version + 1, \
             updated_at = now() \
         WHERE id = $3 AND cabinet_id = $4 \
         RETURNING version",
    )
    .bind(total_cents)
    .bind(body.deposit_pct)
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match e {
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("P0001") => {
            AppError::QuoteLocked
        }
        _ => AppError::Internal,
    })?;

    let version: i32 = updated.try_get("version").map_err(|_| AppError::Internal)?;

    // Remplace les lignes existantes (#4065 : pas d'identité stable par ligne
    // côté client aujourd'hui, cf. commentaire de module).
    sqlx::query("DELETE FROM quote_item WHERE quote_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    for item in &body.items {
        sqlx::query(
            "INSERT INTO quote_item \
             (cabinet_id, quote_id, label, unit_amount, ccam_code, tooth, amo_part, amc_part) \
             VALUES ($1, $2, $3, $4::numeric / 100, $5, $6, $7::numeric / 100, $8::numeric / 100)",
        )
        .bind(claims.cabinet_id)
        .bind(id)
        .bind(&item.label)
        .bind(item.amount_cents)
        .bind(&item.ccam_code)
        .bind(&item.tooth)
        .bind(item.amo_part_cents)
        .bind(item.amc_part_cents)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %claims.sub,
        cabinet_id = %claims.cabinet_id,
        quote_id = %id,
        version,
        "cabinet quote patched"
    );

    Ok(Json(PatchCabinetQuoteResponse {
        quote_id: id,
        version,
        total_amount_cents: total_cents,
    }))
}
