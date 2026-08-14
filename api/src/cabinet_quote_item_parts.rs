//! `PATCH /v1/cabinet/quotes/:id/items/:item_id/parts` — réaffectation
//! manuelle AMO/AMC après retour de remboursement (#4069).
//!
//! Quoi : corrige `quote_item.amo_part`/`amc_part` d'une ligne facturée
//! quand le remboursement réel (retour NOEMIE) diffère de l'estimation
//! initiale (#4062 : estimation automatique à 70% du tarif de référence,
//! jamais garantie exacte). Trace l'ancien et le nouveau montant dans
//! `audit_log` (append-only, `metadata` jsonb).
//! Quand : après clôture/signature d'un devis — reste possible sur un devis
//! `sent` ou `signed` (cette route ne touche que `quote_item`, jamais
//! `quote`, donc le trigger `enforce_quote_immutable`, migration 0051, ne
//! s'applique pas ici), MAIS bornée : sur un devis non-`draft`, la part
//! patient de la ligne (`amount − amo_part − amc_part`) ne peut pas
//! AUGMENTER par rapport à sa valeur au moment de l'appel → 409
//! `quote_locked` sinon (#4873, #5473). Sans ça, réduire
//! `amo_part`/`amc_part` après envoi/signature fait grimper le reste à
//! charge au-delà de ce que le patient a vu/consenti, alors que tous les
//! plafonds de paiement (`billing_payments.rs`,
//! `cabinet_payments_manual.rs`, `payment_schedules.rs`) recalculent la part
//! patient en direct depuis `quote_item`.
//! Pourquoi un module dédié : `cabinet_quotes.rs` était déjà à 604 lignes
//! (CLAUDE.md plafond 700), même pattern que `cabinet_quotes_patch.rs`.
//! Modes d'échec : ligne inexistante/hors devis/hors cabinet → 404 ; aucun
//! des deux champs fourni ou valeur négative → 422 ; somme > montant ligne
//! → 422 ; devis non-`draft` (`sent`/`signed`) et part patient de la ligne
//! en hausse → 409.

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
/// - Fonctionne quel que soit `quote.status`, mais si non-`draft`
///   (`sent`/`signed`), la part patient de la ligne ne peut pas augmenter
///   par rapport à sa valeur actuelle → 409 `quote_locked` sinon (#4873,
///   #5473, voir commentaire de module).
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
        "SELECT (qi.amo_part * 100)::bigint AS amo_part_cents, \
                (qi.amc_part * 100)::bigint AS amc_part_cents, \
                (qi.qty * qi.unit_amount * 100)::bigint AS amount_cents, \
                q.status AS quote_status \
         FROM quote_item qi \
         JOIN quote q ON q.id = qi.quote_id \
         WHERE qi.id = $1 AND qi.quote_id = $2 AND qi.cabinet_id = $3",
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
    let quote_status: String = before
        .try_get("quote_status")
        .map_err(|_| AppError::Internal)?;

    let old_amo = old_amo_part_cents.unwrap_or(0);
    let old_amc = old_amc_part_cents.unwrap_or(0);

    // #4309 : la somme effective (champ patché ou valeur inchangée pour
    // l'autre) ne doit pas dépasser le montant de la ligne.
    let effective_amo = body.amo_part_cents.unwrap_or(old_amo);
    let effective_amc = body.amc_part_cents.unwrap_or(old_amc);
    if effective_amo + effective_amc > amount_cents {
        return Err(AppError::ValidationError);
    }

    // #4873/#5473 : un devis `sent` (déjà vu par le patient, #4432) ou
    // `signed` fige le reste à charge consenti par le patient.
    // `enforce_quote_immutable` (migration 0051) ne porte que sur `quote`,
    // pas `quote_item` — sans ce garde-fou, réduire amo/amc_part sur un
    // devis `sent` ou `signed` ferait grimper la part patient recalculée en
    // direct par tous les plafonds de paiement, au-delà de ce que le
    // patient a vu/consenti. Les corrections qui baissent (ou laissent
    // inchangée) la part patient de la ligne restent autorisées (#4069),
    // et `draft` reste librement éditable.
    if quote_status != "draft" {
        let old_patient_share = amount_cents - old_amo - old_amc;
        let new_patient_share = amount_cents - effective_amo - effective_amc;
        if new_patient_share > old_patient_share {
            return Err(AppError::QuoteLocked);
        }
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
