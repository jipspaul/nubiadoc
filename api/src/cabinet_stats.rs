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
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
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
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`.
/// `from`/`to` (format `YYYY-MM-DD`, bornes inclusives sur
/// `consultation_act.created_at`) → `422 validation_error` si non parsable,
/// tous deux optionnels (absents = pas de borne).
/// Source : `consultation_act` uniquement (agrégation, aucune nouvelle table).
pub async fn get_cabinet_activity_stats(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
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
    /// Impayé courant (solde actuel, PAS borné par `from`/`to`) : somme des
    /// devis `signed` moins les paiements `pending`/`paid` (jamais
    /// `failed`/`refunded`) — même formule que `balance_due_cents`
    /// (`patient_detail::get_cabinet_patient`, US-4.6.2/#4044), agrégée au
    /// cabinet entier plutôt qu'à un seul patient.
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

    // Solde courant — même formule que balance_due_cents (clinical.rs),
    // délibérément non bornée par from/to (c'est un état, pas un flux).
    let outstanding_row = sqlx::query(
        "SELECT (( \
           COALESCE((SELECT SUM(total_amount) FROM quote \
                     WHERE cabinet_id = $1 AND status = 'signed' AND deleted_at IS NULL), 0) \
           - \
           COALESCE((SELECT SUM(amount) FROM payment \
                     WHERE cabinet_id = $1 AND status IN ('pending', 'paid')), 0) \
         ) * 100)::bigint AS outstanding_cents",
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
