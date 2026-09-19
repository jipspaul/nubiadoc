//! Handler `GET /v1/me/kpis` (#7189, DP-F10.b) — tableau de bord KPI du
//! praticien connecté : facturé/encaissé jour+mois (global et par cabinet),
//! objectif du mois et % atteint, taux d'occupation de la semaine courante,
//! RDV du jour, rappels en attente. CRUD des objectifs sous
//! `/v1/cabinet/practitioner-objectives` pour le manager/admin.
//!
//! Un praticien peut exercer dans plusieurs cabinets (une ligne `practitioner`
//! par cabinet, migration 0002) alors que le JWT ne porte qu'un seul
//! `cabinet_id` à la fois (`select-context`) — la résolution multi-cabinet
//! passe donc par `user_practitioner_ids()` (migration 0254, SECURITY
//! DEFINER, contourne la RLS fail-closed `practitioner`), même pattern que
//! `GET /v1/me` (auth/mod.rs). Chaque cabinet est ensuite requêté dans sa
//! propre transaction avec le GUC `app.current_cabinet_id` posé.
//!
//! Attribution des montants par praticien :
//! - « Facturé » = `consultation_act.amount_cents` (colonne `practitioner_id`
//!   directe, même source que `cabinet_stats::get_cabinet_activity_stats`).
//! - « Encaissé » = paiements `paid` des patients traités par ce praticien
//!   dans ce cabinet (`payment` n'a pas de colonne `practitioner_id` — on
//!   rattache via l'ensemble des patients ayant un `consultation_act` de ce
//!   praticien, seule jointure possible avec le schéma existant).
//!
//! L'objectif (`practitioner_objective.target_cents`) est comparé au facturé
//! du mois (donnée directement attribuable), pas à l'encaissé (approximation
//! ci-dessus).

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use chrono::Datelike;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminOrManagerClaims, ProPractitionerClaims},
    scheduling::cabinet_local_days_utc_range,
    AppState,
};

/// Parse `"YYYY-MM"` en premier jour du mois. `422 validation_error` si le
/// format ne correspond pas.
fn parse_month(s: &str) -> Result<chrono::NaiveDate, AppError> {
    chrono::NaiveDate::parse_from_str(&format!("{s}-01"), "%Y-%m-%d")
        .map_err(|_| AppError::ValidationError)
}

/// Premier jour du mois suivant `month_start` (lui-même déjà un premier jour
/// de mois) — utilisé pour borner la fenêtre `[month_start, next[`.
fn next_month_start(month_start: chrono::NaiveDate) -> chrono::NaiveDate {
    let (year, month) = if month_start.month() == 12 {
        (month_start.year() + 1, 1)
    } else {
        (month_start.year(), month_start.month() + 1)
    };
    chrono::NaiveDate::from_ymd_opt(year, month, 1).expect("mois valide")
}

// ---------------------------------------------------------------------------
// GET /v1/me/kpis (#7189)
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
pub struct MyKpisQuery {
    /// Mois ciblé pour le CA mensuel/objectif, format `YYYY-MM` (défaut :
    /// mois courant). Le CA du jour et l'occupation portent toujours sur
    /// aujourd'hui/la semaine courante, quel que soit `period`.
    pub period: Option<String>,
}

#[derive(Serialize)]
pub struct KpiAmounts {
    pub billed_cents: i64,
    pub collected_cents: i64,
}

#[derive(Serialize)]
pub struct CabinetKpiItem {
    pub cabinet_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cabinet_name: Option<String>,
    pub today: KpiAmounts,
    pub month: KpiAmounts,
    pub appointments_today: i64,
    pub pending_reminders: i64,
    /// Créneaux réservés / créneaux ouverts de la semaine courante.
    /// `null` si aucun créneau ouvert cette semaine (rien à diviser).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub occupancy_rate: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub objective_target_cents: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub objective_achieved_pct: Option<f64>,
}

#[derive(Serialize)]
pub struct PractitionerKpisResponse {
    /// Premier jour du mois utilisé pour `month`/l'objectif (`YYYY-MM-DD`).
    pub period_month: String,
    pub today: KpiAmounts,
    pub month: KpiAmounts,
    pub appointments_today: i64,
    pub pending_reminders: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub occupancy_rate: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub objective_target_cents: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub objective_achieved_pct: Option<f64>,
    pub by_cabinet: Vec<CabinetKpiItem>,
}

/// `GET /v1/me/kpis?period=YYYY-MM` — tableau de bord KPI du praticien
/// appelant, agrégé sur tous ses cabinets (`today`/`month`/`appointments_today`
/// /`pending_reminders`/`occupancy_rate`/objectif) et détaillé par cabinet
/// (`by_cabinet`). Aucun cabinet trouvé (compte sans profil `practitioner`,
/// ex. admin pur) → tout à zéro, `by_cabinet: []`, pas d'erreur.
pub async fn get_my_kpis(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Query(params): Query<MyKpisQuery>,
) -> Result<Json<PractitionerKpisResponse>, AppError> {
    let month_start = match params.period.as_deref() {
        Some(p) => parse_month(p)?,
        None => {
            let today = chrono::Utc::now().date_naive();
            chrono::NaiveDate::from_ymd_opt(today.year(), today.month(), 1).expect("mois valide")
        }
    };
    let (month_start_utc, month_end_utc) = cabinet_local_days_utc_range(
        month_start,
        (next_month_start(month_start) - month_start).num_days(),
    )?;

    let today = chrono::Utc::now().date_naive();
    let (day_start_utc, day_end_utc) = cabinet_local_days_utc_range(today, 1)?;

    // Semaine courante = lundi-dimanche (procédure #7189, étape 2).
    let week_start = today - chrono::Duration::days(today.weekday().num_days_from_monday() as i64);
    let (week_start_utc, week_end_utc) = cabinet_local_days_utc_range(week_start, 7)?;

    // Résolution multi-cabinet (voir doc de module) : contourne la RLS
    // fail-closed de `practitioner`.
    let pairs: Vec<(Uuid, Uuid)> =
        sqlx::query("SELECT cabinet_id, practitioner_id FROM user_practitioner_ids($1)")
            .bind(claims.sub)
            .fetch_all(&state.db)
            .await
            .map_err(|_| AppError::Internal)?
            .into_iter()
            .map(|r| -> Result<(Uuid, Uuid), AppError> {
                let cabinet_id: Uuid = r.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
                let practitioner_id: Uuid = r
                    .try_get("practitioner_id")
                    .map_err(|_| AppError::Internal)?;
                Ok((cabinet_id, practitioner_id))
            })
            .collect::<Result<Vec<_>, AppError>>()?;

    let mut by_cabinet = Vec::with_capacity(pairs.len());
    let mut total_billed_today_cents = 0i64;
    let mut total_collected_today_cents = 0i64;
    let mut total_billed_month_cents = 0i64;
    let mut total_collected_month_cents = 0i64;
    let mut total_appointments_today = 0i64;
    let mut total_pending_reminders = 0i64;
    let mut total_opened_week = 0i64;
    let mut total_reserved_week = 0i64;
    let mut total_objective_target_cents: Option<i64> = None;

    for (cabinet_id, practitioner_id) in pairs {
        let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let cabinet_name: Option<String> =
            sqlx::query("SELECT raison_sociale FROM cabinet WHERE id = $1")
                .bind(cabinet_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
                .map(|r| r.try_get("raison_sociale"))
                .transpose()
                .map_err(|_| AppError::Internal)?;

        let provider_id: Option<Uuid> = sqlx::query(
            "SELECT id FROM provider WHERE practitioner_id = $1 AND cabinet_id = $2 LIMIT 1",
        )
        .bind(practitioner_id)
        .bind(cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .map(|r| r.try_get("id"))
        .transpose()
        .map_err(|_| AppError::Internal)?;

        let billed_row = sqlx::query(
            "SELECT \
               COALESCE(SUM(amount_cents) FILTER (WHERE created_at >= $1 AND created_at < $2), 0)::bigint \
                 AS billed_today_cents, \
               COALESCE(SUM(amount_cents) FILTER (WHERE created_at >= $3 AND created_at < $4), 0)::bigint \
                 AS billed_month_cents \
             FROM consultation_act \
             WHERE cabinet_id = $5 AND practitioner_id = $6",
        )
        .bind(day_start_utc)
        .bind(day_end_utc)
        .bind(month_start_utc)
        .bind(month_end_utc)
        .bind(cabinet_id)
        .bind(practitioner_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        let billed_today_cents: i64 = billed_row
            .try_get("billed_today_cents")
            .map_err(|_| AppError::Internal)?;
        let billed_month_cents: i64 = billed_row
            .try_get("billed_month_cents")
            .map_err(|_| AppError::Internal)?;

        // Encaissé : patients traités par CE praticien dans CE cabinet (cf.
        // doc de module — `payment` n'a pas de `practitioner_id`).
        let collected_row = sqlx::query(
            "SELECT \
               (COALESCE(SUM(amount) FILTER (WHERE created_at >= $1 AND created_at < $2), 0) * 100)::bigint \
                 AS collected_today_cents, \
               (COALESCE(SUM(amount) FILTER (WHERE created_at >= $3 AND created_at < $4), 0) * 100)::bigint \
                 AS collected_month_cents \
             FROM payment \
             WHERE cabinet_id = $5 AND status = 'paid' \
               AND patient_id IN ( \
                 SELECT DISTINCT patient_id FROM consultation_act \
                 WHERE cabinet_id = $5 AND practitioner_id = $6 \
               )",
        )
        .bind(day_start_utc)
        .bind(day_end_utc)
        .bind(month_start_utc)
        .bind(month_end_utc)
        .bind(cabinet_id)
        .bind(practitioner_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        let collected_today_cents: i64 = collected_row
            .try_get("collected_today_cents")
            .map_err(|_| AppError::Internal)?;
        let collected_month_cents: i64 = collected_row
            .try_get("collected_month_cents")
            .map_err(|_| AppError::Internal)?;

        let appointments_today: i64 = sqlx::query(
            "SELECT COUNT(*)::bigint AS cnt FROM appointment \
             WHERE cabinet_id = $1 AND practitioner_id = $2 AND deleted_at IS NULL \
               AND status NOT IN ('cancelled', 'no_show') \
               AND starts_at >= $3 AND starts_at < $4",
        )
        .bind(cabinet_id)
        .bind(practitioner_id)
        .bind(day_start_utc)
        .bind(day_end_utc)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get("cnt")
        .map_err(|_| AppError::Internal)?;

        let pending_reminders: i64 = sqlx::query(
            "SELECT COUNT(*)::bigint AS cnt FROM reminder r \
             JOIN appointment a ON a.id = r.appointment_id \
             WHERE r.cabinet_id = $1 AND a.practitioner_id = $2 AND r.status = 'pending'",
        )
        .bind(cabinet_id)
        .bind(practitioner_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get("cnt")
        .map_err(|_| AppError::Internal)?;

        // Occupation semaine courante : `availability_slot` (pas de RLS,
        // migration 0011 §« Entités plateforme SANS cabinet_id ») filtré
        // explicitement par cabinet+praticien, comme `list_cabinet_slots`.
        let occupancy_row = sqlx::query(
            "SELECT \
               COUNT(*) FILTER (WHERE status IN ('open', 'held', 'booked'))::bigint AS opened, \
               COUNT(*) FILTER (WHERE status = 'booked')::bigint AS reserved \
             FROM availability_slot \
             WHERE cabinet_id = $1 AND practitioner_id = $2 AND deleted_at IS NULL \
               AND starts_at >= $3 AND starts_at < $4",
        )
        .bind(cabinet_id)
        .bind(practitioner_id)
        .bind(week_start_utc)
        .bind(week_end_utc)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        let opened: i64 = occupancy_row
            .try_get("opened")
            .map_err(|_| AppError::Internal)?;
        let reserved: i64 = occupancy_row
            .try_get("reserved")
            .map_err(|_| AppError::Internal)?;

        let objective_target_cents: Option<i64> = if let Some(pid) = provider_id {
            sqlx::query(
                "SELECT target_cents FROM practitioner_objective \
                 WHERE cabinet_id = $1 AND provider_id = $2 AND month = $3",
            )
            .bind(cabinet_id)
            .bind(pid)
            .bind(month_start)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .map(|r| r.try_get("target_cents"))
            .transpose()
            .map_err(|_| AppError::Internal)?
        } else {
            None
        };

        tx.commit().await.map_err(|_| AppError::Internal)?;

        let occupancy_rate = (opened > 0).then(|| reserved as f64 / opened as f64);
        let objective_achieved_pct = objective_target_cents
            .filter(|t| *t > 0)
            .map(|t| billed_month_cents as f64 / t as f64);

        total_billed_today_cents += billed_today_cents;
        total_collected_today_cents += collected_today_cents;
        total_billed_month_cents += billed_month_cents;
        total_collected_month_cents += collected_month_cents;
        total_appointments_today += appointments_today;
        total_pending_reminders += pending_reminders;
        total_opened_week += opened;
        total_reserved_week += reserved;
        if let Some(t) = objective_target_cents {
            total_objective_target_cents = Some(total_objective_target_cents.unwrap_or(0) + t);
        }

        by_cabinet.push(CabinetKpiItem {
            cabinet_id,
            cabinet_name,
            today: KpiAmounts {
                billed_cents: billed_today_cents,
                collected_cents: collected_today_cents,
            },
            month: KpiAmounts {
                billed_cents: billed_month_cents,
                collected_cents: collected_month_cents,
            },
            appointments_today,
            pending_reminders,
            occupancy_rate,
            objective_target_cents,
            objective_achieved_pct,
        });
    }

    let occupancy_rate =
        (total_opened_week > 0).then(|| total_reserved_week as f64 / total_opened_week as f64);
    let objective_achieved_pct = total_objective_target_cents
        .filter(|t| *t > 0)
        .map(|t| total_billed_month_cents as f64 / t as f64);

    tracing::info!(
        user_id = %claims.sub,
        cabinets = by_cabinet.len(),
        "practitioner kpis fetched"
    );

    Ok(Json(PractitionerKpisResponse {
        period_month: month_start.format("%Y-%m-%d").to_string(),
        today: KpiAmounts {
            billed_cents: total_billed_today_cents,
            collected_cents: total_collected_today_cents,
        },
        month: KpiAmounts {
            billed_cents: total_billed_month_cents,
            collected_cents: total_collected_month_cents,
        },
        appointments_today: total_appointments_today,
        pending_reminders: total_pending_reminders,
        occupancy_rate,
        objective_target_cents: total_objective_target_cents,
        objective_achieved_pct,
        by_cabinet,
    }))
}

// ---------------------------------------------------------------------------
// CRUD `/v1/cabinet/practitioner-objectives` (#7189) — manager/admin.
// ---------------------------------------------------------------------------

fn is_unique_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23505")
    )
}

#[derive(Serialize)]
pub struct ObjectiveItem {
    pub id: Uuid,
    pub cabinet_id: Uuid,
    pub provider_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_name: Option<String>,
    pub month: String,
    pub target_cents: i64,
    pub created_by: Uuid,
    pub created_at: String,
}

fn objective_item_from_row(row: sqlx::postgres::PgRow) -> Result<ObjectiveItem, AppError> {
    let month: chrono::NaiveDate = row.try_get("month").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    Ok(ObjectiveItem {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        cabinet_id: row.try_get("cabinet_id").map_err(|_| AppError::Internal)?,
        provider_id: row.try_get("provider_id").map_err(|_| AppError::Internal)?,
        provider_name: row
            .try_get("provider_name")
            .map_err(|_| AppError::Internal)?,
        month: month.format("%Y-%m-%d").to_string(),
        target_cents: row
            .try_get("target_cents")
            .map_err(|_| AppError::Internal)?,
        created_by: row.try_get("created_by").map_err(|_| AppError::Internal)?,
        created_at: created_at.to_rfc3339(),
    })
}

/// Recharge un objectif (avec `provider_name` joint) après un `INSERT`/`UPDATE`
/// — évite une sous-requête corrélée dans la clause `RETURNING`, même idiome
/// `LEFT JOIN` que `list_practitioner_objectives`.
async fn fetch_objective_row(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    id: Uuid,
) -> Result<sqlx::postgres::PgRow, AppError> {
    sqlx::query(
        "SELECT o.id, o.cabinet_id, o.provider_id, p.display_name AS provider_name, \
                o.month, o.target_cents, o.created_by, o.created_at \
         FROM practitioner_objective o \
         LEFT JOIN provider p ON p.id = o.provider_id \
         WHERE o.id = $1",
    )
    .bind(id)
    .fetch_one(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)
}

#[derive(Deserialize)]
pub struct ListObjectivesQuery {
    /// Filtre optionnel `YYYY-MM`.
    pub month: Option<String>,
    pub provider_id: Option<Uuid>,
}

/// `GET /v1/cabinet/practitioner-objectives?month=&provider_id=` — liste des
/// objectifs du cabinet. Manager/admin uniquement.
pub async fn list_practitioner_objectives(
    State(state): State<AppState>,
    claims: ProAdminOrManagerClaims,
    Query(params): Query<ListObjectivesQuery>,
) -> Result<Json<Vec<ObjectiveItem>>, AppError> {
    let month = params.month.as_deref().map(parse_month).transpose()?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT o.id, o.cabinet_id, o.provider_id, p.display_name AS provider_name, \
                o.month, o.target_cents, o.created_by, o.created_at \
         FROM practitioner_objective o \
         LEFT JOIN provider p ON p.id = o.provider_id \
         WHERE o.cabinet_id = $1 \
           AND ($2::date IS NULL OR o.month = $2) \
           AND ($3::uuid IS NULL OR o.provider_id = $3) \
         ORDER BY o.month DESC, p.display_name",
    )
    .bind(claims.cabinet_id)
    .bind(month)
    .bind(params.provider_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .into_iter()
        .map(objective_item_from_row)
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(data))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateObjectiveBody {
    pub provider_id: Uuid,
    /// `YYYY-MM`.
    pub month: String,
    pub target_cents: i64,
}

/// `POST /v1/cabinet/practitioner-objectives` — crée l'objectif de CA mensuel
/// d'un praticien du cabinet. Manager/admin uniquement.
/// `404` si `provider_id` n'appartient pas à ce cabinet, `422` si
/// `target_cents < 0`, `409` si un objectif existe déjà pour ce couple
/// (provider, mois).
pub async fn create_practitioner_objective(
    State(state): State<AppState>,
    claims: ProAdminOrManagerClaims,
    Json(body): Json<CreateObjectiveBody>,
) -> Result<(StatusCode, Json<ObjectiveItem>), AppError> {
    if body.target_cents < 0 {
        return Err(AppError::ValidationError);
    }
    let month = parse_month(&body.month)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let provider_exists = sqlx::query("SELECT 1 FROM provider WHERE id = $1 AND cabinet_id = $2")
        .bind(body.provider_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if provider_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let inserted_id: Uuid = sqlx::query(
        "INSERT INTO practitioner_objective \
           (cabinet_id, provider_id, month, target_cents, created_by) \
         VALUES ($1, $2, $3, $4, $5) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.provider_id)
    .bind(month)
    .bind(body.target_cents)
    .bind(claims.sub)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| {
        if is_unique_violation(&e) {
            AppError::ObjectiveAlreadyExists
        } else {
            AppError::Internal
        }
    })?
    .try_get("id")
    .map_err(|_| AppError::Internal)?;

    let row = fetch_objective_row(&mut tx, inserted_id).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        provider_id = %body.provider_id,
        month = %body.month,
        "practitioner objective created"
    );

    Ok((StatusCode::CREATED, Json(objective_item_from_row(row)?)))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchObjectiveBody {
    pub target_cents: i64,
}

/// `PATCH /v1/cabinet/practitioner-objectives/:id` — modifie le montant
/// cible. Manager/admin uniquement. `404` si l'objectif n'existe pas dans ce
/// cabinet.
pub async fn patch_practitioner_objective(
    State(state): State<AppState>,
    claims: ProAdminOrManagerClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchObjectiveBody>,
) -> Result<Json<ObjectiveItem>, AppError> {
    if body.target_cents < 0 {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let updated = sqlx::query(
        "UPDATE practitioner_objective SET target_cents = $1 \
         WHERE id = $2 AND cabinet_id = $3 \
         RETURNING id",
    )
    .bind(body.target_cents)
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if updated.is_none() {
        return Err(AppError::NotFound);
    }

    let row = fetch_objective_row(&mut tx, id).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(cabinet_id = %claims.cabinet_id, objective_id = %id, "practitioner objective updated");

    Ok(Json(objective_item_from_row(row)?))
}

/// `DELETE /v1/cabinet/practitioner-objectives/:id` — supprime un objectif.
/// Manager/admin uniquement. `404` si l'objectif n'existe pas dans ce cabinet.
pub async fn delete_practitioner_objective(
    State(state): State<AppState>,
    claims: ProAdminOrManagerClaims,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let deleted = sqlx::query(
        "DELETE FROM practitioner_objective WHERE id = $1 AND cabinet_id = $2 RETURNING id",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if deleted.is_none() {
        return Err(AppError::NotFound);
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(cabinet_id = %claims.cabinet_id, objective_id = %id, "practitioner objective deleted");

    Ok(StatusCode::NO_CONTENT)
}
