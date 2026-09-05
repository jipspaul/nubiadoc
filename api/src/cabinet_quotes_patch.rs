//! `PATCH /v1/cabinet/quotes/:id` — édition d'un devis `draft` (#4065, #4432).
//!
//! Extrait de `cabinet_quotes.rs` (CLAUDE.md plafond 700 lignes : ce fichier
//! était déjà à 601 lignes avant cette route) — même contrat/tenant que les
//! autres handlers `/v1/cabinet/quotes`.
//!
//! Quoi : remplace intégralement les lignes (`quote_item`) d'un devis
//! `draft` et recalcule `total_amount`, incrémente `version`.
//! Quand : édition d'un devis avant envoi au patient (doc12 §16).
//! Pourquoi cette approche : remplacement complet plutôt que diff ligne à
//! ligne — un devis n'a pas d'identité stable par ligne côté client (pas
//! d'UI d'édition ligne par ligne aujourd'hui), et ça réutilise directement
//! `validate_quote_items`/le pattern INSERT de `create_cabinet_quote`.
//! Modes d'échec : devis `sent`/`signed` → 409 `quote_locked` (#4432 : un
//! devis déjà envoyé a pu être vu par le patient — le muter romprait
//! l'intégrité du consentement à la signature, cf. `billing::sign_quote` qui
//! ne pin aucune version ; le trigger `enforce_quote_immutable`, migration
//! 0051, ne couvrait que `signed`) ; devis inexistant/hors tenant → 404 ;
//! lignes invalides → 422 (mêmes règles que la création).

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
#[serde(deny_unknown_fields)]
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

/// `PATCH /v1/cabinet/quotes/:id` — édite un devis tant qu'il est `draft`.
///
/// - Auth JWT pro `practitioner`/`admin` requis (doc12 §16) — `secretary` → 403.
/// - `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`.
/// - `items` remplace intégralement les lignes existantes (validation
///   identique à `create_cabinet_quote` : non vide, montants bornés, libellé
///   non blanc, `amo`/`amc` non négatifs) → 422 sinon.
/// - `deposit_pct` doit être entre 0 et 100 si fourni → 422 sinon.
/// - Devis inexistant/hors cabinet → 404.
/// - Devis `sent` ou `signed` → 409 `quote_locked` (#4432 : figer le montant
///   dès l'envoi au patient, pour que `sign` engage exactement ce qu'il a vu).
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

    let existing = sqlx::query(
        "SELECT status FROM quote WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    // #4432 : un devis `sent` (déjà vu par le patient) ne doit plus être
    // éditable — sinon `sign` fige silencieusement un montant que le
    // patient n'a jamais consenti. Seul `draft` reste éditable ; `signed`
    // est de toute façon bloqué par le trigger `enforce_quote_immutable`
    // plus bas, mais on le rejette ici aussi pour un message cohérent.
    let status: String = existing.try_get("status").map_err(|_| AppError::Internal)?;
    if status != "draft" {
        return Err(AppError::QuoteLocked);
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

    // #5733 puis #5749 : `QuoteItemInput` n'a pas d'identité stable par
    // ligne (cf. commentaire de module), mais le DELETE+INSERT ci-dessous
    // perdait systématiquement `phase_id` — une ligne rattachée à une phase
    // de plan de traitement (`treatment_phases::create_treatment_phase`) se
    // retrouvait détachée dès la moindre édition du devis, vidant
    // silencieusement la phase et son agrégat `total_cost_cents` côté plan.
    // On capture le `phase_id` des lignes existantes avant le DELETE et on
    // le reporte, au meilleur effort, sur la ligne du PATCH ayant le même
    // contenu STRUCTUREL (label/ccam/dent). #5733 incluait `amount_cents`
    // dans la clé de match, ce qui excluait de fait toute simple correction
    // de prix (le cas le plus fréquent en pratique) : une ligne identique en
    // tout sauf le montant n'est pas un changement structurel du point de
    // vue métier, donc `amount_cents` est exclu du matching ici.
    let old_item_rows = sqlx::query(
        "SELECT label, ccam_code, tooth, phase_id \
         FROM quote_item WHERE quote_id = $1",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    type OldItem = (String, Option<String>, Option<String>, Option<Uuid>);
    let mut old_items: Vec<OldItem> = Vec::with_capacity(old_item_rows.len());
    for row in &old_item_rows {
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        let ccam_code: Option<String> = row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
        let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
        let phase_id: Option<Uuid> = row.try_get("phase_id").map_err(|_| AppError::Internal)?;
        old_items.push((label, ccam_code, tooth, phase_id));
    }

    sqlx::query("DELETE FROM quote_item WHERE quote_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    for item in &body.items {
        let phase_id = old_items
            .iter()
            .position(|(label, ccam_code, tooth, _)| {
                label == &item.label && ccam_code == &item.ccam_code && tooth == &item.tooth
            })
            .and_then(|idx| old_items.remove(idx).3);

        sqlx::query(
            "INSERT INTO quote_item \
             (cabinet_id, quote_id, phase_id, label, unit_amount, ccam_code, tooth, amo_part, amc_part) \
             VALUES ($1, $2, $3, $4, $5::numeric / 100, $6, $7, $8::numeric / 100, $9::numeric / 100)",
        )
        .bind(claims.cabinet_id)
        .bind(id)
        .bind(phase_id)
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
