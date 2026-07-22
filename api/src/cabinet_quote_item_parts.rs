//! `PATCH /v1/cabinet/quotes/:id/items/:item_id/parts` — réaffectation
//! manuelle AMO/AMC après retour de remboursement (#4069).
//!
//! Quoi : corrige `quote_item.amo_part`/`amc_part` d'une ligne facturée
//! quand le remboursement réel (retour NOEMIE) diffère de l'estimation
//! initiale (#4062 : estimation automatique à 70% du tarif de référence,
//! jamais garantie exacte). Trace l'ancien et le nouveau montant dans
//! `audit_log` (append-only, `metadata` jsonb).
//! Quand : après clôture/signature d'un devis — DÉLIBÉRÉMENT indépendant du
//! statut `quote.status` (fonctionne sur un devis `signed`) : cette route ne
//! touche que `quote_item`, jamais `quote`, donc le trigger
//! `enforce_quote_immutable` (migration 0051, ne porte que sur `quote`) ne
//! s'applique pas ici — c'est exactement le point de l'issue (corriger
//! après coup un devis déjà signé, cité comme point de veto démo).
//! Pourquoi un module dédié : `cabinet_quotes.rs` était déjà à 604 lignes
//! (CLAUDE.md plafond 700), même pattern que `cabinet_quotes_patch.rs`.
//! Modes d'échec : ligne inexistante/hors devis/hors cabinet → 404 ; aucun
//! des deux champs fourni ou valeur négative → 422.

use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Body de `PATCH /v1/cabinet/quotes/:id/items/:item_id/parts`. Au moins un
/// des deux champs doit être fourni ; l'autre reste inchangé.
#[derive(Deserialize)]
pub struct PatchQuoteItemPartsBody {
    pub amo_part_cents: Option<i64>,
    pub amc_part_cents: Option<i64>,
}

/// Réponse de `PATCH /v1/cabinet/quotes/:id/items/:item_id/parts`.
#[derive(Serialize)]
pub struct PatchQuoteItemPartsResponse {
    pub item_id: Uuid,
    pub amo_part_cents: i64,
    pub amc_part_cents: i64,
}

/// `PATCH /v1/cabinet/quotes/:id/items/:item_id/parts` — réaffecte
/// manuellement `amo_part`/`amc_part` d'une ligne de devis.
///
/// - Auth JWT pro `practitioner`/`secretary`/`admin`/`manager` requis.
/// - `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`.
/// - Au moins un des deux champs doit être fourni, tous deux ≥ 0 → 422 sinon.
/// - Leur somme (après application, l'autre champ non fourni gardant sa
///   valeur actuelle) ne doit pas dépasser le montant de la ligne → 422
///   sinon (#4309) — sinon le reste à charge patient devient négatif.
/// - Ligne inexistante, hors devis (`:id`) ou hors cabinet → 404.
/// - Fonctionne quel que soit `quote.status` (y compris `signed`) : voir
///   commentaire de module.
/// - Trace `{old,new}_{amo,amc}_part_cents` dans `audit_log.metadata`
///   (action `reallocate_quote_item_parts`, append-only).
pub async fn patch_quote_item_parts(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path((quote_id, item_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<PatchQuoteItemPartsBody>,
) -> Result<Json<PatchQuoteItemPartsResponse>, AppError> {
    if body.amo_part_cents.is_none() && body.amc_part_cents.is_none() {
        return Err(AppError::ValidationError);
    }
    if body.amo_part_cents.is_some_and(|v| v < 0) || body.amc_part_cents.is_some_and(|v| v < 0) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let before = sqlx::query(
        "SELECT (amo_part * 100)::bigint AS amo_part_cents, \
                (amc_part * 100)::bigint AS amc_part_cents, \
                (qty * unit_amount * 100)::bigint AS amount_cents \
         FROM quote_item \
         WHERE id = $1 AND quote_id = $2 AND cabinet_id = $3",
    )
    .bind(item_id)
    .bind(quote_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let old_amo_part_cents: Option<i64> = before.try_get("amo_part_cents").ok();
    let old_amc_part_cents: Option<i64> = before.try_get("amc_part_cents").ok();
    let amount_cents: i64 = before
        .try_get("amount_cents")
        .map_err(|_| AppError::Internal)?;

    // #4309 : la somme effective (champ patché ou valeur inchangée pour
    // l'autre) ne doit pas dépasser le montant de la ligne.
    let effective_amo = body
        .amo_part_cents
        .unwrap_or(old_amo_part_cents.unwrap_or(0));
    let effective_amc = body
        .amc_part_cents
        .unwrap_or(old_amc_part_cents.unwrap_or(0));
    if effective_amo + effective_amc > amount_cents {
        return Err(AppError::ValidationError);
    }

    let updated = sqlx::query(
        "UPDATE quote_item \
         SET amo_part = coalesce($1::numeric / 100, amo_part), \
             amc_part = coalesce($2::numeric / 100, amc_part) \
         WHERE id = $3 \
         RETURNING (amo_part * 100)::bigint AS amo_part_cents, \
                    (amc_part * 100)::bigint AS amc_part_cents",
    )
    .bind(body.amo_part_cents)
    .bind(body.amc_part_cents)
    .bind(item_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let new_amo_part_cents: Option<i64> = updated.try_get("amo_part_cents").ok();
    let new_amc_part_cents: Option<i64> = updated.try_get("amc_part_cents").ok();

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, $3, 'reallocate_quote_item_parts', 'quote_item', $4, $5)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(item_id)
    .bind(serde_json::json!({
        "quote_id": quote_id,
        "old_amo_part_cents": old_amo_part_cents,
        "new_amo_part_cents": new_amo_part_cents,
        "old_amc_part_cents": old_amc_part_cents,
        "new_amc_part_cents": new_amc_part_cents,
    }))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %claims.sub,
        cabinet_id = %claims.cabinet_id,
        quote_id = %quote_id,
        item_id = %item_id,
        "quote item parts reallocated"
    );

    Ok(Json(PatchQuoteItemPartsResponse {
        item_id,
        amo_part_cents: new_amo_part_cents.unwrap_or(0),
        amc_part_cents: new_amc_part_cents.unwrap_or(0),
    }))
}
