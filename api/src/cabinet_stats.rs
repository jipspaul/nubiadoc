//! Handlers `GET /v1/cabinet/stats/activity` (#4079) et
//! `GET /v1/cabinet/stats/billing` (#4080) — statistiques du cabinet.
//!
//! Agrégation SQL directe sur les tables existantes (`consultation_act`,
//! `quote`, `payment`) dans le contexte tenant, pas de nouvelle table
//! (demandé explicitement par les deux issues). Bornée à des comptages/sommes
//! déterministes — pas de KPI dont la définition n'est pas donnée par
//! l'issue (ex. CA net) : cf. #4153 (écran de pilotage), flaguée bloquée
//! pour ce type de besoin non spécifié.

use axum::extract::{Query, State};
use axum::Json;
use chrono::{Datelike, NaiveDate};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims, ProSecretaryPlusClaims},
    scheduling::{cabinet_local_days_utc_range, paris_today},
    AppState,
};

/// Query de `GET /v1/cabinet/stats/activity` — bornes de date `YYYY-MM-DD`
/// (inclusives), sur `consultation_act.created_at`.
#[derive(Deserialize)]
pub struct ActivityStatsQuery {
    pub from: Option<String>,
    pub to: Option<String>,
}

/// Agrégat pour un couple (praticien, acte CCAM).
#[derive(Serialize)]
pub struct ActivityStatItem {
    pub practitioner_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub practitioner_name: Option<String>,
    pub ccam_code: String,
    pub label: String,
    pub act_count: i64,
    pub total_amount_cents: i64,
}

/// Réponse de `GET /v1/cabinet/stats/activity`.
#[derive(Serialize)]
pub struct ActivityStatsResponse {
    pub data: Vec<ActivityStatItem>,
}

/// `GET /v1/cabinet/stats/activity?from=&to=` — nombre d'actes et montant
/// total facturé, groupés par praticien et type d'acte CCAM (#4079).
///
/// Praticien uniquement (`ProPractitionerClaims`) — le détail des actes
/// cliniques (codes CCAM par praticien) relève du clinique, comme le reste
/// de la surface `consultation_act` (403 secretary/patient, cf. #4592).
/// `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`.
/// `from`/`to` (format `YYYY-MM-DD`, bornes inclusives sur
/// `consultation_act.created_at`) → `422 validation_error` si non parsable,
/// tous deux optionnels (absents = pas de borne).
/// Source : `consultation_act` uniquement (agrégation, aucune nouvelle table).
pub async fn get_cabinet_activity_stats(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Query(params): Query<ActivityStatsQuery>,
) -> Result<Json<ActivityStatsResponse>, AppError> {
    let from: Option<chrono::NaiveDate> = params
        .from
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;
    let to: Option<chrono::NaiveDate> = params
        .to
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT ca.practitioner_id, pv.display_name AS practitioner_name, \
                ca.ccam_code, ca.label, \
                COUNT(*)::bigint AS act_count, \
                COALESCE(SUM(ca.amount_cents), 0)::bigint AS total_amount_cents \
         FROM consultation_act ca \
         LEFT JOIN provider pv \
           ON pv.practitioner_id = ca.practitioner_id AND pv.cabinet_id = ca.cabinet_id \
         WHERE ca.cabinet_id = $1 \
           AND ($2::date IS NULL OR ca.created_at::date >= $2) \
           AND ($3::date IS NULL OR ca.created_at::date <= $3) \
         GROUP BY ca.practitioner_id, pv.display_name, ca.ccam_code, ca.label \
         ORDER BY ca.practitioner_id, ca.ccam_code",
    )
    .bind(claims.cabinet_id)
    .bind(from)
    .bind(to)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .into_iter()
        .map(|row| {
            Ok(ActivityStatItem {
                practitioner_id: row
                    .try_get("practitioner_id")
                    .map_err(|_| AppError::Internal)?,
                practitioner_name: row
                    .try_get("practitioner_name")
                    .map_err(|_| AppError::Internal)?,
                ccam_code: row.try_get("ccam_code").map_err(|_| AppError::Internal)?,
                label: row.try_get("label").map_err(|_| AppError::Internal)?,
                act_count: row.try_get("act_count").map_err(|_| AppError::Internal)?,
                total_amount_cents: row
                    .try_get("total_amount_cents")
                    .map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        rows = data.len(),
        "cabinet activity stats fetched"
    );

    Ok(Json(ActivityStatsResponse { data }))
}

// ---------------------------------------------------------------------------
// GET /v1/cabinet/stats/billing (#4080)
// ---------------------------------------------------------------------------

/// Query de `GET /v1/cabinet/stats/billing` — bornes de date `YYYY-MM-DD`
/// (inclusives). Filtrent `revenue_collected_cents` (`payment.created_at`)
/// et `conversion_rate` (`quote.created_at`) — `outstanding_cents` est un
/// solde courant, jamais filtré par date (cf. doc du champ).
#[derive(Deserialize)]
pub struct BillingStatsQuery {
    pub from: Option<String>,
    pub to: Option<String>,
}

/// Réponse de `GET /v1/cabinet/stats/billing`.
#[derive(Serialize)]
pub struct BillingStatsResponse {
    /// CA encaissé sur la période : somme des `payment.amount` `status='paid'`.
    pub revenue_collected_cents: i64,
    /// Impayé courant (solde actuel, PAS borné par `from`/`to`) : pour
    /// chaque devis `signed`, `total_amount` moins les paiements
    /// `pending`/`paid` **rattachés à ce devis** (`payment.quote_id`) —
    /// jamais `failed`/`refunded` — clampé à `>= 0` **par devis** puis
    /// sommé (#4425 : un clamp global masquait les impayés réels d'un
    /// devis derrière le trop-perçu d'un autre). `>= 0` par construction
    /// (#4347 — contrairement à `balance_due_cents`, agréger tous les
    /// paiements du cabinet sans ce scoping mélangeait des ensembles sans
    /// rapport et produisait un solde absurdement négatif).
    pub outstanding_cents: i64,
    /// `signed_count / sent_total` sur la période (`quote.created_at`) —
    /// `sent_total` = devis ayant atteint le statut envoyé
    /// (`sent`/`signed`/`refused`/`expired`, PAS `draft`, jamais envoyé).
    /// `null` si `sent_total = 0` (rien à diviser).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub conversion_rate: Option<f64>,
    pub signed_count: i64,
    pub sent_total: i64,
}

/// `GET /v1/cabinet/stats/billing?from=&to=` — CA encaissé, impayé courant,
/// taux de transformation devis signés/envoyés (#4080).
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`.
/// `from`/`to` → `422 validation_error` si non parsable.
pub async fn get_cabinet_billing_stats(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<BillingStatsQuery>,
) -> Result<Json<BillingStatsResponse>, AppError> {
    let from: Option<chrono::NaiveDate> = params
        .from
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;
    let to: Option<chrono::NaiveDate> = params
        .to
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let revenue_row = sqlx::query(
        "SELECT (COALESCE(SUM(amount), 0) * 100)::bigint AS revenue_collected_cents \
         FROM payment \
         WHERE cabinet_id = $1 AND status = 'paid' \
           AND ($2::date IS NULL OR created_at::date >= $2) \
           AND ($3::date IS NULL OR created_at::date <= $3)",
    )
    .bind(claims.cabinet_id)
    .bind(from)
    .bind(to)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let revenue_collected_cents: i64 = revenue_row
        .try_get("revenue_collected_cents")
        .map_err(|_| AppError::Internal)?;

    // Solde courant, délibérément non borné par from/to (c'est un état, pas
    // un flux). #4347 : contrairement à balance_due_cents (patient_detail.rs)
    // - où "tous les paiements du patient" et "ses devis signés" coïncident
    // en pratique à l'échelle d'un seul patient - agréger "TOUS les
    // paiements du cabinet" contre "les devis signés du cabinet" mélange des
    // ensembles sans rapport (acomptes sur devis draft/refused, paiements
    // hors devis...) et pouvait produire un impayé massivement négatif. Fix
    // : ne compter que les paiements réellement rattachés (quote_id) à un
    // devis signé.
    // #4425 : le fix #4347 clampait GREATEST(0, ...) sur l'agrégat GLOBAL
    // (somme des devis - somme des paiements), donc un devis surpayé
    // (trop-perçu) pouvait compenser un autre devis impayé avant que le
    // clamp global écrase le résidu net négatif à 0 - masquant des impayés
    // réels. Un impayé n'est jamais négatif PAR DEVIS ; le clamp doit donc
    // s'appliquer par devis (trop-perçu neutralisé à 0 sans absorber
    // l'impayé d'un autre devis) avant de sommer.
    // #5487 : q.total_amount est le montant BRUT du devis (tiers-payant inclus).
    // Un paiement patient est plafonné à patient_share (total - amo_part -
    // amc_part, cf. billing_payments.rs) et ne peut donc jamais éteindre la
    // part AMO/AMC : comparer les paiements au brut laissait un impayé
    // fantôme permanent égal à amo_part + amc_part dès qu'il y avait du
    // tiers-payant. Même correctif que #4748 (patient_detail.rs) : comparer
    // les paiements à la part patient nette, pas au total brut.
    let outstanding_row = sqlx::query(
        "SELECT (COALESCE(SUM(GREATEST(0, COALESCE(patient_share.share, q.total_amount) \
           - COALESCE(pay.paid_sum, 0))), 0) * 100)::bigint AS outstanding_cents \
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
         WHERE q.cabinet_id = $1 AND q.status = 'signed' AND q.deleted_at IS NULL",
    )
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let outstanding_cents: i64 = outstanding_row
        .try_get("outstanding_cents")
        .map_err(|_| AppError::Internal)?;

    let conversion_row = sqlx::query(
        "SELECT \
           COUNT(*) FILTER (WHERE status = 'signed')::bigint AS signed_count, \
           COUNT(*) FILTER (WHERE status IN ('sent', 'signed', 'refused', 'expired'))::bigint \
             AS sent_total \
         FROM quote \
         WHERE cabinet_id = $1 AND deleted_at IS NULL \
           AND ($2::date IS NULL OR created_at::date >= $2) \
           AND ($3::date IS NULL OR created_at::date <= $3)",
    )
    .bind(claims.cabinet_id)
    .bind(from)
    .bind(to)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let signed_count: i64 = conversion_row
        .try_get("signed_count")
        .map_err(|_| AppError::Internal)?;
    let sent_total: i64 = conversion_row
        .try_get("sent_total")
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let conversion_rate = if sent_total > 0 {
        Some(signed_count as f64 / sent_total as f64)
    } else {
        None
    };

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        revenue_collected_cents,
        outstanding_cents,
        signed_count,
        sent_total,
        "cabinet billing stats fetched"
    );

    Ok(Json(BillingStatsResponse {
        revenue_collected_cents,
        outstanding_cents,
        conversion_rate,
        signed_count,
        sent_total,
    }))
}

// ---------------------------------------------------------------------------
// GET /v1/cabinet/lab-stats (#7164, DP-F19.b)
// ---------------------------------------------------------------------------

/// Parse `"YYYY-MM"` en premier jour du mois. Même contrat que
/// `cabinet_quotes_overview::parse_month`/`practitioner_kpis::parse_month`
/// (dupliqué faute de fonction partagée pour une conversion aussi courte).
fn parse_lab_stats_month(s: &str) -> Result<NaiveDate, AppError> {
    NaiveDate::parse_from_str(&format!("{s}-01"), "%Y-%m-%d").map_err(|_| AppError::ValidationError)
}

/// Premier jour du mois suivant `month_start`. Même contrat que
/// `cabinet_quotes_overview::next_month_start`.
fn next_lab_stats_month(month_start: NaiveDate) -> NaiveDate {
    let (year, month) = if month_start.month() == 12 {
        (month_start.year() + 1, 1)
    } else {
        (month_start.year(), month_start.month() + 1)
    };
    NaiveDate::from_ymd_opt(year, month, 1).expect("mois valide")
}

/// Query de `GET /v1/cabinet/lab-stats`.
#[derive(Deserialize)]
pub struct LabStatsQuery {
    /// Mois ciblé, format `YYYY-MM` (défaut : mois courant, calendrier local
    /// `Europe/Paris`). Filtre sur `lab_work_order.sent_at`.
    pub period: Option<String>,
}

/// Un bon de travail sur la période, valorisé (coût labo vs CA patient).
#[derive(Serialize)]
pub struct LabStatActItem {
    pub lab_work_order_id: Uuid,
    pub lab_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub practitioner_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub practitioner_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tooth_fdi: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub work_nature: Option<String>,
    /// `lab_work_order.purchase_price_cents`.
    pub lab_cost_cents: i64,
    /// Montant facturé au patient sur la ligne de devis liée
    /// (`quote_item.qty * quote_item.unit_amount`) — `0` si le bon n'est
    /// rattaché à aucune ligne de devis (pas de CA patient identifiable).
    pub patient_revenue_cents: i64,
    /// `patient_revenue_cents - lab_cost_cents`.
    pub margin_cents: i64,
}

/// Agrégat pour un laboratoire.
#[derive(Serialize)]
pub struct LabStatByLab {
    pub lab_name: String,
    pub order_count: i64,
    pub lab_cost_cents: i64,
    pub patient_revenue_cents: i64,
    pub margin_cents: i64,
}

/// Agrégat pour un praticien (bons rattachés à un devis avec `practitioner_id`).
#[derive(Serialize)]
pub struct LabStatByPractitioner {
    pub practitioner_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub practitioner_name: Option<String>,
    pub order_count: i64,
    pub lab_cost_cents: i64,
    pub patient_revenue_cents: i64,
    pub margin_cents: i64,
}

/// Réponse de `GET /v1/cabinet/lab-stats`.
#[derive(Serialize)]
pub struct LabStatsResponse {
    /// Premier jour du mois couvert (`YYYY-MM-DD`).
    pub period_month: String,
    pub total_lab_cost_cents: i64,
    pub total_patient_revenue_cents: i64,
    pub total_margin_cents: i64,
    pub by_act: Vec<LabStatActItem>,
    pub by_practitioner: Vec<LabStatByPractitioner>,
    pub by_lab: Vec<LabStatByLab>,
}

/// `GET /v1/cabinet/lab-stats?period=YYYY-MM` — coût labo, CA patient et
/// marge par acte / par praticien / par laboratoire (#7164, DP-F19.b).
///
/// Token pro requis (secretary/practitioner/admin) — patient → 403.
/// `?period=` → `422 validation_error` si non `YYYY-MM`, défaut le mois
/// courant (calendrier `Europe/Paris`, même contrat que
/// `cabinet_quotes_overview::get_cabinet_quotes_overview`). Filtre sur
/// `lab_work_order.sent_at` (date de création du bon, borne de la fenêtre
/// mensuelle en UTC via `cabinet_local_days_utc_range`).
///
/// `patient_revenue_cents` = `quote_item.qty * quote_item.unit_amount` de la
/// ligne de devis liée au bon (`lab_work_order.quote_item_id`) — `0` si le
/// bon n'est rattaché à aucune ligne (coût labo compté quand même dans les
/// totaux/`by_lab`, mais absent de `by_practitioner` faute de praticien
/// identifiable via `quote.practitioner_id`). `margin_cents` peut être
/// négatif (coût labo supérieur au prix facturé, alerte visuelle côté
/// client).
pub async fn get_cabinet_lab_stats(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<LabStatsQuery>,
) -> Result<Json<LabStatsResponse>, AppError> {
    let month_start = match params.period.as_deref() {
        Some(p) => parse_lab_stats_month(p)?,
        None => {
            let today = paris_today();
            NaiveDate::from_ymd_opt(today.year(), today.month(), 1).expect("mois valide")
        }
    };
    let (period_start, period_end) = cabinet_local_days_utc_range(
        month_start,
        (next_lab_stats_month(month_start) - month_start).num_days(),
    )?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let act_rows = sqlx::query(
        "SELECT lwo.id AS lab_work_order_id, lwo.lab_name, \
                q.practitioner_id, practitioner_display_name(q.practitioner_id) AS practitioner_name, \
                qi.tooth AS tooth_fdi, qi.label AS work_nature, \
                lwo.purchase_price_cents::bigint AS lab_cost_cents, \
                (COALESCE(qi.qty * qi.unit_amount, 0) * 100)::bigint AS patient_revenue_cents \
         FROM lab_work_order lwo \
         LEFT JOIN quote_item qi ON qi.id = lwo.quote_item_id \
         LEFT JOIN quote q ON q.id = qi.quote_id \
         WHERE lwo.cabinet_id = $1 \
           AND lwo.sent_at >= $2 AND lwo.sent_at < $3 \
         ORDER BY lwo.sent_at DESC",
    )
    .bind(claims.cabinet_id)
    .bind(period_start)
    .bind(period_end)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let by_lab_rows = sqlx::query(
        "SELECT lwo.lab_name, COUNT(*)::bigint AS order_count, \
                SUM(lwo.purchase_price_cents)::bigint AS lab_cost_cents, \
                (COALESCE(SUM(qi.qty * qi.unit_amount), 0) * 100)::bigint AS patient_revenue_cents \
         FROM lab_work_order lwo \
         LEFT JOIN quote_item qi ON qi.id = lwo.quote_item_id \
         WHERE lwo.cabinet_id = $1 \
           AND lwo.sent_at >= $2 AND lwo.sent_at < $3 \
         GROUP BY lwo.lab_name \
         ORDER BY lwo.lab_name",
    )
    .bind(claims.cabinet_id)
    .bind(period_start)
    .bind(period_end)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let by_practitioner_rows = sqlx::query(
        "SELECT q.practitioner_id, practitioner_display_name(q.practitioner_id) AS practitioner_name, \
                COUNT(*)::bigint AS order_count, \
                SUM(lwo.purchase_price_cents)::bigint AS lab_cost_cents, \
                (COALESCE(SUM(qi.qty * qi.unit_amount), 0) * 100)::bigint AS patient_revenue_cents \
         FROM lab_work_order lwo \
         JOIN quote_item qi ON qi.id = lwo.quote_item_id \
         JOIN quote q ON q.id = qi.quote_id AND q.practitioner_id IS NOT NULL \
         WHERE lwo.cabinet_id = $1 \
           AND lwo.sent_at >= $2 AND lwo.sent_at < $3 \
         GROUP BY q.practitioner_id \
         ORDER BY order_count DESC",
    )
    .bind(claims.cabinet_id)
    .bind(period_start)
    .bind(period_end)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut by_act = Vec::with_capacity(act_rows.len());
    let mut total_lab_cost_cents: i64 = 0;
    let mut total_patient_revenue_cents: i64 = 0;
    for row in &act_rows {
        let lab_cost_cents: i64 = row
            .try_get("lab_cost_cents")
            .map_err(|_| AppError::Internal)?;
        let patient_revenue_cents: i64 = row
            .try_get("patient_revenue_cents")
            .map_err(|_| AppError::Internal)?;
        total_lab_cost_cents += lab_cost_cents;
        total_patient_revenue_cents += patient_revenue_cents;
        by_act.push(LabStatActItem {
            lab_work_order_id: row
                .try_get("lab_work_order_id")
                .map_err(|_| AppError::Internal)?,
            lab_name: row.try_get("lab_name").map_err(|_| AppError::Internal)?,
            practitioner_id: row
                .try_get("practitioner_id")
                .map_err(|_| AppError::Internal)?,
            practitioner_name: row
                .try_get("practitioner_name")
                .map_err(|_| AppError::Internal)?,
            tooth_fdi: row.try_get("tooth_fdi").map_err(|_| AppError::Internal)?,
            work_nature: row.try_get("work_nature").map_err(|_| AppError::Internal)?,
            lab_cost_cents,
            patient_revenue_cents,
            margin_cents: patient_revenue_cents - lab_cost_cents,
        });
    }

    let mut by_lab = Vec::with_capacity(by_lab_rows.len());
    for row in &by_lab_rows {
        let lab_cost_cents: i64 = row
            .try_get("lab_cost_cents")
            .map_err(|_| AppError::Internal)?;
        let patient_revenue_cents: i64 = row
            .try_get("patient_revenue_cents")
            .map_err(|_| AppError::Internal)?;
        by_lab.push(LabStatByLab {
            lab_name: row.try_get("lab_name").map_err(|_| AppError::Internal)?,
            order_count: row.try_get("order_count").map_err(|_| AppError::Internal)?,
            lab_cost_cents,
            patient_revenue_cents,
            margin_cents: patient_revenue_cents - lab_cost_cents,
        });
    }

    let mut by_practitioner = Vec::with_capacity(by_practitioner_rows.len());
    for row in &by_practitioner_rows {
        let lab_cost_cents: i64 = row
            .try_get("lab_cost_cents")
            .map_err(|_| AppError::Internal)?;
        let patient_revenue_cents: i64 = row
            .try_get("patient_revenue_cents")
            .map_err(|_| AppError::Internal)?;
        by_practitioner.push(LabStatByPractitioner {
            practitioner_id: row
                .try_get("practitioner_id")
                .map_err(|_| AppError::Internal)?,
            practitioner_name: row
                .try_get("practitioner_name")
                .map_err(|_| AppError::Internal)?,
            order_count: row.try_get("order_count").map_err(|_| AppError::Internal)?,
            lab_cost_cents,
            patient_revenue_cents,
            margin_cents: patient_revenue_cents - lab_cost_cents,
        });
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        period_month = %month_start,
        orders = by_act.len(),
        total_lab_cost_cents,
        total_patient_revenue_cents,
        "cabinet lab stats fetched"
    );

    Ok(Json(LabStatsResponse {
        period_month: month_start.to_string(),
        total_lab_cost_cents,
        total_patient_revenue_cents,
        total_margin_cents: total_patient_revenue_cents - total_lab_cost_cents,
        by_act,
        by_practitioner,
        by_lab,
    }))
}
