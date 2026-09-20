//! Handlers `GET /v1/cabinet/briefs/{day,week,prostheses}` (#7192, dépend de
//! #7208) — résumé structuré du cabinet : RDV par praticien (avec motif),
//! patients nouveaux, actes prévus, prothèses à poser, tâches ouvertes.
//!
//! Fenêtres jour/semaine : même découpe locale `Europe/Paris` que l'agenda
//! (`scheduling::cabinet_local_days_utc_range`, #6577), réutilisée plutôt que
//! dupliquée. `prostheses` réutilise la même fenêtre glissante que `week`
//! (7 jours à partir de `?date=`, aujourd'hui par défaut) : les bons de
//! travaux prothétiques ne sont pas rattachés à un jour précis comme les RDV.
//!
//! PDF : même moteur « sans crate » que les courriers/devis/ordonnances
//! (`pdf_text::build_text_pdf`, DP-F7.a) — pas de nouvelle dépendance.
//!
//! `ProSecretaryPlusClaims` (secretary/practitioner/admin) : lecture
//! cabinet-wide, même garde que `cabinet_tasks.rs`/`cabinet_stats.rs` (pas de
//! garde relation-de-soin — un brief de cabinet n'est pas un dossier
//! patient).

use std::collections::HashMap;

use axum::{
    extract::{Query, State},
    http::{header, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    cabinet_tasks::resolve_member_name,
    pdf_text,
    scheduling::{cabinet_local_days_utc_range, format_paris_date, format_paris_time},
    AppState,
};

/// Nombre de jours de la fenêtre `prostheses` (#7192) : les bons de travaux
/// n'ont pas de vue "semaine" dédiée côté lab-work-orders, on reprend la même
/// largeur que le brief hebdomadaire.
const PROSTHESES_WINDOW_DAYS: i64 = 7;

// ── Query commune ────────────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct BriefQuery {
    /// Date ISO `YYYY-MM-DD` de départ de la fenêtre (défaut : aujourd'hui,
    /// heure locale cabinet). Même paramètre que `AgendaQuery::date`.
    pub date: Option<String>,
}

fn parse_base_date(date: Option<&str>) -> Result<chrono::NaiveDate, AppError> {
    match date {
        Some(s) => {
            chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").map_err(|_| AppError::ValidationError)
        }
        None => Ok(crate::scheduling::paris_today()),
    }
}

// ── Structures de réponse ────────────────────────────────────────────────────

#[derive(Serialize)]
pub struct BriefAppointmentItem {
    pub id: Uuid,
    pub starts_at: String,
    pub patient_id: Uuid,
    pub patient_display_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub motif: Option<String>,
    pub status: String,
}

#[derive(Serialize)]
pub struct BriefPractitionerAppointments {
    pub practitioner_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub practitioner_display_name: Option<String>,
    pub appointments: Vec<BriefAppointmentItem>,
}

#[derive(Serialize)]
pub struct BriefNewPatient {
    pub patient_id: Uuid,
    pub patient_display_name: String,
    pub appointment_id: Uuid,
    pub starts_at: String,
}

#[derive(Serialize)]
pub struct BriefPlannedAct {
    pub motif: String,
    pub count: i64,
}

#[derive(Serialize)]
pub struct BriefProsthesis {
    pub id: Uuid,
    pub patient_id: Uuid,
    pub patient_display_name: String,
    pub appointment_id: Uuid,
    pub appointment_starts_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tooth_fdi: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub work_nature: Option<String>,
    pub lab_name: String,
    pub status: String,
}

#[derive(Serialize)]
pub struct BriefOpenTask {
    pub id: Uuid,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assignee_display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub patient_display_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub due_date: Option<String>,
}

#[derive(Serialize)]
pub struct CabinetBriefResponse {
    /// "day" | "week" | "prostheses".
    pub view: String,
    pub range_start: String,
    pub range_end: String,
    pub appointments_by_practitioner: Vec<BriefPractitionerAppointments>,
    pub new_patients: Vec<BriefNewPatient>,
    pub planned_acts: Vec<BriefPlannedAct>,
    pub prostheses_to_fit: Vec<BriefProsthesis>,
    pub open_tasks: Vec<BriefOpenTask>,
}

// ── Requêtes SQL par section ─────────────────────────────────────────────────

/// RDV du cabinet dans `[range_start, range_end[`, groupés par praticien
/// (ordre d'apparition = premier RDV du praticien sur la période).
/// Annulés/absents exclus (même filtre que `scheduling::get_cabinet_agenda`).
async fn fetch_appointments_by_practitioner(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    range_start: chrono::DateTime<chrono::Utc>,
    range_end: chrono::DateTime<chrono::Utc>,
) -> Result<Vec<BriefPractitionerAppointments>, AppError> {
    let rows = sqlx::query(
        "SELECT a.id, a.starts_at, a.status, a.motif, a.patient_id, \
                p.first_name || ' ' || p.last_name AS patient_display_name, \
                a.practitioner_id, pv.display_name AS practitioner_display_name \
         FROM appointment a \
         JOIN patient p ON p.id = a.patient_id \
         LEFT JOIN provider pv \
           ON pv.practitioner_id = a.practitioner_id AND pv.cabinet_id = a.cabinet_id \
         WHERE a.cabinet_id = $1 AND a.deleted_at IS NULL \
           AND a.status NOT IN ('cancelled', 'no_show') \
           AND a.starts_at >= $2 AND a.starts_at < $3 \
         ORDER BY a.practitioner_id, a.starts_at ASC",
    )
    .bind(cabinet_id)
    .bind(range_start)
    .bind(range_end)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut groups: Vec<BriefPractitionerAppointments> = Vec::new();
    let mut index: HashMap<Uuid, usize> = HashMap::new();

    for row in &rows {
        let practitioner_id: Uuid = row
            .try_get("practitioner_id")
            .map_err(|_| AppError::Internal)?;
        let practitioner_display_name: Option<String> = row
            .try_get("practitioner_display_name")
            .map_err(|_| AppError::Internal)?;
        let starts_at: chrono::DateTime<chrono::Utc> =
            row.try_get("starts_at").map_err(|_| AppError::Internal)?;

        let item = BriefAppointmentItem {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            starts_at: starts_at.to_rfc3339(),
            patient_id: row.try_get("patient_id").map_err(|_| AppError::Internal)?,
            patient_display_name: row
                .try_get("patient_display_name")
                .map_err(|_| AppError::Internal)?,
            motif: row.try_get("motif").map_err(|_| AppError::Internal)?,
            status: row.try_get("status").map_err(|_| AppError::Internal)?,
        };

        let idx = *index.entry(practitioner_id).or_insert_with(|| {
            groups.push(BriefPractitionerAppointments {
                practitioner_id,
                practitioner_display_name,
                appointments: Vec::new(),
            });
            groups.len() - 1
        });
        groups[idx].appointments.push(item);
    }

    Ok(groups)
}

/// Patients dont le tout premier RDV du cabinet (tous statuts hors
/// annulé/absent, toutes dates confondues) tombe dans `[range_start,
/// range_end[` — c'est-à-dire les patients vus pour la première fois sur la
/// période.
async fn fetch_new_patients(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    range_start: chrono::DateTime<chrono::Utc>,
    range_end: chrono::DateTime<chrono::Utc>,
) -> Result<Vec<BriefNewPatient>, AppError> {
    let rows = sqlx::query(
        "SELECT p.id AS patient_id, p.first_name || ' ' || p.last_name AS patient_display_name, \
                first_appt.appointment_id, first_appt.starts_at \
         FROM ( \
             SELECT DISTINCT ON (patient_id) \
                    patient_id, id AS appointment_id, starts_at \
             FROM appointment \
             WHERE cabinet_id = $1 AND deleted_at IS NULL \
               AND status NOT IN ('cancelled', 'no_show') \
             ORDER BY patient_id, starts_at ASC \
         ) first_appt \
         JOIN patient p ON p.id = first_appt.patient_id \
         WHERE first_appt.starts_at >= $2 AND first_appt.starts_at < $3 \
         ORDER BY first_appt.starts_at ASC",
    )
    .bind(cabinet_id)
    .bind(range_start)
    .bind(range_end)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in &rows {
        let starts_at: chrono::DateTime<chrono::Utc> =
            row.try_get("starts_at").map_err(|_| AppError::Internal)?;
        data.push(BriefNewPatient {
            patient_id: row.try_get("patient_id").map_err(|_| AppError::Internal)?,
            patient_display_name: row
                .try_get("patient_display_name")
                .map_err(|_| AppError::Internal)?,
            appointment_id: row
                .try_get("appointment_id")
                .map_err(|_| AppError::Internal)?,
            starts_at: starts_at.to_rfc3339(),
        });
    }
    Ok(data)
}

/// Actes prévus sur la période : agrégation du `motif` des RDV (seule donnée
/// d'acte disponible en amont de la séance — `consultation_act` ne porte que
/// les actes déjà réalisés, cf. migration 0042).
async fn fetch_planned_acts(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    range_start: chrono::DateTime<chrono::Utc>,
    range_end: chrono::DateTime<chrono::Utc>,
) -> Result<Vec<BriefPlannedAct>, AppError> {
    let rows = sqlx::query(
        "SELECT motif, COUNT(*)::bigint AS act_count \
         FROM appointment \
         WHERE cabinet_id = $1 AND deleted_at IS NULL \
           AND status NOT IN ('cancelled', 'no_show') \
           AND starts_at >= $2 AND starts_at < $3 \
           AND motif IS NOT NULL AND btrim(motif) <> '' \
         GROUP BY motif \
         ORDER BY act_count DESC, motif ASC",
    )
    .bind(cabinet_id)
    .bind(range_start)
    .bind(range_end)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in &rows {
        data.push(BriefPlannedAct {
            motif: row.try_get("motif").map_err(|_| AppError::Internal)?,
            count: row.try_get("act_count").map_err(|_| AppError::Internal)?,
        });
    }
    Ok(data)
}

/// Bons de travaux prothétiques dont le RDV de pose tombe dans `[range_start,
/// range_end[` — généralisation de
/// `lab_work_orders::list_today_lab_work_orders` (#7208) à une fenêtre
/// arbitraire, sans garde relation-de-soin (vue cabinet, pas praticien).
async fn fetch_prostheses_to_fit(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    range_start: chrono::DateTime<chrono::Utc>,
    range_end: chrono::DateTime<chrono::Utc>,
) -> Result<Vec<BriefProsthesis>, AppError> {
    let rows = sqlx::query(
        "SELECT lwo.id, lwo.patient_id, \
                p.first_name || ' ' || p.last_name AS patient_display_name, \
                lwo.appointment_id, a.starts_at AS appointment_starts_at, \
                qi.tooth AS tooth_fdi, qi.label AS work_nature, \
                lwo.lab_name, lwo.status \
         FROM lab_work_order lwo \
         JOIN appointment a ON a.id = lwo.appointment_id \
         JOIN patient p ON p.id = lwo.patient_id \
         LEFT JOIN quote_item qi ON qi.id = lwo.quote_item_id \
         WHERE lwo.cabinet_id = $1 \
           AND a.deleted_at IS NULL \
           AND a.status NOT IN ('cancelled', 'no_show') \
           AND a.starts_at >= $2 AND a.starts_at < $3 \
         ORDER BY a.starts_at ASC",
    )
    .bind(cabinet_id)
    .bind(range_start)
    .bind(range_end)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in &rows {
        let appointment_starts_at: chrono::DateTime<chrono::Utc> = row
            .try_get("appointment_starts_at")
            .map_err(|_| AppError::Internal)?;
        data.push(BriefProsthesis {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            patient_id: row.try_get("patient_id").map_err(|_| AppError::Internal)?,
            patient_display_name: row
                .try_get("patient_display_name")
                .map_err(|_| AppError::Internal)?,
            appointment_id: row
                .try_get("appointment_id")
                .map_err(|_| AppError::Internal)?,
            appointment_starts_at: appointment_starts_at.to_rfc3339(),
            tooth_fdi: row.try_get("tooth_fdi").map_err(|_| AppError::Internal)?,
            work_nature: row.try_get("work_nature").map_err(|_| AppError::Internal)?,
            lab_name: row.try_get("lab_name").map_err(|_| AppError::Internal)?,
            status: row.try_get("status").map_err(|_| AppError::Internal)?,
        });
    }
    Ok(data)
}

/// Tâches ouvertes du cabinet (`cabinet_task.status = 'open'`), pas bornées
/// par la fenêtre jour/semaine : une tâche ouverte reste à traiter même sans
/// échéance ou avec une échéance passée (#7211).
async fn fetch_open_tasks(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
) -> Result<Vec<BriefOpenTask>, AppError> {
    let rows = sqlx::query(
        "SELECT t.id, t.title, t.due_date, t.assignee_user_id, \
                p.first_name AS patient_first_name, p.last_name AS patient_last_name \
         FROM cabinet_task t \
         LEFT JOIN patient p ON p.id = t.patient_id \
         WHERE t.cabinet_id = $1 AND t.status = 'open' \
         ORDER BY t.due_date ASC NULLS LAST, t.created_at DESC",
    )
    .bind(cabinet_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut name_cache: HashMap<Uuid, Option<String>> = HashMap::new();
    let mut data = Vec::with_capacity(rows.len());
    for row in &rows {
        let assignee_user_id: Option<Uuid> = row
            .try_get("assignee_user_id")
            .map_err(|_| AppError::Internal)?;
        let assignee_display_name = match assignee_user_id {
            Some(user_id) => resolve_member_name(tx, &mut name_cache, user_id).await?,
            None => None,
        };
        let patient_first_name: Option<String> = row
            .try_get("patient_first_name")
            .map_err(|_| AppError::Internal)?;
        let patient_last_name: Option<String> = row
            .try_get("patient_last_name")
            .map_err(|_| AppError::Internal)?;
        let patient_display_name = match (patient_first_name, patient_last_name) {
            (Some(first), Some(last)) => Some(format!("{first} {last}")),
            _ => None,
        };
        let due_date: Option<chrono::NaiveDate> =
            row.try_get("due_date").map_err(|_| AppError::Internal)?;

        data.push(BriefOpenTask {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            title: row.try_get("title").map_err(|_| AppError::Internal)?,
            assignee_display_name,
            patient_display_name,
            due_date: due_date.map(|d| d.to_string()),
        });
    }
    Ok(data)
}

/// Construit le brief complet (RDV, nouveaux patients, actes prévus,
/// prothèses à poser, tâches ouvertes) pour la fenêtre `[range_start,
/// range_end[`. Partagé par les vues JSON et PDF.
async fn build_full_brief(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    view: &str,
    range_start: chrono::DateTime<chrono::Utc>,
    range_end: chrono::DateTime<chrono::Utc>,
) -> Result<CabinetBriefResponse, AppError> {
    let appointments_by_practitioner =
        fetch_appointments_by_practitioner(tx, cabinet_id, range_start, range_end).await?;
    let new_patients = fetch_new_patients(tx, cabinet_id, range_start, range_end).await?;
    let planned_acts = fetch_planned_acts(tx, cabinet_id, range_start, range_end).await?;
    let prostheses_to_fit = fetch_prostheses_to_fit(tx, cabinet_id, range_start, range_end).await?;
    let open_tasks = fetch_open_tasks(tx, cabinet_id).await?;

    Ok(CabinetBriefResponse {
        view: view.to_string(),
        range_start: range_start.to_rfc3339(),
        range_end: range_end.to_rfc3339(),
        appointments_by_practitioner,
        new_patients,
        planned_acts,
        prostheses_to_fit,
        open_tasks,
    })
}

/// Construit le brief focalisé "prothèses à poser" — seule
/// `prostheses_to_fit` est renseignée, les autres sections restent vides
/// (endpoint dédié à l'impression pour le secrétariat/labo, cf. issue #7192).
async fn build_prostheses_brief(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    range_start: chrono::DateTime<chrono::Utc>,
    range_end: chrono::DateTime<chrono::Utc>,
) -> Result<CabinetBriefResponse, AppError> {
    let prostheses_to_fit = fetch_prostheses_to_fit(tx, cabinet_id, range_start, range_end).await?;

    Ok(CabinetBriefResponse {
        view: "prostheses".to_string(),
        range_start: range_start.to_rfc3339(),
        range_end: range_end.to_rfc3339(),
        appointments_by_practitioner: Vec::new(),
        new_patients: Vec::new(),
        planned_acts: Vec::new(),
        prostheses_to_fit,
        open_tasks: Vec::new(),
    })
}

async fn set_cabinet_guc(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
) -> Result<(), AppError> {
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
    Ok(())
}

/// Nom du cabinet pour l'en-tête PDF — DOIT être lu dans la même transaction
/// que le reste (GUC `app.current_cabinet_id` posé), `cabinet` étant
/// RLS-isolée sur sa propre clé (migration 0011) : une requête hors
/// transaction (pool nu, sans GUC) ne renverrait aucune ligne (fail-closed).
async fn fetch_cabinet_name(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
) -> Result<String, AppError> {
    let row = sqlx::query("SELECT raison_sociale FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
    Ok(match row {
        Some(row) => row.try_get("raison_sociale").unwrap_or_default(),
        None => String::new(),
    })
}

// ── GET /v1/cabinet/briefs/day ───────────────────────────────────────────────

/// `GET /v1/cabinet/briefs/day?date=` — brief du jour (#7192).
///
/// Token pro requis (secretary/practitioner/admin), `cabinet_id` extrait du
/// JWT. `?date=` (`YYYY-MM-DD`, défaut aujourd'hui) → `422 validation_error`
/// si non parsable. Fenêtre `[minuit local, minuit local + 1 jour[`, même
/// calcul que `GET /v1/cabinet/agenda?view=day`.
pub async fn day_brief(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<BriefQuery>,
) -> Result<Json<CabinetBriefResponse>, AppError> {
    let base_date = parse_base_date(params.date.as_deref())?;
    let (range_start, range_end) = cabinet_local_days_utc_range(base_date, 1)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_cabinet_guc(&mut tx, claims.cabinet_id).await?;
    let brief = build_full_brief(&mut tx, claims.cabinet_id, "day", range_start, range_end).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(cabinet_id = %claims.cabinet_id, view = "day", "cabinet brief fetched");

    Ok(Json(brief))
}

// ── GET /v1/cabinet/briefs/week ──────────────────────────────────────────────

/// `GET /v1/cabinet/briefs/week?date=` — brief de la semaine (#7192).
///
/// Mêmes garde/paramètres que [`day_brief`]. Fenêtre `[minuit local,
/// minuit local + 7 jours[` à partir de `?date=` (glissante, pas alignée sur
/// le lundi — même choix que `GET /v1/cabinet/agenda?view=week`).
pub async fn week_brief(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<BriefQuery>,
) -> Result<Json<CabinetBriefResponse>, AppError> {
    let base_date = parse_base_date(params.date.as_deref())?;
    let (range_start, range_end) = cabinet_local_days_utc_range(base_date, 7)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_cabinet_guc(&mut tx, claims.cabinet_id).await?;
    let brief =
        build_full_brief(&mut tx, claims.cabinet_id, "week", range_start, range_end).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(cabinet_id = %claims.cabinet_id, view = "week", "cabinet brief fetched");

    Ok(Json(brief))
}

// ── GET /v1/cabinet/briefs/prostheses ───────────────────────────────────────

/// `GET /v1/cabinet/briefs/prostheses?date=` — prothèses à poser (#7192).
///
/// Mêmes garde/paramètres que [`day_brief`]. Fenêtre de
/// [`PROSTHESES_WINDOW_DAYS`] jours à partir de `?date=`.
pub async fn prostheses_brief(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<BriefQuery>,
) -> Result<Json<CabinetBriefResponse>, AppError> {
    let base_date = parse_base_date(params.date.as_deref())?;
    let (range_start, range_end) = cabinet_local_days_utc_range(base_date, PROSTHESES_WINDOW_DAYS)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_cabinet_guc(&mut tx, claims.cabinet_id).await?;
    let brief = build_prostheses_brief(&mut tx, claims.cabinet_id, range_start, range_end).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(cabinet_id = %claims.cabinet_id, view = "prostheses", "cabinet brief fetched");

    Ok(Json(brief))
}

// ── Export PDF ────────────────────────────────────────────────────────────────

/// Traduit un brief en lignes de corps PDF (une section par bloc, séparées
/// par une ligne vide) — même mécanique de repli que `letters.rs`
/// (`pdf_text::wrap_lines`).
///
/// Vue `prostheses` (#7192) : brief focalisé, seule `prostheses_to_fit` est
/// renseignée (cf. [`build_prostheses_brief`]) — n'imprime que cette
/// section. Imprimer les 4 autres sections vidées à dessein afficherait de
/// fausses affirmations (« Aucun RDV », etc.) sur un document remis au labo
/// (#7410).
fn brief_body_lines(brief: &CabinetBriefResponse) -> Vec<String> {
    if brief.view == "prostheses" {
        let mut lines: Vec<String> = Vec::new();
        lines.push("PROTHÈSES À POSER".to_string());
        if brief.prostheses_to_fit.is_empty() {
            lines.push("Aucune prothèse à poser sur la période.".to_string());
        }
        for pr in &brief.prostheses_to_fit {
            let starts_at = chrono::DateTime::parse_from_rfc3339(&pr.appointment_starts_at)
                .map(|dt| format_paris_date(dt.with_timezone(&chrono::Utc)))
                .unwrap_or_default();
            lines.push(format!(
                "- {} {} — {} ({})",
                starts_at, pr.patient_display_name, pr.lab_name, pr.status
            ));
        }
        return lines;
    }

    let mut lines: Vec<String> = Vec::new();

    lines.push("RENDEZ-VOUS PAR PRATICIEN".to_string());
    if brief.appointments_by_practitioner.is_empty() {
        lines.push("Aucun RDV sur la période.".to_string());
    }
    for group in &brief.appointments_by_practitioner {
        lines.push(String::new());
        lines.push(format!(
            "- {}",
            group
                .practitioner_display_name
                .clone()
                .unwrap_or_else(|| "Praticien".to_string())
        ));
        for appt in &group.appointments {
            let starts_at = chrono::DateTime::parse_from_rfc3339(&appt.starts_at)
                .map(|dt| format_paris_time(dt.with_timezone(&chrono::Utc)))
                .unwrap_or_default();
            lines.push(format!(
                "  {} {} — {}",
                starts_at,
                appt.patient_display_name,
                appt.motif
                    .clone()
                    .unwrap_or_else(|| "Sans motif".to_string())
            ));
        }
    }

    lines.push(String::new());
    lines.push("PATIENTS NOUVEAUX".to_string());
    if brief.new_patients.is_empty() {
        lines.push("Aucun nouveau patient sur la période.".to_string());
    }
    for np in &brief.new_patients {
        lines.push(format!("- {}", np.patient_display_name));
    }

    lines.push(String::new());
    lines.push("ACTES PRÉVUS".to_string());
    if brief.planned_acts.is_empty() {
        lines.push("Aucun acte renseigné sur la période.".to_string());
    }
    for act in &brief.planned_acts {
        lines.push(format!("- {} × {}", act.count, act.motif));
    }

    lines.push(String::new());
    lines.push("PROTHÈSES À POSER".to_string());
    if brief.prostheses_to_fit.is_empty() {
        lines.push("Aucune prothèse à poser sur la période.".to_string());
    }
    for pr in &brief.prostheses_to_fit {
        let starts_at = chrono::DateTime::parse_from_rfc3339(&pr.appointment_starts_at)
            .map(|dt| format_paris_date(dt.with_timezone(&chrono::Utc)))
            .unwrap_or_default();
        lines.push(format!(
            "- {} {} — {} ({})",
            starts_at, pr.patient_display_name, pr.lab_name, pr.status
        ));
    }

    lines.push(String::new());
    lines.push("TÂCHES OUVERTES".to_string());
    if brief.open_tasks.is_empty() {
        lines.push("Aucune tâche ouverte.".to_string());
    }
    for task in &brief.open_tasks {
        lines.push(format!(
            "- {} (assigné : {}, échéance : {})",
            task.title,
            task.assignee_display_name
                .clone()
                .unwrap_or_else(|| "non assigné".to_string()),
            task.due_date
                .clone()
                .unwrap_or_else(|| "aucune".to_string()),
        ));
    }

    lines
}

fn brief_title(view: &str) -> &'static str {
    match view {
        "day" => "Brief du jour",
        "week" => "Brief de la semaine",
        _ => "Prothèses à poser",
    }
}

fn render_brief_pdf(
    cabinet_id: Uuid,
    cabinet_name: String,
    view: &str,
    range_start: chrono::DateTime<chrono::Utc>,
    range_end: chrono::DateTime<chrono::Utc>,
    brief: CabinetBriefResponse,
) -> Result<Response, AppError> {
    let header = vec![
        cabinet_name,
        format!(
            "{} — {} au {}",
            brief_title(view),
            format_paris_date(range_start),
            format_paris_date(range_end - chrono::Duration::seconds(1)),
        ),
    ];
    let footer = vec![format!(
        "Généré le {} à {}",
        format_paris_date(chrono::Utc::now()),
        format_paris_time(chrono::Utc::now())
    )];

    let body_lines: Vec<String> = brief_body_lines(&brief)
        .iter()
        .flat_map(|line| pdf_text::wrap_lines(line, pdf_text::WRAP_COLUMNS))
        .collect();
    let pdf_bytes = pdf_text::build_text_pdf(&header, &body_lines, &footer);

    tracing::info!(cabinet_id = %cabinet_id, view, "cabinet brief pdf generated");

    let filename = format!(
        "brief-{}-{}.pdf",
        view,
        format_paris_date(range_start).replace('/', "-")
    );
    let disposition = HeaderValue::from_str(&format!("inline; filename=\"{filename}\""))
        .map_err(|_| AppError::Internal)?;

    Ok((
        StatusCode::OK,
        [
            (
                header::CONTENT_TYPE,
                HeaderValue::from_static("application/pdf"),
            ),
            (header::CONTENT_DISPOSITION, disposition),
        ],
        pdf_bytes,
    )
        .into_response())
}

/// `GET /v1/cabinet/briefs/day.pdf?date=` — export PDF du brief du jour.
pub async fn day_brief_pdf(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<BriefQuery>,
) -> Result<Response, AppError> {
    let base_date = parse_base_date(params.date.as_deref())?;
    let (range_start, range_end) = cabinet_local_days_utc_range(base_date, 1)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_cabinet_guc(&mut tx, claims.cabinet_id).await?;
    let cabinet_name = fetch_cabinet_name(&mut tx, claims.cabinet_id).await?;
    let brief = build_full_brief(&mut tx, claims.cabinet_id, "day", range_start, range_end).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    render_brief_pdf(
        claims.cabinet_id,
        cabinet_name,
        "day",
        range_start,
        range_end,
        brief,
    )
}

/// `GET /v1/cabinet/briefs/week.pdf?date=` — export PDF du brief de la semaine.
pub async fn week_brief_pdf(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<BriefQuery>,
) -> Result<Response, AppError> {
    let base_date = parse_base_date(params.date.as_deref())?;
    let (range_start, range_end) = cabinet_local_days_utc_range(base_date, 7)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_cabinet_guc(&mut tx, claims.cabinet_id).await?;
    let cabinet_name = fetch_cabinet_name(&mut tx, claims.cabinet_id).await?;
    let brief =
        build_full_brief(&mut tx, claims.cabinet_id, "week", range_start, range_end).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    render_brief_pdf(
        claims.cabinet_id,
        cabinet_name,
        "week",
        range_start,
        range_end,
        brief,
    )
}

/// `GET /v1/cabinet/briefs/prostheses.pdf?date=` — export PDF des prothèses à poser.
pub async fn prostheses_brief_pdf(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<BriefQuery>,
) -> Result<Response, AppError> {
    let base_date = parse_base_date(params.date.as_deref())?;
    let (range_start, range_end) = cabinet_local_days_utc_range(base_date, PROSTHESES_WINDOW_DAYS)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_cabinet_guc(&mut tx, claims.cabinet_id).await?;
    let cabinet_name = fetch_cabinet_name(&mut tx, claims.cabinet_id).await?;
    let brief = build_prostheses_brief(&mut tx, claims.cabinet_id, range_start, range_end).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    render_brief_pdf(
        claims.cabinet_id,
        cabinet_name,
        "prostheses",
        range_start,
        range_end,
        brief,
    )
}
