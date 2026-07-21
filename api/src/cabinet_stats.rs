//! Handler `GET /v1/cabinet/stats/activity` (#4079) — statistiques
//! d'activité du cabinet (par praticien et type d'acte).
//!
//! Agrégation SQL sur `consultation_act` dans le contexte tenant existant,
//! pas de nouvelle table (demandé explicitement par l'issue). Bornée à un
//! comptage/somme déterministe (nombre d'actes, montant total en centimes)
//! — pas de KPI dérivé (CA net, taux de transformation) qui nécessiterait
//! une définition métier non spécifiée par l'issue.

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
