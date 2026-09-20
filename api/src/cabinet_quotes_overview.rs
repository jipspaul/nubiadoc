//! Handler `GET /v1/cabinet/quotes/overview` (#7176, DP-F15.b) — vue
//! « suivi devis » multi-praticiens : compteurs par statut, montant, taux
//! de signature et délai moyen de signature, cabinet entier puis détaillé
//! par praticien.
//!
//! Formules alignées sur `cabinet_stats::get_cabinet_billing_stats`
//! (#4080) : « taux de signature » = `signed / (sent+signed+refused+expired)`
//! (`conversion_rate` là-bas), même périmètre de statuts (un devis encore
//! `draft` n'a pas encore été proposé au patient, il ne compte dans aucun
//! des deux membres du ratio). « Délai moyen » = moyenne de
//! `signed_at - sent_at` (heures) sur les devis `signed` ayant les deux
//! dates (un devis importé/backfillé sans `sent_at` est exclu plutôt que de
//! fausser la moyenne avec un délai inconnu).

use axum::extract::{Query, State};
use axum::Json;
use chrono::{Datelike, NaiveDate};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::AppError,
    cabinet_quotes::VALID_QUOTE_STATUSES,
    permissions::ProBillingClaims,
    scheduling::{cabinet_local_days_utc_range, paris_today},
    AppState,
};

/// Parse `"YYYY-MM"` en premier jour du mois. Même contrat que
/// `practitioner_kpis::parse_month` (dupliqué faute de fonction partagée
/// pour une conversion aussi courte, même choix que `cabinet_quotes::
/// is_valid_fdi_tooth`/`consultation_acts::is_valid_fdi_tooth`).
fn parse_month(s: &str) -> Result<NaiveDate, AppError> {
    NaiveDate::parse_from_str(&format!("{s}-01"), "%Y-%m-%d").map_err(|_| AppError::ValidationError)
}

/// Premier jour du mois suivant `month_start` (lui-même déjà un premier jour
/// de mois).
fn next_month_start(month_start: NaiveDate) -> NaiveDate {
    let (year, month) = if month_start.month() == 12 {
        (month_start.year() + 1, 1)
    } else {
        (month_start.year(), month_start.month() + 1)
    };
    NaiveDate::from_ymd_opt(year, month, 1).expect("mois valide")
}

#[derive(Deserialize)]
pub struct CabinetQuotesOverviewQuery {
    /// Mois ciblé, format `YYYY-MM` (défaut : mois courant, calendrier
    /// local `Europe/Paris`, cf. `paris_today`). Filtre sur `quote.created_at`.
    pub period: Option<String>,
    /// `practitioner_id` du praticien à isoler ; absent = tout le cabinet.
    pub provider: Option<Uuid>,
}

/// Compteur/montant pour un statut de devis.
#[derive(Serialize)]
pub struct QuoteStatusCount {
    pub status: String,
    pub count: i64,
    pub amount_cents: i64,
}

/// Agrégat pour un praticien du cabinet.
#[derive(Serialize)]
pub struct QuotePractitionerOverview {
    pub practitioner_id: Uuid,
    pub practitioner_name: Option<String>,
    pub count: i64,
    pub amount_cents: i64,
    pub signed_count: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signature_rate: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avg_time_to_sign_hours: Option<f64>,
}

/// Réponse de `GET /v1/cabinet/quotes/overview`.
#[derive(Serialize)]
pub struct CabinetQuotesOverviewResponse {
    /// Premier jour du mois couvert (`YYYY-MM-DD`).
    pub period_month: String,
    pub by_status: Vec<QuoteStatusCount>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub signature_rate: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub avg_time_to_sign_hours: Option<f64>,
    pub by_practitioner: Vec<QuotePractitionerOverview>,
}

/// `GET /v1/cabinet/quotes/overview?period=YYYY-MM&provider=` — vue
/// « suivi devis » multi-praticiens (#7176, DP-F15.b).
///
/// `ProBillingClaims` (même garde `permissions->>'billing'` que
/// `cabinet_quotes::list_cabinet_quotes`) — secretary/practitioner/admin/
/// manager avec l'accès facturation, `403` sinon.
/// `?period=` doit être `YYYY-MM` → `422 validation_error` sinon, défaut le
/// mois courant (calendrier `Europe/Paris`). `?provider=` filtre sur
/// `quote.practitioner_id` ; absent = tout le cabinet.
/// `by_status` couvre systématiquement les 5 valeurs de
/// `VALID_QUOTE_STATUSES` (0 si aucun devis dans cet état sur la période,
/// même choix que remplir plutôt qu'omettre pour un tableau de bord).
/// `by_practitioner` ne liste que les devis avec `practitioner_id` renseigné
/// (un devis créé par un rôle non-clinicien, cf. `cabinet_quotes::
/// create_cabinet_quote`, n'est attribuable à aucun praticien) — trié par
/// `count` décroissant.
pub async fn get_cabinet_quotes_overview(
    State(state): State<AppState>,
    claims: ProBillingClaims,
    Query(params): Query<CabinetQuotesOverviewQuery>,
) -> Result<Json<CabinetQuotesOverviewResponse>, AppError> {
    let month_start = match params.period.as_deref() {
        Some(p) => parse_month(p)?,
        None => {
            let today = paris_today();
            NaiveDate::from_ymd_opt(today.year(), today.month(), 1).expect("mois valide")
        }
    };
    let (period_start, period_end) = cabinet_local_days_utc_range(
        month_start,
        (next_month_start(month_start) - month_start).num_days(),
    )?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let status_rows = sqlx::query(
        "SELECT status, COUNT(*)::bigint AS count, \
                (COALESCE(SUM(total_amount), 0) * 100)::bigint AS amount_cents \
         FROM quote \
         WHERE cabinet_id = $1 AND deleted_at IS NULL \
           AND created_at >= $2 AND created_at < $3 \
           AND ($4::uuid IS NULL OR practitioner_id = $4) \
         GROUP BY status",
    )
    .bind(claims.cabinet_id)
    .bind(period_start)
    .bind(period_end)
    .bind(params.provider)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut by_status: Vec<QuoteStatusCount> = VALID_QUOTE_STATUSES
        .iter()
        .map(|status| QuoteStatusCount {
            status: status.to_string(),
            count: 0,
            amount_cents: 0,
        })
        .collect();
    for row in &status_rows {
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        let count: i64 = row.try_get("count").map_err(|_| AppError::Internal)?;
        let amount_cents: i64 = row
            .try_get("amount_cents")
            .map_err(|_| AppError::Internal)?;
        if let Some(entry) = by_status.iter_mut().find(|s| s.status == status) {
            entry.count = count;
            entry.amount_cents = amount_cents;
        }
    }

    // Même formule que `cabinet_stats::get_cabinet_billing_stats::conversion_rate`.
    let conversion_row = sqlx::query(
        "SELECT \
           COUNT(*) FILTER (WHERE status = 'signed')::bigint AS signed_count, \
           COUNT(*) FILTER (WHERE status IN ('sent', 'signed', 'refused', 'expired'))::bigint \
             AS sent_total, \
           (AVG(EXTRACT(EPOCH FROM (signed_at - sent_at)) / 3600.0) \
             FILTER (WHERE status = 'signed' AND signed_at IS NOT NULL AND sent_at IS NOT NULL))::float8 \
             AS avg_hours \
         FROM quote \
         WHERE cabinet_id = $1 AND deleted_at IS NULL \
           AND created_at >= $2 AND created_at < $3 \
           AND ($4::uuid IS NULL OR practitioner_id = $4)",
    )
    .bind(claims.cabinet_id)
    .bind(period_start)
    .bind(period_end)
    .bind(params.provider)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let signed_count: i64 = conversion_row
        .try_get("signed_count")
        .map_err(|_| AppError::Internal)?;
    let sent_total: i64 = conversion_row
        .try_get("sent_total")
        .map_err(|_| AppError::Internal)?;
    let avg_hours: Option<f64> = conversion_row
        .try_get("avg_hours")
        .map_err(|_| AppError::Internal)?;

    let signature_rate = if sent_total > 0 {
        Some(signed_count as f64 / sent_total as f64)
    } else {
        None
    };

    let practitioner_rows = sqlx::query(
        "SELECT q.practitioner_id, \
                practitioner_display_name(q.practitioner_id) AS practitioner_name, \
                COUNT(*)::bigint AS count, \
                (COALESCE(SUM(q.total_amount), 0) * 100)::bigint AS amount_cents, \
                COUNT(*) FILTER (WHERE q.status = 'signed')::bigint AS signed_count, \
                COUNT(*) FILTER (WHERE q.status IN ('sent', 'signed', 'refused', 'expired'))::bigint \
                  AS sent_total, \
                (AVG(EXTRACT(EPOCH FROM (q.signed_at - q.sent_at)) / 3600.0) \
                  FILTER (WHERE q.status = 'signed' AND q.signed_at IS NOT NULL AND q.sent_at IS NOT NULL))::float8 \
                  AS avg_hours \
         FROM quote q \
         WHERE q.cabinet_id = $1 AND q.deleted_at IS NULL AND q.practitioner_id IS NOT NULL \
           AND q.created_at >= $2 AND q.created_at < $3 \
           AND ($4::uuid IS NULL OR q.practitioner_id = $4) \
         GROUP BY q.practitioner_id \
         ORDER BY count DESC",
    )
    .bind(claims.cabinet_id)
    .bind(period_start)
    .bind(period_end)
    .bind(params.provider)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut by_practitioner = Vec::with_capacity(practitioner_rows.len());
    for row in &practitioner_rows {
        let practitioner_id: Uuid = row
            .try_get("practitioner_id")
            .map_err(|_| AppError::Internal)?;
        let practitioner_name: Option<String> = row
            .try_get("practitioner_name")
            .map_err(|_| AppError::Internal)?;
        let count: i64 = row.try_get("count").map_err(|_| AppError::Internal)?;
        let amount_cents: i64 = row
            .try_get("amount_cents")
            .map_err(|_| AppError::Internal)?;
        let p_signed_count: i64 = row
            .try_get("signed_count")
            .map_err(|_| AppError::Internal)?;
        let p_sent_total: i64 = row.try_get("sent_total").map_err(|_| AppError::Internal)?;
        let p_avg_hours: Option<f64> = row.try_get("avg_hours").map_err(|_| AppError::Internal)?;

        let p_signature_rate = if p_sent_total > 0 {
            Some(p_signed_count as f64 / p_sent_total as f64)
        } else {
            None
        };

        by_practitioner.push(QuotePractitionerOverview {
            practitioner_id,
            practitioner_name,
            count,
            amount_cents,
            signed_count: p_signed_count,
            signature_rate: p_signature_rate,
            avg_time_to_sign_hours: p_avg_hours,
        });
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        period_month = %month_start,
        provider = ?params.provider,
        "cabinet quotes overview fetched"
    );

    Ok(Json(CabinetQuotesOverviewResponse {
        period_month: month_start.to_string(),
        by_status,
        signature_rate,
        avg_time_to_sign_hours: avg_hours,
        by_practitioner,
    }))
}
