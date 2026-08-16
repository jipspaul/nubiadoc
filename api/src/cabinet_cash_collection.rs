//! `GET /v1/cabinet/cash-collection/today` (#5591, contrat front #5382) —
//! synthèse de caisse du jour pour la carte « Encaissements du jour » du
//! tableau de bord secrétariat.
//!
//! Root cause du bug : le front (#5382, mergé 7262b4a3) consommait déjà
//! cette route mais aucun handler/route n'existait côté API → 404
//! permanent. Champs alignés strictement sur le DTO front déjà mergé
//! (`cash_collection_summary_dto.dart`) : `collected_today_cents`,
//! `collected_today_payment_count`, `remaining_today_cents`,
//! `remaining_today_patient_count`, `closing_hour`, `unpaid_cents`,
//! `unpaid_patient_count`.
//!
//! Définitions retenues (aucun contrat métier préexistant pour cette carte,
//! cf. `cabinet_stats.rs` sur la même prudence pour les KPI non spécifiés) :
//! - `collected_today_*` : paiements `status='paid'` du jour (même filtre
//!   que `cabinet_cash_register::close_cash_register`).
//! - `unpaid_*` : impayé courant du cabinet, même formule que
//!   `outstanding_cents` de `GET /v1/cabinet/stats/billing` (par devis
//!   signé, part patient nette clampée à `>= 0` avant somme, #4425/#5487),
//!   avec en plus le nombre de patients distincts concernés.
//! - `remaining_today_*` : sous-ensemble de l'impayé ci-dessus restreint
//!   aux patients ayant un rendez-vous aujourd'hui (hors
//!   `cancelled`/`no_show`) — l'argent que la secrétaire peut encore
//!   espérer encaisser avant la fermeture, car le patient est physiquement
//!   attendu au cabinet le jour même.
//! - `closing_hour` : pas de config horaires structurée exploitable
//!   (`cabinet.settings->'horaires'` est un JSON libre, jamais parsé
//!   ailleurs dans l'API, cf. `cabinet_info.rs`) → valeur par défaut fixe
//!   (19h, horaire de fermeture usuel d'un cabinet dentaire) en attendant
//!   une config dédiée.

use axum::extract::State;
use axum::Json;
use serde::Serialize;
use sqlx::Row;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Horaire de fermeture par défaut, faute de config horaires structurée
/// (cf. docstring du module).
const DEFAULT_CLOSING_HOUR: i32 = 19;

#[derive(Serialize)]
pub struct CashCollectionSummaryResponse {
    pub collected_today_cents: i64,
    pub collected_today_payment_count: i64,
    pub remaining_today_cents: i64,
    pub remaining_today_patient_count: i64,
    pub closing_hour: i32,
    pub unpaid_cents: i64,
    pub unpaid_patient_count: i64,
}

/// `GET /v1/cabinet/cash-collection/today` — encaissé aujourd'hui, reste à
/// encaisser avant la fermeture, impayés du cabinet (#5591).
///
/// Token pro secretary+ requis (même garde que `cash-register/closing` et
/// `stats/billing`). `cabinet_id` extrait du JWT, RLS scopée via
/// `app.current_cabinet_id`.
pub async fn get_cash_collection_today(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<CashCollectionSummaryResponse>, AppError> {
    let today = chrono::Utc::now().date_naive();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let collected_row = sqlx::query(
        "SELECT (COALESCE(SUM(amount), 0) * 100)::bigint AS collected_today_cents, \
                COUNT(*)::bigint AS collected_today_payment_count \
         FROM payment \
         WHERE cabinet_id = $1 AND status = 'paid' AND created_at::date = $2",
    )
    .bind(claims.cabinet_id)
    .bind(today)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let collected_today_cents: i64 = collected_row
        .try_get("collected_today_cents")
        .map_err(|_| AppError::Internal)?;
    let collected_today_payment_count: i64 = collected_row
        .try_get("collected_today_payment_count")
        .map_err(|_| AppError::Internal)?;

    // Impayé courant (même formule que `outstanding_cents`,
    // `cabinet_stats.rs`) + sous-ensemble restreint aux patients attendus
    // aujourd'hui (`remaining_today_*`).
    let due_row = sqlx::query(
        "WITH today_patients AS ( \
           SELECT DISTINCT patient_id FROM appointment \
           WHERE cabinet_id = $1 AND starts_at::date = $2 \
             AND status NOT IN ('cancelled', 'no_show') AND deleted_at IS NULL \
         ), \
         quote_due AS ( \
           SELECT q.patient_id, \
                  GREATEST(0, COALESCE(patient_share.share, q.total_amount) \
                    - COALESCE(pay.paid_sum, 0)) AS due_amount \
           FROM quote q \
           LEFT JOIN ( \
             SELECT quote_id, SUM(qty * unit_amount - COALESCE(amo_part, 0) - COALESCE(amc_part, 0)) \
               AS share \
             FROM quote_item \
             GROUP BY quote_id \
           ) patient_share ON patient_share.quote_id = q.id \
           LEFT JOIN ( \
             SELECT quote_id, SUM(amount) AS paid_sum FROM payment \
             WHERE cabinet_id = $1 AND status IN ('pending', 'paid') \
             GROUP BY quote_id \
           ) pay ON pay.quote_id = q.id \
           WHERE q.cabinet_id = $1 AND q.status = 'signed' AND q.deleted_at IS NULL \
         ) \
         SELECT \
           (COALESCE(SUM(due_amount), 0) * 100)::bigint AS unpaid_cents, \
           COUNT(DISTINCT patient_id) FILTER (WHERE due_amount > 0)::bigint \
             AS unpaid_patient_count, \
           (COALESCE(SUM(due_amount) FILTER ( \
              WHERE patient_id IN (SELECT patient_id FROM today_patients) \
           ), 0) * 100)::bigint AS remaining_today_cents, \
           COUNT(DISTINCT patient_id) FILTER ( \
             WHERE due_amount > 0 \
               AND patient_id IN (SELECT patient_id FROM today_patients) \
           )::bigint AS remaining_today_patient_count \
         FROM quote_due",
    )
    .bind(claims.cabinet_id)
    .bind(today)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let unpaid_cents: i64 = due_row
        .try_get("unpaid_cents")
        .map_err(|_| AppError::Internal)?;
    let unpaid_patient_count: i64 = due_row
        .try_get("unpaid_patient_count")
        .map_err(|_| AppError::Internal)?;
    let remaining_today_cents: i64 = due_row
        .try_get("remaining_today_cents")
        .map_err(|_| AppError::Internal)?;
    let remaining_today_patient_count: i64 = due_row
        .try_get("remaining_today_patient_count")
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        collected_today_cents,
        remaining_today_cents,
        unpaid_cents,
        "cash collection today summary fetched"
    );

    Ok(Json(CashCollectionSummaryResponse {
        collected_today_cents,
        collected_today_payment_count,
        remaining_today_cents,
        remaining_today_patient_count,
        closing_hour: DEFAULT_CLOSING_HOUR,
        unpaid_cents,
        unpaid_patient_count,
    }))
}
