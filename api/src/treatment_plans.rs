//! Handler pour le parcours de soins patient :
//! GET /v1/treatment-plans — liste paginée des plans de traitement.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, ProPractitionerClaims},
    AppState,
};

/// Vérifie que le praticien appelant a eu au moins un `appointment` avec le
/// patient dans ce cabinet (403 sinon). Même garde §14 que
/// `dental_chart.rs`/`orthodontics.rs`/`periodontal_chart.rs`/`medical_record.rs`
/// (#4400 : absente ici, plans de traitement accessibles à tout praticien du
/// cabinet même sans relation de soin avec le patient). Appelant responsable
/// du 404 patient-inexistant en amont.
async fn ensure_care_relationship(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    patient_id: Uuid,
    cabinet_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
           AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(user_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    Ok(())
}

#[derive(Deserialize)]
pub struct ListTreatmentPlansQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

#[derive(Serialize)]
pub struct TreatmentPlanItem {
    pub id: Uuid,
    pub title: String,
    pub status: String,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

#[derive(Serialize)]
pub struct ListTreatmentPlansResponse {
    pub data: Vec<TreatmentPlanItem>,
    pub page: PageInfo,
}

fn encode_cursor(created_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", created_at.timestamp_micros(), id)
}

fn decode_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/treatment-plans` — parcours de soins patient : liste paginée des plans de traitement.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` (migration 0038).
/// Tri par `created_at DESC`. Pagination cursor-based (`limit` + `cursor`).
/// Aucun plan → `{ data: [], page: { limit } }`.
pub async fn list_treatment_plans(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(params): Query<ListTreatmentPlansQuery>,
) -> Result<Json<ListTreatmentPlansResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let fetch_limit = limit + 1;

    let cursor = params.cursor.as_deref().and_then(decode_cursor);

    let cursor_clause = if cursor.is_some() {
        " AND (tp.created_at < $2 OR (tp.created_at = $2 AND tp.id < $3))"
    } else {
        ""
    };

    let sql = format!(
        "SELECT tp.id, tp.title, tp.status, tp.created_at \
         FROM treatment_plan tp \
         WHERE tp.deleted_at IS NULL\
         {cursor_clause} \
         ORDER BY tp.created_at DESC, tp.id DESC \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — RLS treatment_plan_patient_read (migration 0038).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = match cursor {
        Some((cursor_at, cursor_id)) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cursor_at)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        None => sqlx::query(&sql)
            .bind(fetch_limit)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<TreatmentPlanItem> = Vec::with_capacity(visible.len());
    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let title: String = row.try_get("title").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        last_created_at = Some(created_at);
        last_id = Some(id);

        data.push(TreatmentPlanItem {
            id,
            title,
            status,
            created_at: created_at.to_rfc3339(),
        });
    }

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        account_id = %claims.account_id,
        count = data.len(),
        has_more,
        "treatment plans listed"
    );

    Ok(Json(ListTreatmentPlansResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}

// ---------------------------------------------------------------------------
// GET /v1/treatment-plans/:id
// ---------------------------------------------------------------------------

#[derive(Serialize)]
pub struct TreatmentPlanDetailItem {
    pub label: String,
    pub ccam_code: Option<String>,
    pub unit_amount_cents: i64,
    pub amo_part_cents: i64,
    pub amc_part_cents: i64,
}

#[derive(Serialize)]
pub struct TreatmentPlanPhase {
    pub id: Uuid,
    pub position: i32,
    pub title: String,
    pub status: String,
    pub items: Vec<TreatmentPlanDetailItem>,
}

#[derive(Serialize)]
pub struct TreatmentPlanDetailResponse {
    pub id: Uuid,
    pub title: String,
    pub status: String,
    pub total_cost_cents: i64,
    pub remaining_cents: i64,
    pub amo_part_cents: i64,
    pub amc_part_cents: i64,
    pub phases: Vec<TreatmentPlanPhase>,
}

/// `GET /v1/treatment-plans/:id` — détail d'un plan de traitement avec phases et actes.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` (migration 0038).
/// Vérifie que le plan appartient au patient (via policy RLS + `patient_account_id`).
/// `404 not_found` si l'id est inexistant ou hors patient.
pub async fn get_treatment_plan(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<TreatmentPlanDetailResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — RLS treatment_plan_patient_read (migration 0038).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Fetch the plan header (RLS ensures it belongs to this patient or returns nothing).
    let plan_row = sqlx::query(
        "SELECT tp.id, tp.cabinet_id, tp.title, tp.status \
         FROM treatment_plan tp \
         WHERE tp.id = $1 AND tp.deleted_at IS NULL",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let plan_id: Uuid = plan_row.try_get("id").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = plan_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let plan_title: String = plan_row.try_get("title").map_err(|_| AppError::Internal)?;
    let plan_status: String = plan_row.try_get("status").map_err(|_| AppError::Internal)?;

    // Scope cabinet — RLS treatment_phase / quote_item uses app.current_cabinet_id.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Fetch phases ordered by position.
    let phase_rows = sqlx::query(
        "SELECT tp2.id, tp2.position, tp2.title, tp2.status \
         FROM treatment_phase tp2 \
         WHERE tp2.plan_id = $1 \
         ORDER BY tp2.position ASC",
    )
    .bind(plan_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Fetch all quote_items linked to phases of this plan in one query.
    let item_rows = sqlx::query(
        "SELECT qi.phase_id, qi.label, qi.ccam_code, \
                (qi.unit_amount * 100)::bigint AS unit_amount_cents, \
                COALESCE((qi.amo_part * 100)::bigint, 0) AS amo_part_cents, \
                COALESCE((qi.amc_part * 100)::bigint, 0) AS amc_part_cents \
         FROM quote_item qi \
         JOIN treatment_phase tp3 ON tp3.id = qi.phase_id \
         WHERE tp3.plan_id = $1",
    )
    .bind(plan_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Group items by phase_id.
    let mut items_by_phase: std::collections::HashMap<Uuid, Vec<TreatmentPlanDetailItem>> =
        std::collections::HashMap::new();

    let mut total_cost_cents: i64 = 0;
    let mut total_amo_cents: i64 = 0;
    let mut total_amc_cents: i64 = 0;

    for row in &item_rows {
        let phase_id: Uuid = row.try_get("phase_id").map_err(|_| AppError::Internal)?;
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        let ccam_code: Option<String> = row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
        let unit_amount_cents: i64 = row
            .try_get("unit_amount_cents")
            .map_err(|_| AppError::Internal)?;
        let amo_part_cents: i64 = row
            .try_get("amo_part_cents")
            .map_err(|_| AppError::Internal)?;
        let amc_part_cents: i64 = row
            .try_get("amc_part_cents")
            .map_err(|_| AppError::Internal)?;

        total_cost_cents += unit_amount_cents;
        total_amo_cents += amo_part_cents;
        total_amc_cents += amc_part_cents;

        items_by_phase
            .entry(phase_id)
            .or_default()
            .push(TreatmentPlanDetailItem {
                label,
                ccam_code,
                unit_amount_cents,
                amo_part_cents,
                amc_part_cents,
            });
    }

    let remaining_cents = total_cost_cents - total_amo_cents - total_amc_cents;

    let phases = phase_rows
        .into_iter()
        .map(|row| {
            let phase_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let position: i32 = row.try_get("position").map_err(|_| AppError::Internal)?;
            let title: String = row.try_get("title").map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            let items = items_by_phase.remove(&phase_id).unwrap_or_default();
            Ok(TreatmentPlanPhase {
                id: phase_id,
                position,
                title,
                status,
                items,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        account_id = %claims.account_id,
        plan_id = %plan_id,
        "treatment plan detail fetched"
    );

    Ok(Json(TreatmentPlanDetailResponse {
        id: plan_id,
        title: plan_title,
        status: plan_status,
        total_cost_cents,
        remaining_cents,
        amo_part_cents: total_amo_cents,
        amc_part_cents: total_amc_cents,
        phases,
    }))
}

// ---------------------------------------------------------------------------
// POST /v1/cabinet/treatment-plans
// ---------------------------------------------------------------------------

/// Corps de `POST /v1/cabinet/treatment-plans`.
#[derive(Deserialize)]
pub struct CreateTreatmentPlanBody {
    pub patient_id: Uuid,
    pub title: String,
}

/// Réponse de `POST /v1/cabinet/treatment-plans`.
#[derive(Serialize)]
pub struct CreateTreatmentPlanResponse {
    pub plan_id: Uuid,
}

/// `POST /v1/cabinet/treatment-plans` — création d'un plan de traitement (§4.1).
///
/// Praticien uniquement (via `ProPractitionerClaims`). `cabinet_id` extrait du
/// JWT, jamais du body (invariant tenancy) — mêmes garanties que `dental_chart.rs`.
/// Patient inexistant ou hors tenant → 404. `title` vide → 422.
/// `practitioner_id` résolu depuis le JWT (`user_id` → ligne `practitioner` du
/// cabinet) ; laissé `NULL` si le praticien n'a pas de ligne `practitioner`
/// (ex. compte migré) — cohérent avec la colonne nullable en base.
/// Statut initial : `draft`. Réponse `201 { plan_id }`.
pub async fn create_treatment_plan(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Json(body): Json<CreateTreatmentPlanBody>,
) -> Result<(StatusCode, Json<CreateTreatmentPlanResponse>), AppError> {
    let title = body.title.trim().to_string();
    if title.is_empty() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le cloisonnement).
    let patient_exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(body.patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // #4400 : garde §14 (relation de soin), absente jusqu'ici sur les plans
    // de traitement alors que dossier/dental-chart/perio/ortho l'exigent.
    ensure_care_relationship(&mut tx, body.patient_id, claims.cabinet_id, claims.sub).await?;

    let practitioner_id: Option<Uuid> =
        sqlx::query("SELECT id FROM practitioner WHERE user_id = $1 AND cabinet_id = $2")
            .bind(claims.sub)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .map(|r| r.try_get("id"))
            .transpose()
            .map_err(|_| AppError::Internal)?;

    let plan_id: Uuid = sqlx::query(
        "INSERT INTO treatment_plan (cabinet_id, patient_id, practitioner_id, title, status) \
         VALUES ($1, $2, $3, $4, 'draft') RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.patient_id)
    .bind(practitioner_id)
    .bind(&title)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .try_get("id")
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %body.patient_id,
        plan_id = %plan_id,
        "treatment plan created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateTreatmentPlanResponse { plan_id }),
    ))
}

// ---------------------------------------------------------------------------
// GET /v1/cabinet/patients/:id/treatment-plans
// ---------------------------------------------------------------------------

/// Phase imbriquée dans `CabinetTreatmentPlanItem` (§4.1, écran praticien #4051).
#[derive(Serialize)]
pub struct CabinetTreatmentPhaseItem {
    pub id: Uuid,
    pub position: i32,
    pub title: String,
    pub status: String,
}

/// Plan de traitement d'un patient, avec ses phases (écran praticien #4051).
#[derive(Serialize)]
pub struct CabinetTreatmentPlanItem {
    pub id: Uuid,
    pub title: String,
    pub status: String,
    pub created_at: String,
    pub phases: Vec<CabinetTreatmentPhaseItem>,
}

/// Réponse de `GET /v1/cabinet/patients/:id/treatment-plans`.
#[derive(Serialize)]
pub struct ListCabinetTreatmentPlansResponse {
    pub data: Vec<CabinetTreatmentPlanItem>,
}

/// `GET /v1/cabinet/patients/:id/treatment-plans` — plans de traitement d'un
/// patient, avec leurs phases (écran praticien #4051 : liste + création).
///
/// Praticien uniquement (via `ProPractitionerClaims`). `cabinet_id` extrait du
/// JWT, jamais du path (invariant tenancy). Patient inexistant ou hors tenant
/// → 404. Tri des plans par `created_at DESC`, des phases par `position ASC`.
pub async fn list_cabinet_treatment_plans(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<ListCabinetTreatmentPlansResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le cloisonnement).
    let patient_exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // #4400 : garde §14 (relation de soin), absente jusqu'ici sur les plans
    // de traitement alors que dossier/dental-chart/perio/ortho l'exigent.
    ensure_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub).await?;

    let plan_rows = sqlx::query(
        "SELECT id, title, status, created_at FROM treatment_plan \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         ORDER BY created_at DESC",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let phase_rows = sqlx::query(
        "SELECT tph.id, tph.plan_id, tph.position, tph.title, tph.status \
         FROM treatment_phase tph \
         JOIN treatment_plan tp ON tp.id = tph.plan_id \
         WHERE tp.patient_id = $1 AND tp.cabinet_id = $2 AND tp.deleted_at IS NULL \
         ORDER BY tph.position ASC",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut phases_by_plan: std::collections::HashMap<Uuid, Vec<CabinetTreatmentPhaseItem>> =
        std::collections::HashMap::new();
    for row in &phase_rows {
        let plan_id: Uuid = row.try_get("plan_id").map_err(|_| AppError::Internal)?;
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let position: i32 = row.try_get("position").map_err(|_| AppError::Internal)?;
        let title: String = row.try_get("title").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        phases_by_plan
            .entry(plan_id)
            .or_default()
            .push(CabinetTreatmentPhaseItem {
                id,
                position,
                title,
                status,
            });
    }

    let mut data = Vec::with_capacity(plan_rows.len());
    for row in &plan_rows {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let title: String = row.try_get("title").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        data.push(CabinetTreatmentPlanItem {
            phases: phases_by_plan.remove(&id).unwrap_or_default(),
            id,
            title,
            status,
            created_at: created_at.to_rfc3339(),
        });
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        patient_id = %patient_id,
        count = data.len(),
        "cabinet treatment plans listed"
    );

    Ok(Json(ListCabinetTreatmentPlansResponse { data }))
}
