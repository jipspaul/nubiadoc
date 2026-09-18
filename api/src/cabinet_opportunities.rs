//! Handler `GET /v1/cabinet/opportunities` (#7214) — vue « opportunités du
//! moment » du cabinet : widget central du dashboard Dental Pilot. Agrège 5
//! catégories déjà couvertes individuellement ailleurs (`cabinet_quotes.rs`,
//! `patient_alerts.rs`, `recall_campaigns.rs`) mais jamais exposées en une
//! seule vue back-office.
//!
//! `ProSecretaryPlusClaims` (secretary/practitioner/admin, et tout rôle
//! `kind:"pro"` non filtré ici — manager/doctor inclus, cf. l'extracteur) :
//! même tier que `recall_campaigns`/`quote_relances`, tâche administrative de
//! pilotage du cabinet, pas une décision clinique.

use axum::{extract::State, Json};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Devis `sent` sans réponse depuis plus de N jours (#7214).
const QUOTE_NO_RESPONSE_DELAY_DAYS: i64 = 7;

/// Devis `signed` considéré impayé après N jours sans solde couvert — même
/// seuil que `patient_alerts::OVERDUE_INVOICE_DELAY_DAYS`.
const OVERDUE_INVOICE_DELAY_DAYS: i64 = 30;

/// Fenêtre « vu récemment » pour la catégorie patients sans prochain RDV —
/// aucun délai déjà configuré ailleurs pour ce sens (inverse de
/// `recall_campaigns::months_since_last_appointment`), valeur arbitraire
/// raisonnable pour un widget de suivi à J+30.
const RECENT_VISIT_WINDOW_DAYS: i64 = 30;

/// Une opportunité individuelle. `amount_cents`/`since_days`/`quote_id`
/// absents selon la catégorie (ex. anniversaire n'a ni montant ni devis).
#[derive(Serialize)]
pub struct OpportunityItem {
    pub kind: String,
    pub patient_id: Uuid,
    pub patient_name: Option<String>,
    pub amount_cents: Option<i64>,
    pub since_days: Option<i64>,
    pub quote_id: Option<Uuid>,
}

/// Une catégorie d'opportunités avec son compteur et son total.
#[derive(Serialize)]
pub struct OpportunityCategory {
    pub kind: String,
    pub count: i64,
    pub total_amount_cents: i64,
    pub items: Vec<OpportunityItem>,
}

/// Réponse de `GET /v1/cabinet/opportunities`.
#[derive(Serialize)]
pub struct CabinetOpportunitiesResponse {
    pub categories: Vec<OpportunityCategory>,
}

fn build_category(kind: &str, items: Vec<OpportunityItem>) -> OpportunityCategory {
    let total_amount_cents: i64 = items.iter().filter_map(|i| i.amount_cents).sum();
    OpportunityCategory {
        kind: kind.to_string(),
        count: items.len() as i64,
        total_amount_cents,
        items,
    }
}

/// `GET /v1/cabinet/opportunities` — vue agrégée « opportunités du moment »
/// du cabinet courant, 5 catégories (doc17 §4) :
/// - `quote_sent_no_response` : devis `sent` sans réponse depuis plus de
///   [`QUOTE_NO_RESPONSE_DELAY_DAYS`] jours.
/// - `quote_accepted_no_appointment` : devis `signed` sans aucun RDV actif à
///   venir pour ce patient.
/// - `unpaid_invoice` : devis `signed` dont le solde patient net (AMO/AMC
///   déduits, même formule que `patient_alerts.rs`) reste positif plus de
///   [`OVERDUE_INVOICE_DELAY_DAYS`] jours après signature.
/// - `patient_no_next_appointment` : RDV `done` dans les
///   [`RECENT_VISIT_WINDOW_DAYS`] derniers jours sans RDV actif à venir.
/// - `birthday_today` : anniversaire du jour (`patient.birth_date`).
///
/// `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`
/// (fail-closed) — un autre cabinet ne voit rien.
pub async fn get_cabinet_opportunities(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<CabinetOpportunitiesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // ── Devis envoyés sans réponse ───────────────────────────────────────
    let sent_no_response_rows = sqlx::query(&format!(
        "SELECT q.id AS quote_id, q.patient_id, \
                trim(concat(p.first_name, ' ', p.last_name)) AS patient_name, \
                (q.total_amount * 100)::bigint AS amount_cents, \
                extract(day FROM now() - q.sent_at)::bigint AS since_days \
         FROM quote q \
         LEFT JOIN patient p ON p.id = q.patient_id \
         WHERE q.cabinet_id = $1 AND q.status = 'sent' AND q.deleted_at IS NULL \
           AND q.sent_at < now() - interval '{QUOTE_NO_RESPONSE_DELAY_DAYS} days' \
         ORDER BY q.sent_at ASC"
    ))
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // ── Devis acceptés sans RDV planifié ─────────────────────────────────
    let accepted_no_appointment_rows = sqlx::query(
        "SELECT q.id AS quote_id, q.patient_id, \
                trim(concat(p.first_name, ' ', p.last_name)) AS patient_name, \
                (q.total_amount * 100)::bigint AS amount_cents, \
                extract(day FROM now() - q.signed_at)::bigint AS since_days \
         FROM quote q \
         LEFT JOIN patient p ON p.id = q.patient_id \
         WHERE q.cabinet_id = $1 AND q.status = 'signed' AND q.deleted_at IS NULL \
           AND NOT EXISTS ( \
             SELECT 1 FROM appointment a \
             WHERE a.patient_id = q.patient_id AND a.cabinet_id = $1 \
               AND a.starts_at > now() \
               AND a.status IN ('requested', 'confirmed', 'checked_in', 'in_progress') \
           ) \
         ORDER BY q.signed_at ASC",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // ── Factures (devis signés) impayées depuis plus de 30 jours ─────────
    // Même formule de solde net que `patient_alerts::get_patient_alerts`
    // (part patient nette AMO/AMC déduits, moins les paiements pending/paid).
    let unpaid_rows = sqlx::query(&format!(
        "WITH signed_balance AS ( \
           SELECT q.id, q.patient_id, q.signed_at, \
             ( (SELECT coalesce(sum(qi.qty * qi.unit_amount \
                     - coalesce(qi.amo_part, 0) - coalesce(qi.amc_part, 0)), 0) \
                FROM quote_item qi WHERE qi.quote_id = q.id) \
               - \
               (SELECT coalesce(sum(amount), 0) FROM payment \
                WHERE quote_id = q.id AND status IN ('pending', 'paid')) \
             ) AS balance_due \
           FROM quote q \
           WHERE q.cabinet_id = $1 AND q.status = 'signed' AND q.deleted_at IS NULL \
             AND q.signed_at < now() - interval '{OVERDUE_INVOICE_DELAY_DAYS} days' \
         ) \
         SELECT sb.id AS quote_id, sb.patient_id, \
                trim(concat(p.first_name, ' ', p.last_name)) AS patient_name, \
                (sb.balance_due * 100)::bigint AS amount_cents, \
                extract(day FROM now() - sb.signed_at)::bigint AS since_days \
         FROM signed_balance sb \
         LEFT JOIN patient p ON p.id = sb.patient_id \
         WHERE sb.balance_due > 0 \
         ORDER BY sb.signed_at ASC"
    ))
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // ── Patients vus récemment sans prochain RDV ─────────────────────────
    let no_next_appointment_rows = sqlx::query(&format!(
        "SELECT DISTINCT ON (p.id) p.id AS patient_id, \
                trim(concat(p.first_name, ' ', p.last_name)) AS patient_name, \
                extract(day FROM now() - a.starts_at)::bigint AS since_days \
         FROM patient p \
         JOIN appointment a ON a.patient_id = p.id AND a.cabinet_id = p.cabinet_id \
         WHERE p.cabinet_id = $1 AND p.deleted_at IS NULL \
           AND a.status = 'done' \
           AND a.starts_at > now() - interval '{RECENT_VISIT_WINDOW_DAYS} days' \
           AND NOT EXISTS ( \
             SELECT 1 FROM appointment a2 \
             WHERE a2.patient_id = p.id AND a2.cabinet_id = $1 \
               AND a2.starts_at > now() \
               AND a2.status IN ('requested', 'confirmed', 'checked_in', 'in_progress') \
           ) \
         ORDER BY p.id, a.starts_at DESC"
    ))
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // ── Anniversaires du jour ────────────────────────────────────────────
    let birthday_rows = sqlx::query(
        "SELECT id AS patient_id, trim(concat(first_name, ' ', last_name)) AS patient_name \
         FROM patient \
         WHERE cabinet_id = $1 AND deleted_at IS NULL AND birth_date IS NOT NULL \
           AND extract(month FROM birth_date) = extract(month FROM now()) \
           AND extract(day FROM birth_date) = extract(day FROM now())",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let to_items_with_quote = |rows: Vec<sqlx::postgres::PgRow>,
                               kind: &str|
     -> Result<Vec<OpportunityItem>, AppError> {
        rows.into_iter()
            .map(|row| {
                let quote_id: Uuid = row.try_get("quote_id").map_err(|_| AppError::Internal)?;
                let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
                let patient_name: Option<String> = row
                    .try_get("patient_name")
                    .map_err(|_| AppError::Internal)?;
                let amount_cents: i64 = row
                    .try_get("amount_cents")
                    .map_err(|_| AppError::Internal)?;
                let since_days: i64 = row.try_get("since_days").map_err(|_| AppError::Internal)?;
                Ok(OpportunityItem {
                    kind: kind.to_string(),
                    patient_id,
                    patient_name: patient_name.filter(|n| !n.is_empty()),
                    amount_cents: Some(amount_cents),
                    since_days: Some(since_days),
                    quote_id: Some(quote_id),
                })
            })
            .collect()
    };

    let quote_sent_no_response =
        to_items_with_quote(sent_no_response_rows, "quote_sent_no_response")?;
    let quote_accepted_no_appointment = to_items_with_quote(
        accepted_no_appointment_rows,
        "quote_accepted_no_appointment",
    )?;
    let unpaid_invoice = to_items_with_quote(unpaid_rows, "unpaid_invoice")?;

    let patient_no_next_appointment = no_next_appointment_rows
        .into_iter()
        .map(|row| {
            let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
            let patient_name: Option<String> = row
                .try_get("patient_name")
                .map_err(|_| AppError::Internal)?;
            let since_days: i64 = row.try_get("since_days").map_err(|_| AppError::Internal)?;
            Ok(OpportunityItem {
                kind: "patient_no_next_appointment".to_string(),
                patient_id,
                patient_name: patient_name.filter(|n| !n.is_empty()),
                amount_cents: None,
                since_days: Some(since_days),
                quote_id: None,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    let birthday_today = birthday_rows
        .into_iter()
        .map(|row| {
            let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
            let patient_name: Option<String> = row
                .try_get("patient_name")
                .map_err(|_| AppError::Internal)?;
            Ok(OpportunityItem {
                kind: "birthday_today".to_string(),
                patient_id,
                patient_name: patient_name.filter(|n| !n.is_empty()),
                amount_cents: None,
                since_days: None,
                quote_id: None,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    let categories = vec![
        build_category("quote_sent_no_response", quote_sent_no_response),
        build_category(
            "quote_accepted_no_appointment",
            quote_accepted_no_appointment,
        ),
        build_category("unpaid_invoice", unpaid_invoice),
        build_category("patient_no_next_appointment", patient_no_next_appointment),
        build_category("birthday_today", birthday_today),
    ];

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        total = categories.iter().map(|c| c.count).sum::<i64>(),
        "cabinet opportunities listed"
    );

    Ok(Json(CabinetOpportunitiesResponse { categories }))
}
