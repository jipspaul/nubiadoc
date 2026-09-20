//! Conformité ARS/DMSM (#7170, suite de #7171 — schéma `compliance_item`/
//! `custom_device_declaration`, migration 0289) :
//! - `GET`/`POST /v1/cabinet/compliance-items` : échéancier de conformité du
//!   cabinet (formation, contrôle d'équipement, registre, autre).
//! - `PATCH`/`DELETE /v1/cabinet/compliance-items/:id` : édition/suppression
//!   d'un item non clôturé.
//! - `POST /v1/cabinet/compliance-items/:id/complete` : clôture un item —
//!   si `recurrence_months` est renseigné, recrée automatiquement l'item
//!   suivant (`due_date` = ancienne échéance + N mois), même logique qu'un
//!   contrôle périodique d'autoclave qui se répète indéfiniment.
//! - `POST /v1/patients/:id/custom-device-declarations` : déclaration DMSM
//!   (dispositif médical sur mesure), génère le PDF réglementaire et le
//!   stocke comme document patient (`category = 'dmsm'`, migration 0290).
//!
//! Alertes J-30/J-7/échu : calculées à la volée sur `due_date` à chaque
//! lecture (`alert_level`), jamais persistées — même choix que
//! `patient_alerts.rs` (pas de job de fond dans ce lot, l'échéancier reste
//! la source de vérité). Un item `done` n'alerte plus jamais.
//!
//! `ProSecretaryPlusClaims` (secretary/practitioner/admin/manager) : suivre
//! l'échéancier réglementaire et déclarer un DMSM sont des tâches
//! administratives du cabinet, pas des décisions cliniques — même doctrine
//! que `sterilization.rs`. La grille de contenu ARS (quels items existent
//! pour quelle inspection) est hors périmètre de ce moteur (action A-02
//! d'Abir, cf. issue #7170) : cet endpoint ne fait qu'outiller un
//! échéancier libre, sans connaître le contenu métier de la grille.

use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    patient_tags::ensure_secretary_scope,
    pdf_text, text_validation, AppState, ObjectStorage,
};

/// Valeurs de `compliance_item.kind` (CHECK, migration 0289).
const VALID_KINDS: [&str; 4] = ["training", "equipment_check", "register", "other"];

/// Bornes hautes sur les champs texte libres — même doctrine que
/// `letters::MAX_NAME_CHARS`/`cabinet_tasks::MAX_TASK_TITLE_LEN` (#7226 et
/// suites) : ne jamais livrer un module texte sans borne haute.
const MAX_LABEL_LEN: usize = 200;
const MAX_EQUIPMENT_LABEL_LEN: usize = 200;
const MAX_LAB_NAME_LEN: usize = 200;
const MAX_DEVICE_DESCRIPTION_LEN: usize = 2_000;

/// Plafond métier réaliste (#7486) : sans borne haute, un `recurrence_months`
/// démesuré passait en 201 puis faisait déborder `NaiveDate::checked_add_months`
/// à la clôture (`None` → 500 systématique, item inclôturable). Une
/// périodicité de conformité se compte en mois, au plus quelques dizaines
/// d'années : 1200 mois = 100 ans, largement suffisant.
const MAX_RECURRENCE_MONTHS: i32 = 1_200;

/// Seuils d'alerte dashboard (jours avant `due_date`), du plus urgent au
/// moins urgent.
const ALERT_DUE_J7_DAYS: i64 = 7;
const ALERT_DUE_J30_DAYS: i64 = 30;

/// `échu` si `due_date` déjà dépassée, `due_j7`/`due_j30` sinon selon le
/// nombre de jours restants — `None` pour un item `done` (jamais d'alerte
/// sur un item clôturé) ou hors fenêtre des 30 jours.
fn alert_level(
    status: &str,
    due_date: chrono::NaiveDate,
    today: chrono::NaiveDate,
) -> Option<&'static str> {
    if status == "done" {
        return None;
    }
    let days_remaining = (due_date - today).num_days();
    if days_remaining < 0 {
        Some("overdue")
    } else if days_remaining <= ALERT_DUE_J7_DAYS {
        Some("due_j7")
    } else if days_remaining <= ALERT_DUE_J30_DAYS {
        Some("due_j30")
    } else {
        None
    }
}

/// Vérifie que `subject_user_id`, quand fourni, est bien membre de ce
/// cabinet (`cabinet_membership`) — même garde que
/// `cabinet_tasks::validate_task_refs` pour `assignee_user_id`, pré-vérifiée
/// pour ne pas laisser remonter la violation de FK simple (`app_user(id)`,
/// migration 0289) en `500`.
async fn validate_subject_user(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    subject_user_id: Option<Uuid>,
) -> Result<(), AppError> {
    if let Some(user_id) = subject_user_id {
        let exists =
            sqlx::query("SELECT 1 FROM cabinet_membership WHERE cabinet_id = $1 AND user_id = $2")
                .bind(cabinet_id)
                .bind(user_id)
                .fetch_optional(&mut **tx)
                .await
                .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::NotFound);
        }
    }
    Ok(())
}

/// Valide les champs texte/numériques communs à la création et à l'édition
/// d'un item. Retourne les valeurs normalisées (`label`/`equipment_label`
/// coupés des espaces superflus).
fn validate_item_fields(
    kind: Option<&str>,
    label: &str,
    equipment_label: Option<&str>,
    recurrence_months: Option<i32>,
) -> Result<(String, Option<String>), AppError> {
    if let Some(kind) = kind {
        if !VALID_KINDS.contains(&kind) {
            return Err(AppError::ValidationError);
        }
    }
    let label = label.trim();
    if label.is_empty() {
        return Err(AppError::ValidationError);
    }
    text_validation::reject_nul_byte(label)?;
    text_validation::validate_max_len(label, MAX_LABEL_LEN)?;

    let equipment_label = match equipment_label {
        Some(v) => {
            let v = v.trim();
            if v.is_empty() {
                return Err(AppError::ValidationError);
            }
            text_validation::reject_nul_byte(v)?;
            text_validation::validate_max_len(v, MAX_EQUIPMENT_LABEL_LEN)?;
            Some(v.to_string())
        }
        None => None,
    };

    if let Some(months) = recurrence_months {
        if months <= 0 || months > MAX_RECURRENCE_MONTHS {
            return Err(AppError::ValidationError);
        }
    }

    Ok((label.to_string(), equipment_label))
}

// ── GET/POST /v1/cabinet/compliance-items ────────────────────────────────────

/// Un item de l'échéancier de conformité.
#[derive(Serialize)]
pub struct ComplianceItemDto {
    pub id: Uuid,
    pub kind: String,
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subject_user_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub equipment_label: Option<String>,
    pub due_date: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recurrence_months: Option<i32>,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub done_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub evidence_document_id: Option<Uuid>,
    /// `overdue` | `due_j7` | `due_j30` | absent (pas d'alerte), cf.
    /// [`alert_level`]. Calculé à la lecture, jamais persisté.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub alert_level: Option<&'static str>,
    pub created_at: String,
}

fn compliance_item_dto_from_row(
    row: &sqlx::postgres::PgRow,
    today: chrono::NaiveDate,
) -> Result<ComplianceItemDto, AppError> {
    let due_date: chrono::NaiveDate = row.try_get("due_date").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let done_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("done_at").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    Ok(ComplianceItemDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        kind: row.try_get("kind").map_err(|_| AppError::Internal)?,
        label: row.try_get("label").map_err(|_| AppError::Internal)?,
        subject_user_id: row
            .try_get("subject_user_id")
            .map_err(|_| AppError::Internal)?,
        equipment_label: row
            .try_get("equipment_label")
            .map_err(|_| AppError::Internal)?,
        due_date: due_date.to_string(),
        recurrence_months: row
            .try_get("recurrence_months")
            .map_err(|_| AppError::Internal)?,
        alert_level: alert_level(&status, due_date, today),
        status,
        done_at: done_at.map(|d| d.to_rfc3339()),
        evidence_document_id: row
            .try_get("evidence_document_id")
            .map_err(|_| AppError::Internal)?,
        created_at: created_at.to_rfc3339(),
    })
}

/// `GET /v1/cabinet/compliance-items` — liste l'échéancier du cabinet,
/// échéance croissante. Chaque item porte `alert_level` (`overdue`/
/// `due_j7`/`due_j30`) calculé sur `due_date`, pour le dashboard.
pub async fn list_compliance_items(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<Vec<ComplianceItemDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, kind, label, subject_user_id, equipment_label, due_date, \
                recurrence_months, status, done_at, evidence_document_id, created_at \
         FROM compliance_item \
         WHERE cabinet_id = $1 \
         ORDER BY due_date ASC, created_at ASC",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let today = chrono::Utc::now().date_naive();
    let items = rows
        .iter()
        .map(|row| compliance_item_dto_from_row(row, today))
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(items))
}

/// Body de `POST /v1/cabinet/compliance-items`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateComplianceItemBody {
    pub kind: String,
    pub label: String,
    pub subject_user_id: Option<Uuid>,
    pub equipment_label: Option<String>,
    pub due_date: String,
    pub recurrence_months: Option<i32>,
}

/// Réponse de `POST /v1/cabinet/compliance-items`.
#[derive(Serialize)]
pub struct CreateComplianceItemResponse {
    pub item_id: Uuid,
}

/// `POST /v1/cabinet/compliance-items` — ajoute un item à l'échéancier.
///
/// `kind` ∈ `training`/`equipment_check`/`register`/`other`, `label` non
/// blanc (≤ [`MAX_LABEL_LEN`]), `due_date` au format `YYYY-MM-DD`,
/// `recurrence_months` dans `]0, MAX_RECURRENCE_MONTHS]` si fourni → `422`
/// sinon. `subject_user_id`, si fourni, doit être membre du cabinet → `404`
/// sinon.
pub async fn create_compliance_item(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateComplianceItemBody>,
) -> Result<(StatusCode, Json<CreateComplianceItemResponse>), AppError> {
    let (label, equipment_label) = validate_item_fields(
        Some(body.kind.as_str()),
        &body.label,
        body.equipment_label.as_deref(),
        body.recurrence_months,
    )?;
    let due_date = chrono::NaiveDate::parse_from_str(&body.due_date, "%Y-%m-%d")
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    validate_subject_user(&mut tx, claims.cabinet_id, body.subject_user_id).await?;

    let row = sqlx::query(
        "INSERT INTO compliance_item \
         (cabinet_id, kind, label, subject_user_id, equipment_label, due_date, recurrence_months) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(&body.kind)
    .bind(&label)
    .bind(body.subject_user_id)
    .bind(&equipment_label)
    .bind(due_date)
    .bind(body.recurrence_months)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let item_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        item_id = %item_id,
        kind = %body.kind,
        "compliance item created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateComplianceItemResponse { item_id }),
    ))
}

// ── PATCH/DELETE /v1/cabinet/compliance-items/:id ────────────────────────────

/// Body de `PATCH /v1/cabinet/compliance-items/:id`. Un champ absent
/// conserve la valeur existante (même contrat que
/// `cabinet_tasks::PatchCabinetTaskBody`).
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchComplianceItemBody {
    pub label: Option<String>,
    pub subject_user_id: Option<Uuid>,
    pub equipment_label: Option<String>,
    pub due_date: Option<String>,
    pub recurrence_months: Option<i32>,
    /// Rattache le justificatif (attestation, rapport de contrôle) déjà
    /// présent au coffre-fort — seul moyen de le poser, `POST .../complete`
    /// n'accepte pas de body (même doctrine que
    /// `cabinet_tasks::complete_cabinet_task`).
    pub evidence_document_id: Option<Uuid>,
}

/// `PATCH /v1/cabinet/compliance-items/:id` — édite un item non clôturé.
///
/// Item inexistant/hors tenant → `404`. Item déjà `done` → `409
/// invalid_status` (un item clôturé est un enregistrement de conformité
/// figé — la ré-échéance passe par `POST .../complete` + récurrence, pas par
/// une édition, même doctrine append-only que `quote_locked`).
/// `subject_user_id`, si fourni, doit être membre du cabinet → `404` sinon.
/// `evidence_document_id`, si fourni, doit exister dans ce cabinet → `404`
/// sinon (pré-vérifié, FK composite migration 0289).
pub async fn patch_compliance_item(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchComplianceItemBody>,
) -> Result<Json<ComplianceItemDto>, AppError> {
    let due_date = body
        .due_date
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

    let existing = sqlx::query(
        "SELECT kind, label, subject_user_id, equipment_label, due_date, recurrence_months, \
                status, evidence_document_id, created_at \
         FROM compliance_item WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let status: String = existing.try_get("status").map_err(|_| AppError::Internal)?;
    if status == "done" {
        return Err(AppError::InvalidStatus);
    }

    let created_at: chrono::DateTime<chrono::Utc> = existing
        .try_get("created_at")
        .map_err(|_| AppError::Internal)?;
    let kind: String = existing.try_get("kind").map_err(|_| AppError::Internal)?;
    let existing_label: String = existing.try_get("label").map_err(|_| AppError::Internal)?;
    let existing_subject: Option<Uuid> = existing
        .try_get("subject_user_id")
        .map_err(|_| AppError::Internal)?;
    let existing_equipment: Option<String> = existing
        .try_get("equipment_label")
        .map_err(|_| AppError::Internal)?;
    let existing_due_date: chrono::NaiveDate = existing
        .try_get("due_date")
        .map_err(|_| AppError::Internal)?;
    let existing_recurrence: Option<i32> = existing
        .try_get("recurrence_months")
        .map_err(|_| AppError::Internal)?;
    let existing_evidence: Option<Uuid> = existing
        .try_get("evidence_document_id")
        .map_err(|_| AppError::Internal)?;

    let new_label_owned = body.label.clone().unwrap_or(existing_label);
    let new_equipment_label_owned = body.equipment_label.clone().or(existing_equipment);
    let new_recurrence_months = body.recurrence_months.or(existing_recurrence);
    let (new_label, new_equipment_label) = validate_item_fields(
        None,
        &new_label_owned,
        new_equipment_label_owned.as_deref(),
        new_recurrence_months,
    )?;
    let new_subject = body.subject_user_id.or(existing_subject);
    let new_due_date = due_date.unwrap_or(existing_due_date);
    let new_evidence = body.evidence_document_id.or(existing_evidence);

    validate_subject_user(&mut tx, claims.cabinet_id, new_subject).await?;
    if let Some(evidence_document_id) = body.evidence_document_id {
        let exists = sqlx::query("SELECT 1 FROM document WHERE id = $1 AND cabinet_id = $2")
            .bind(evidence_document_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    sqlx::query(
        "UPDATE compliance_item \
         SET label = $1, subject_user_id = $2, equipment_label = $3, due_date = $4, \
             recurrence_months = $5, evidence_document_id = $6 \
         WHERE id = $7 AND cabinet_id = $8",
    )
    .bind(&new_label)
    .bind(new_subject)
    .bind(&new_equipment_label)
    .bind(new_due_date)
    .bind(new_recurrence_months)
    .bind(new_evidence)
    .bind(id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        item_id = %id,
        "compliance item updated"
    );

    Ok(Json(ComplianceItemDto {
        id,
        kind,
        label: new_label,
        subject_user_id: new_subject,
        equipment_label: new_equipment_label,
        due_date: new_due_date.to_string(),
        recurrence_months: new_recurrence_months,
        status: status.clone(),
        done_at: None,
        evidence_document_id: new_evidence,
        alert_level: alert_level(&status, new_due_date, chrono::Utc::now().date_naive()),
        created_at: created_at.to_rfc3339(),
    }))
}

/// `DELETE /v1/cabinet/compliance-items/:id` — supprime un item non
/// clôturé. Item inexistant/hors tenant → `404`. Item `done` → `409
/// invalid_status` (même doctrine que `PATCH` : un item clôturé est
/// l'enregistrement de conformité, il ne s'efface pas).
pub async fn delete_compliance_item(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing =
        sqlx::query("SELECT status FROM compliance_item WHERE id = $1 AND cabinet_id = $2")
            .bind(id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;
    let status: String = existing.try_get("status").map_err(|_| AppError::Internal)?;
    if status == "done" {
        return Err(AppError::InvalidStatus);
    }

    sqlx::query("DELETE FROM compliance_item WHERE id = $1 AND cabinet_id = $2")
        .bind(id)
        .bind(claims.cabinet_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        item_id = %id,
        "compliance item deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}

// ── POST /v1/cabinet/compliance-items/:id/complete ───────────────────────────

/// Réponse de `POST /v1/cabinet/compliance-items/:id/complete`.
#[derive(Serialize)]
pub struct CompleteComplianceItemResponse {
    pub id: Uuid,
    pub status: String,
    /// Item recréé automatiquement si l'item clôturé portait
    /// `recurrence_months` — `None` sinon (item ponctuel).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_item_id: Option<Uuid>,
}

/// `POST /v1/cabinet/compliance-items/:id/complete` — clôture un item
/// (`status = 'done'`, `done_at = now()`). Pas de body (même contrat que
/// `cabinet_tasks::complete_cabinet_task`) — le justificatif se pose via
/// `PATCH .../:id` (`evidence_document_id`) avant la clôture, puisqu'un item
/// `done` n'est plus éditable.
///
/// Item inexistant/hors tenant → `404`. Item déjà `done` → `409
/// invalid_status` (même doctrine que `cabinet_tasks::complete_cabinet_task`
/// — une clôture n'est pas idempotente, elle ne se rejoue pas).
///
/// Récurrence (#7170) : si l'item clôturé porte `recurrence_months`, un
/// nouvel item `pending` est recréé avec la même définition (`kind`/
/// `label`/`subject_user_id`/`equipment_label`/`recurrence_months`) et
/// `due_date` = l'échéance clôturée + `recurrence_months` — jamais depuis la
/// date de clôture, pour ne pas faire dériver l'échéancier d'un contrôle
/// périodique clôturé en retard.
pub async fn complete_compliance_item(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<CompleteComplianceItemResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing = sqlx::query(
        "SELECT kind, label, subject_user_id, equipment_label, due_date, recurrence_months, status \
         FROM compliance_item WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let status: String = existing.try_get("status").map_err(|_| AppError::Internal)?;
    if status == "done" {
        return Err(AppError::InvalidStatus);
    }

    sqlx::query(
        "UPDATE compliance_item SET status = 'done', done_at = now() \
         WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let kind: String = existing.try_get("kind").map_err(|_| AppError::Internal)?;
    let label: String = existing.try_get("label").map_err(|_| AppError::Internal)?;
    let subject_user_id: Option<Uuid> = existing
        .try_get("subject_user_id")
        .map_err(|_| AppError::Internal)?;
    let equipment_label: Option<String> = existing
        .try_get("equipment_label")
        .map_err(|_| AppError::Internal)?;
    let due_date: chrono::NaiveDate = existing
        .try_get("due_date")
        .map_err(|_| AppError::Internal)?;
    let recurrence_months: Option<i32> = existing
        .try_get("recurrence_months")
        .map_err(|_| AppError::Internal)?;

    let next_item_id = match recurrence_months {
        Some(months) => {
            let next_due_date = due_date
                .checked_add_months(chrono::Months::new(months as u32))
                .ok_or(AppError::ValidationError)?;
            let row = sqlx::query(
                "INSERT INTO compliance_item \
                 (cabinet_id, kind, label, subject_user_id, equipment_label, due_date, recurrence_months) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7) \
                 RETURNING id",
            )
            .bind(claims.cabinet_id)
            .bind(&kind)
            .bind(&label)
            .bind(subject_user_id)
            .bind(&equipment_label)
            .bind(next_due_date)
            .bind(recurrence_months)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
            Some(row.try_get("id").map_err(|_| AppError::Internal)?)
        }
        None => None,
    };

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'complete_compliance_item', 'compliance_item', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        item_id = %id,
        next_item_id = ?next_item_id,
        "compliance item completed"
    );

    Ok(Json(CompleteComplianceItemResponse {
        id,
        status: "done".to_string(),
        next_item_id,
    }))
}

// ── POST /v1/patients/:id/custom-device-declarations ─────────────────────────

/// Body de `POST /v1/patients/:id/custom-device-declarations`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateCustomDeviceDeclarationBody {
    pub lab_name: String,
    pub device_description: String,
    pub consultation_act_id: Option<Uuid>,
}

/// Réponse de `POST /v1/patients/:id/custom-device-declarations`.
#[derive(Serialize)]
pub struct CreateCustomDeviceDeclarationResponse {
    pub declaration_id: Uuid,
    pub document_id: Uuid,
    pub filename: String,
    pub size_bytes: i64,
}

/// `POST /v1/patients/:id/custom-device-declarations` — déclare un
/// dispositif médical sur mesure (DMSM, obligation réglementaire pour une
/// prothèse/appareil fabriqué par un laboratoire sur prescription
/// individuelle) et génère le PDF de déclaration.
///
/// Patient inexistant/hors tenant/hors scope secrétariat (R10) → `404`.
/// `lab_name`/`device_description` non blancs (≤ [`MAX_LAB_NAME_LEN`]/
/// [`MAX_DEVICE_DESCRIPTION_LEN`]) → `422` sinon. `consultation_act_id`, si
/// fourni, doit exister dans ce cabinet ET appartenir à ce patient → `404`
/// sinon (pré-vérifié, FK composite migration 0289).
///
/// PDF produit par `pdf_text` (même moteur sans crate que courriers/devis/
/// ordonnances, DP-F7.a), stocké comme document patient (`document.category
/// = 'dmsm'`, migration 0290), audit `create_custom_device_declaration`.
pub async fn create_custom_device_declaration(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Extension(object_storage): Extension<std::sync::Arc<dyn ObjectStorage>>,
    Path(patient_id): Path<Uuid>,
    Json(body): Json<CreateCustomDeviceDeclarationBody>,
) -> Result<(StatusCode, Json<CreateCustomDeviceDeclarationResponse>), AppError> {
    let lab_name = body.lab_name.trim();
    let device_description = body.device_description.trim();
    if lab_name.is_empty() || device_description.is_empty() {
        return Err(AppError::ValidationError);
    }
    text_validation::reject_nul_byte(lab_name)?;
    text_validation::reject_nul_byte(device_description)?;
    text_validation::validate_max_len(lab_name, MAX_LAB_NAME_LEN)?;
    text_validation::validate_max_len(device_description, MAX_DEVICE_DESCRIPTION_LEN)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let patient_row = sqlx::query(
        "SELECT first_name, last_name, birth_date FROM patient \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    ensure_secretary_scope(&mut tx, &claims, patient_id).await?;

    let first_name: String = patient_row
        .try_get("first_name")
        .map_err(|_| AppError::Internal)?;
    let last_name: String = patient_row
        .try_get("last_name")
        .map_err(|_| AppError::Internal)?;
    let birth_date: Option<chrono::NaiveDate> = patient_row
        .try_get("birth_date")
        .map_err(|_| AppError::Internal)?;

    let act_summary = match body.consultation_act_id {
        Some(act_id) => {
            let act_row = sqlx::query(
                "SELECT ccam_code, label FROM consultation_act \
                 WHERE id = $1 AND cabinet_id = $2 AND patient_id = $3",
            )
            .bind(act_id)
            .bind(claims.cabinet_id)
            .bind(patient_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;
            let ccam_code: String = act_row
                .try_get("ccam_code")
                .map_err(|_| AppError::Internal)?;
            let label: String = act_row.try_get("label").map_err(|_| AppError::Internal)?;
            Some(format!("{ccam_code} — {label}"))
        }
        None => None,
    };

    let cab_row = sqlx::query("SELECT raison_sociale FROM cabinet WHERE id = $1")
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::Internal)?;
    let cabinet_name: String = cab_row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;

    let declared_at = chrono::Utc::now();
    let birth_suffix = birth_date
        .map(|d| format!(" (né(e) le {})", d.format("%d/%m/%Y")))
        .unwrap_or_default();
    let mut body_text = format!(
        "Patient : {first_name} {last_name}{birth_suffix}\n\
         Laboratoire : {lab_name}\n\
         Description du dispositif : {device_description}\n"
    );
    if let Some(act_summary) = act_summary {
        body_text.push_str(&format!("Acte associé : {act_summary}\n"));
    }
    body_text.push_str(&format!(
        "Déclaré le {} à {}",
        crate::scheduling::format_paris_date(declared_at),
        crate::scheduling::format_paris_time(declared_at)
    ));

    let header = vec![
        cabinet_name,
        "Déclaration de dispositif médical sur mesure (DMSM)".to_string(),
    ];
    let body_lines = pdf_text::wrap_lines(&body_text, pdf_text::WRAP_COLUMNS);
    let pdf_bytes = pdf_text::build_text_pdf(&header, &body_lines, &[]);
    let size_bytes = pdf_bytes.len() as i64;
    let document_id = Uuid::new_v4();
    let storage_key = format!("dmsm/{}/{}.pdf", claims.cabinet_id, document_id);
    let filename = format!("dmsm-{document_id}.pdf");

    object_storage
        .upload(&storage_key, "application/pdf", pdf_bytes.clone())
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO document \
         (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, \
          sha256, scan_status, uploaded_by, size_bytes) \
         VALUES ($1, $2, $3, 'dmsm', $4, $5, 'application/pdf', \
                 encode(digest($6, 'sha256'), 'hex'), 'clean', $7, $8)",
    )
    .bind(document_id)
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(&storage_key)
    .bind(&filename)
    .bind(&pdf_bytes)
    .bind(claims.sub)
    .bind(size_bytes)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO custom_device_declaration \
         (cabinet_id, patient_id, consultation_act_id, lab_name, device_description, document_id) \
         VALUES ($1, $2, $3, $4, $5, $6) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(body.consultation_act_id)
    .bind(lab_name)
    .bind(device_description)
    .bind(document_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let declaration_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'create_custom_device_declaration', 'custom_device_declaration', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(declaration_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        declaration_id = %declaration_id,
        document_id = %document_id,
        size_bytes,
        "custom device declaration generated"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateCustomDeviceDeclarationResponse {
            declaration_id,
            document_id,
            filename,
            size_bytes,
        }),
    ))
}
