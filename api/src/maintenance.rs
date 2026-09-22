//! Handlers `/v1/cabinet/equipment` et `/v1/cabinet/maintenance/*` (#7167,
//! DP-F18.b) : CRUD équipements du cabinet + tickets de maintenance, sur
//! `cabinet_equipment`/`maintenance_ticket`/`maintenance_ticket_photo`
//! (migration 0291, #7168).
//!
//! À la création d'un ticket, e-mail au technicien (`Mailer::
//! send_maintenance_ticket_created`) avec la description et les photos déjà
//! jointes — cible résolue depuis `assigned_to_email` (texte libre fourni à
//! la création) ou, à défaut, `cabinet_equipment.technician_email` de
//! l'équipement concerné. Aucune cible résolue → pas d'e-mail (no-op loggé),
//! même doctrine que `BrevoMailer` qui journalise plutôt que de faire
//! échouer l'appelant.
//!
//! Photos : réutilise le coffre-fort `document` (catégorie `photo`), même
//! pattern que `quote_attachments.rs` (upload générique puis rattachement
//! par `document_id`) — `POST /v1/cabinet/maintenance/photos` uploade la
//! pièce (cabinet-scopée, sans patient, cf. `upload_patient_document` dans
//! `clinical.rs` pour le même besoin côté dossier patient), puis
//! `POST /v1/cabinet/maintenance/tickets` référence les `document_id` déjà
//! uploadés via `photo_document_ids`.

use std::collections::HashSet;
use std::sync::Arc;

use axum::extract::{Extension, Multipart, Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{is_valid_email_format, AppError, ProSecretaryPlusClaims},
    text_validation, upload_storage, AppState, ObjectStorage,
};

const MAX_LABEL_LEN: usize = 200;
const MAX_SHORT_FIELD_LEN: usize = 200;
const MAX_TICKET_TITLE_LEN: usize = 200;
const MAX_TICKET_DESCRIPTION_LEN: usize = 4_000;
const VALID_PRIORITIES: [&str; 4] = ["low", "medium", "high", "urgent"];
const VALID_TICKET_STATUSES: [&str; 4] = ["open", "in_progress", "resolved", "cancelled"];
const MAX_PHOTO_SIZE: usize = 20 * 1024 * 1024;
const ALLOWED_PHOTO_MIMES: &[&str] = &["image/jpeg", "image/png"];

/// `422 validation_error` si `s` (une fois trim) dépasse `max_chars` ou
/// contient un octet NUL, sinon `Ok(())` — même garde que
/// `cabinet_correspondents.rs::validate_optional_field`.
fn validate_optional_field(s: &str, max_chars: usize) -> Result<(), AppError> {
    text_validation::reject_nul_byte(s)?;
    text_validation::validate_max_len(s, max_chars)
}

/// Trim `s`, renvoie `None` si le résultat est vide.
fn normalize_optional(s: Option<String>) -> Option<String> {
    s.map(|v| v.trim().to_string()).filter(|v| !v.is_empty())
}

/// Détecte une violation de contrainte FOREIGN KEY Postgres (SQLSTATE `23503`).
fn is_foreign_key_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23503")
    )
}

// ── Équipements ──────────────────────────────────────────────────────────

/// Un équipement du cabinet.
#[derive(Serialize)]
pub struct EquipmentDto {
    pub id: Uuid,
    pub label: String,
    pub category: String,
    pub room: Option<String>,
    pub supplier: Option<String>,
    pub technician_email: Option<String>,
    pub technician_phone: Option<String>,
    pub purchased_at: Option<String>,
    pub next_check_at: Option<String>,
    pub created_at: String,
}

fn equipment_dto_from_row(row: &sqlx::postgres::PgRow) -> Result<EquipmentDto, AppError> {
    let purchased_at: Option<chrono::NaiveDate> = row
        .try_get("purchased_at")
        .map_err(|_| AppError::Internal)?;
    let next_check_at: Option<chrono::NaiveDate> = row
        .try_get("next_check_at")
        .map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    Ok(EquipmentDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        label: row.try_get("label").map_err(|_| AppError::Internal)?,
        category: row.try_get("category").map_err(|_| AppError::Internal)?,
        room: row.try_get("room").map_err(|_| AppError::Internal)?,
        supplier: row.try_get("supplier").map_err(|_| AppError::Internal)?,
        technician_email: row
            .try_get("technician_email")
            .map_err(|_| AppError::Internal)?,
        technician_phone: row
            .try_get("technician_phone")
            .map_err(|_| AppError::Internal)?,
        purchased_at: purchased_at.map(|d| d.to_string()),
        next_check_at: next_check_at.map(|d| d.to_string()),
        created_at: created_at.to_rfc3339(),
    })
}

/// `GET /v1/cabinet/equipment` — liste l'inventaire du cabinet, trié par libellé.
pub async fn list_equipment(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<Vec<EquipmentDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, label, category, room, supplier, technician_email, technician_phone, \
                purchased_at, next_check_at, created_at \
         FROM cabinet_equipment ORDER BY label",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(equipment_dto_from_row)
        .collect::<Result<Vec<_>, AppError>>()?;
    Ok(Json(data))
}

/// Corps de `POST /v1/cabinet/equipment`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateEquipmentBody {
    pub label: String,
    pub category: String,
    pub room: Option<String>,
    pub supplier: Option<String>,
    pub technician_email: Option<String>,
    pub technician_phone: Option<String>,
    /// Date ISO `YYYY-MM-DD`.
    pub purchased_at: Option<String>,
    /// Date ISO `YYYY-MM-DD`.
    pub next_check_at: Option<String>,
}

/// `POST /v1/cabinet/equipment` — ajoute un équipement à l'inventaire.
///
/// `label`/`category` non blancs et bornés → `422` sinon. `technician_email`,
/// s'il est fourni, doit être syntaxiquement valide. `purchased_at`/
/// `next_check_at` doivent être des dates ISO valides → `422` sinon.
pub async fn create_equipment(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateEquipmentBody>,
) -> Result<(StatusCode, Json<EquipmentDto>), AppError> {
    let label = body.label.trim().to_string();
    if label.is_empty() {
        return Err(AppError::ValidationError);
    }
    validate_optional_field(&label, MAX_LABEL_LEN)?;
    let category = body.category.trim().to_string();
    if category.is_empty() {
        return Err(AppError::ValidationError);
    }
    validate_optional_field(&category, MAX_SHORT_FIELD_LEN)?;

    let room = normalize_optional(body.room);
    let supplier = normalize_optional(body.supplier);
    let technician_email = normalize_optional(body.technician_email);
    let technician_phone = normalize_optional(body.technician_phone);
    for field in [&room, &supplier, &technician_phone].into_iter().flatten() {
        validate_optional_field(field, MAX_SHORT_FIELD_LEN)?;
    }
    if let Some(email) = &technician_email {
        validate_optional_field(email, MAX_SHORT_FIELD_LEN)?;
        if !is_valid_email_format(email) {
            return Err(AppError::ValidationError);
        }
    }
    let purchased_at = body
        .purchased_at
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;
    let next_check_at = body
        .next_check_at
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

    let row = sqlx::query(
        "INSERT INTO cabinet_equipment \
         (cabinet_id, label, category, room, supplier, technician_email, technician_phone, \
          purchased_at, next_check_at) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) \
         RETURNING id, label, category, room, supplier, technician_email, technician_phone, \
                   purchased_at, next_check_at, created_at",
    )
    .bind(claims.cabinet_id)
    .bind(&label)
    .bind(&category)
    .bind(&room)
    .bind(&supplier)
    .bind(&technician_email)
    .bind(&technician_phone)
    .bind(purchased_at)
    .bind(next_check_at)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let dto = equipment_dto_from_row(&row)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'create_cabinet_equipment', 'cabinet_equipment', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(dto.id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        equipment_id = %dto.id,
        "cabinet equipment created"
    );

    Ok((StatusCode::CREATED, Json(dto)))
}

/// Corps de `PATCH /v1/cabinet/equipment/:id`. Champ absent = inchangé ;
/// champ optionnel fourni blanc l'efface (stocké `NULL`).
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchEquipmentBody {
    pub label: Option<String>,
    pub category: Option<String>,
    pub room: Option<String>,
    pub supplier: Option<String>,
    pub technician_email: Option<String>,
    pub technician_phone: Option<String>,
    pub purchased_at: Option<String>,
    pub next_check_at: Option<String>,
}

/// `PATCH /v1/cabinet/equipment/:id` — met à jour un équipement.
///
/// Équipement absent ou hors tenant → `404`. Mêmes bornes/validations que `POST`.
pub async fn patch_equipment(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchEquipmentBody>,
) -> Result<Json<EquipmentDto>, AppError> {
    if let Some(label) = &body.label {
        if label.trim().is_empty() {
            return Err(AppError::ValidationError);
        }
        validate_optional_field(label.trim(), MAX_LABEL_LEN)?;
    }
    if let Some(category) = &body.category {
        if category.trim().is_empty() {
            return Err(AppError::ValidationError);
        }
        validate_optional_field(category.trim(), MAX_SHORT_FIELD_LEN)?;
    }
    let room = body.room.map(|s| normalize_optional(Some(s)));
    let supplier = body.supplier.map(|s| normalize_optional(Some(s)));
    let technician_email = body.technician_email.map(|s| normalize_optional(Some(s)));
    let technician_phone = body.technician_phone.map(|s| normalize_optional(Some(s)));
    for field in [&room, &supplier, &technician_phone]
        .into_iter()
        .flatten()
        .flatten()
    {
        validate_optional_field(field, MAX_SHORT_FIELD_LEN)?;
    }
    if let Some(Some(email)) = &technician_email {
        validate_optional_field(email, MAX_SHORT_FIELD_LEN)?;
        if !is_valid_email_format(email) {
            return Err(AppError::ValidationError);
        }
    }
    let purchased_at = body
        .purchased_at
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;
    let next_check_at = body
        .next_check_at
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

    let current = sqlx::query(
        "SELECT label, category, room, supplier, technician_email, technician_phone, \
                purchased_at, next_check_at \
         FROM cabinet_equipment WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let new_label = body
        .label
        .map(|s| s.trim().to_string())
        .unwrap_or(current.try_get("label").map_err(|_| AppError::Internal)?);
    let new_category = body.category.map(|s| s.trim().to_string()).unwrap_or(
        current
            .try_get("category")
            .map_err(|_| AppError::Internal)?,
    );
    let new_room = room.unwrap_or(current.try_get("room").map_err(|_| AppError::Internal)?);
    let new_supplier = supplier.unwrap_or(
        current
            .try_get("supplier")
            .map_err(|_| AppError::Internal)?,
    );
    let new_technician_email = technician_email.unwrap_or(
        current
            .try_get("technician_email")
            .map_err(|_| AppError::Internal)?,
    );
    let new_technician_phone = technician_phone.unwrap_or(
        current
            .try_get("technician_phone")
            .map_err(|_| AppError::Internal)?,
    );
    let new_purchased_at = purchased_at.or(current
        .try_get("purchased_at")
        .map_err(|_| AppError::Internal)?);
    let new_next_check_at = next_check_at.or(current
        .try_get("next_check_at")
        .map_err(|_| AppError::Internal)?);

    let row = sqlx::query(
        "UPDATE cabinet_equipment \
         SET label = $1, category = $2, room = $3, supplier = $4, technician_email = $5, \
             technician_phone = $6, purchased_at = $7, next_check_at = $8 \
         WHERE id = $9 AND cabinet_id = $10 \
         RETURNING id, label, category, room, supplier, technician_email, technician_phone, \
                   purchased_at, next_check_at, created_at",
    )
    .bind(&new_label)
    .bind(&new_category)
    .bind(&new_room)
    .bind(&new_supplier)
    .bind(&new_technician_email)
    .bind(&new_technician_phone)
    .bind(new_purchased_at)
    .bind(new_next_check_at)
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let dto = equipment_dto_from_row(&row)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'update_cabinet_equipment', 'cabinet_equipment', $4)",
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
        equipment_id = %id,
        "cabinet equipment updated"
    );

    Ok(Json(dto))
}

/// `DELETE /v1/cabinet/equipment/:id` — retire un équipement de l'inventaire.
///
/// Équipement absent ou hors tenant → `404`. Référencé par un ticket de
/// maintenance (FK composite `(equipment_id, cabinet_id)`, migration 0291)
/// → `409 equipment_in_use` plutôt qu'un `500` sur la violation `23503`.
pub async fn delete_equipment(
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

    let deleted =
        sqlx::query("DELETE FROM cabinet_equipment WHERE id = $1 AND cabinet_id = $2 RETURNING id")
            .bind(id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|e| {
                if is_foreign_key_violation(&e) {
                    AppError::EquipmentInUse
                } else {
                    AppError::Internal
                }
            })?;

    if deleted.is_none() {
        return Err(AppError::NotFound);
    }

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'delete_cabinet_equipment', 'cabinet_equipment', $4)",
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
        equipment_id = %id,
        "cabinet equipment deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}

// ── Tickets de maintenance ───────────────────────────────────────────────

/// Un ticket de maintenance.
#[derive(Serialize)]
pub struct MaintenanceTicketDto {
    pub id: Uuid,
    pub equipment_id: Option<Uuid>,
    pub title: String,
    pub description: Option<String>,
    pub priority: String,
    pub status: String,
    pub reported_by: Uuid,
    pub assigned_to_email: Option<String>,
    pub created_at: String,
    pub resolved_at: Option<String>,
}

fn ticket_dto_from_row(row: &sqlx::postgres::PgRow) -> Result<MaintenanceTicketDto, AppError> {
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    let resolved_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("resolved_at").map_err(|_| AppError::Internal)?;
    Ok(MaintenanceTicketDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        equipment_id: row
            .try_get("equipment_id")
            .map_err(|_| AppError::Internal)?,
        title: row.try_get("title").map_err(|_| AppError::Internal)?,
        description: row.try_get("description").map_err(|_| AppError::Internal)?,
        priority: row.try_get("priority").map_err(|_| AppError::Internal)?,
        status: row.try_get("status").map_err(|_| AppError::Internal)?,
        reported_by: row.try_get("reported_by").map_err(|_| AppError::Internal)?,
        assigned_to_email: row
            .try_get("assigned_to_email")
            .map_err(|_| AppError::Internal)?,
        created_at: created_at.to_rfc3339(),
        resolved_at: resolved_at.map(|d| d.to_rfc3339()),
    })
}

/// Query de `GET /v1/cabinet/maintenance/tickets`.
#[derive(Deserialize)]
pub struct ListTicketsQuery {
    pub status: Option<String>,
    pub equipment_id: Option<Uuid>,
}

/// `GET /v1/cabinet/maintenance/tickets` — liste les tickets du cabinet,
/// filtrables par statut/équipement, tri création la plus récente d'abord.
///
/// `?status=` hors énum (CHECK, migration 0291) → `422`.
pub async fn list_tickets(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(query): Query<ListTicketsQuery>,
) -> Result<Json<Vec<MaintenanceTicketDto>>, AppError> {
    if let Some(ref status) = query.status {
        if !VALID_TICKET_STATUSES.contains(&status.as_str()) {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, equipment_id, title, description, priority, status, reported_by, \
                assigned_to_email, created_at, resolved_at \
         FROM maintenance_ticket \
         WHERE ($1::text IS NULL OR status = $1) \
           AND ($2::uuid IS NULL OR equipment_id = $2) \
         ORDER BY created_at DESC",
    )
    .bind(query.status.as_deref())
    .bind(query.equipment_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(ticket_dto_from_row)
        .collect::<Result<Vec<_>, AppError>>()?;
    Ok(Json(data))
}

/// Corps de `POST /v1/cabinet/maintenance/tickets`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateTicketBody {
    pub equipment_id: Option<Uuid>,
    pub title: String,
    pub description: Option<String>,
    pub priority: Option<String>,
    pub assigned_to_email: Option<String>,
    /// `document_id` de photos déjà uploadées via
    /// `POST /v1/cabinet/maintenance/photos` (catégorie `photo`).
    pub photo_document_ids: Option<Vec<Uuid>>,
}

/// `POST /v1/cabinet/maintenance/tickets` — crée un ticket (statut `open`).
///
/// `title` non blanc et borné, `description` bornée. `priority` ∈
/// `low, medium, high, urgent` (défaut `medium`) → `422` sinon.
/// `equipment_id`, si fourni, doit appartenir à ce cabinet → `404` sinon.
/// `assigned_to_email`, si fourni, doit être syntaxiquement valide.
/// `photo_document_ids`, si fournis, doivent référencer des documents
/// catégorie `photo` de ce cabinet → `422` sinon (dédoublonnés avant insertion).
///
/// E-mail au technicien (#7167) : cible = `assigned_to_email` ou, à défaut,
/// `cabinet_equipment.technician_email` de l'équipement concerné. Aucune
/// cible résolue → pas d'e-mail envoyé (loggé).
pub async fn create_ticket(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateTicketBody>,
) -> Result<(StatusCode, Json<MaintenanceTicketDto>), AppError> {
    let title = body.title.trim().to_string();
    if title.is_empty() {
        return Err(AppError::ValidationError);
    }
    validate_optional_field(&title, MAX_TICKET_TITLE_LEN)?;
    if let Some(ref description) = body.description {
        validate_optional_field(description, MAX_TICKET_DESCRIPTION_LEN)?;
    }
    let description = normalize_optional(body.description);
    let priority = body.priority.unwrap_or_else(|| "medium".to_string());
    if !VALID_PRIORITIES.contains(&priority.as_str()) {
        return Err(AppError::ValidationError);
    }
    let assigned_to_email = normalize_optional(body.assigned_to_email);
    if let Some(email) = &assigned_to_email {
        validate_optional_field(email, MAX_SHORT_FIELD_LEN)?;
        if !is_valid_email_format(email) {
            return Err(AppError::ValidationError);
        }
    }
    let mut seen = HashSet::new();
    let photo_document_ids: Vec<Uuid> = body
        .photo_document_ids
        .unwrap_or_default()
        .into_iter()
        .filter(|id| seen.insert(*id))
        .collect();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let equipment_technician_email = match body.equipment_id {
        Some(equipment_id) => {
            let row = sqlx::query(
                "SELECT technician_email FROM cabinet_equipment WHERE id = $1 AND cabinet_id = $2",
            )
            .bind(equipment_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;
            row.try_get::<Option<String>, _>("technician_email")
                .map_err(|_| AppError::Internal)?
        }
        None => None,
    };

    let row = sqlx::query(
        "INSERT INTO maintenance_ticket \
         (cabinet_id, equipment_id, title, description, priority, reported_by, assigned_to_email) \
         VALUES ($1, $2, $3, $4, $5, $6, $7) \
         RETURNING id, equipment_id, title, description, priority, status, reported_by, \
                   assigned_to_email, created_at, resolved_at",
    )
    .bind(claims.cabinet_id)
    .bind(body.equipment_id)
    .bind(&title)
    .bind(&description)
    .bind(&priority)
    .bind(claims.sub)
    .bind(&assigned_to_email)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let dto = ticket_dto_from_row(&row)?;

    let mut photo_filenames = Vec::with_capacity(photo_document_ids.len());
    for document_id in &photo_document_ids {
        let doc = sqlx::query(
            "SELECT filename FROM document \
             WHERE id = $1 AND cabinet_id = $2 AND category = 'photo' AND deleted_at IS NULL",
        )
        .bind(document_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::ValidationError)?;
        let filename: String = doc.try_get("filename").map_err(|_| AppError::Internal)?;

        sqlx::query(
            "INSERT INTO maintenance_ticket_photo (cabinet_id, ticket_id, document_id) \
             VALUES ($1, $2, $3)",
        )
        .bind(claims.cabinet_id)
        .bind(dto.id)
        .bind(document_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        photo_filenames.push(filename);
    }

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'create_maintenance_ticket', 'maintenance_ticket', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(dto.id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let technician_target = assigned_to_email.or(equipment_technician_email);
    match &technician_target {
        Some(email) => {
            state.mailer.send_maintenance_ticket_created(
                email,
                &title,
                description.as_deref(),
                &photo_filenames,
            );
            tracing::info!(
                cabinet_id = %claims.cabinet_id,
                ticket_id = %dto.id,
                "maintenance ticket email dispatched to technician"
            );
        }
        None => {
            tracing::info!(
                cabinet_id = %claims.cabinet_id,
                ticket_id = %dto.id,
                "maintenance ticket created without a resolvable technician email — no email sent"
            );
        }
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        ticket_id = %dto.id,
        "maintenance ticket created"
    );

    Ok((StatusCode::CREATED, Json(dto)))
}

/// Transition de statut valide via `PATCH` : `resolved`/`cancelled` sont
/// terminaux (aucune transition sortante, y compris vers eux-mêmes n'a de
/// sens à changer), le reste (`open`/`in_progress`) peut aller vers
/// n'importe quel autre statut.
fn is_valid_ticket_status_transition(current: &str, target: &str) -> bool {
    target == current || !matches!(current, "resolved" | "cancelled")
}

/// Corps de `PATCH /v1/cabinet/maintenance/tickets/:id`. Champ absent =
/// inchangé ; `description`/`assigned_to_email` fournis blancs effacent
/// (stockés `NULL`). `equipment_id` n'est pas modifiable après création.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchTicketBody {
    pub title: Option<String>,
    pub description: Option<String>,
    pub priority: Option<String>,
    pub assigned_to_email: Option<String>,
    pub status: Option<String>,
}

/// `PATCH /v1/cabinet/maintenance/tickets/:id` — met à jour un ticket.
///
/// Ticket absent/hors tenant → `404`. `status`/`priority` hors énum → `422`.
/// Ticket déjà `resolved`/`cancelled` (terminal) → `409 invalid_status` si un
/// changement de statut est demandé, même doctrine que
/// `cabinet_tasks.rs::is_valid_task_status_transition`. Passage à `resolved`
/// pose `resolved_at = now()` (contrainte `maintenance_ticket_resolved_consistency`,
/// migration 0291).
pub async fn patch_ticket(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchTicketBody>,
) -> Result<Json<MaintenanceTicketDto>, AppError> {
    if let Some(title) = &body.title {
        if title.trim().is_empty() {
            return Err(AppError::ValidationError);
        }
        validate_optional_field(title.trim(), MAX_TICKET_TITLE_LEN)?;
    }
    if let Some(priority) = &body.priority {
        if !VALID_PRIORITIES.contains(&priority.as_str()) {
            return Err(AppError::ValidationError);
        }
    }
    if let Some(status) = &body.status {
        if !VALID_TICKET_STATUSES.contains(&status.as_str()) {
            return Err(AppError::ValidationError);
        }
    }
    let description = body.description.map(|s| normalize_optional(Some(s)));
    if let Some(Some(description)) = &description {
        validate_optional_field(description, MAX_TICKET_DESCRIPTION_LEN)?;
    }
    let assigned_to_email = body.assigned_to_email.map(|s| normalize_optional(Some(s)));
    if let Some(Some(email)) = &assigned_to_email {
        validate_optional_field(email, MAX_SHORT_FIELD_LEN)?;
        if !is_valid_email_format(email) {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let current = sqlx::query(
        "SELECT title, description, priority, status, assigned_to_email \
         FROM maintenance_ticket WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let current_status: String = current.try_get("status").map_err(|_| AppError::Internal)?;
    let new_status = body.status.unwrap_or_else(|| current_status.clone());
    if !is_valid_ticket_status_transition(&current_status, &new_status) {
        return Err(AppError::InvalidStatus);
    }

    let new_title = body
        .title
        .map(|s| s.trim().to_string())
        .unwrap_or(current.try_get("title").map_err(|_| AppError::Internal)?);
    let new_description = description.unwrap_or(
        current
            .try_get("description")
            .map_err(|_| AppError::Internal)?,
    );
    let new_priority = body.priority.unwrap_or(
        current
            .try_get("priority")
            .map_err(|_| AppError::Internal)?,
    );
    let new_assigned_to_email = assigned_to_email.unwrap_or(
        current
            .try_get("assigned_to_email")
            .map_err(|_| AppError::Internal)?,
    );
    let resolved_now = new_status == "resolved" && current_status != "resolved";

    let row = sqlx::query(
        "UPDATE maintenance_ticket \
         SET title = $1, description = $2, priority = $3, assigned_to_email = $4, status = $5, \
             resolved_at = CASE WHEN $6 THEN now() ELSE resolved_at END \
         WHERE id = $7 AND cabinet_id = $8 \
         RETURNING id, equipment_id, title, description, priority, status, reported_by, \
                   assigned_to_email, created_at, resolved_at",
    )
    .bind(&new_title)
    .bind(&new_description)
    .bind(&new_priority)
    .bind(&new_assigned_to_email)
    .bind(&new_status)
    .bind(resolved_now)
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let dto = ticket_dto_from_row(&row)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'update_maintenance_ticket', 'maintenance_ticket', $4)",
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
        ticket_id = %id,
        status = %dto.status,
        "maintenance ticket updated"
    );

    Ok(Json(dto))
}

// ── Photos ────────────────────────────────────────────────────────────────

/// Réponse de `POST /v1/cabinet/maintenance/photos`.
#[derive(Serialize)]
pub struct UploadMaintenancePhotoResponse {
    pub document_id: Uuid,
    pub filename: String,
    pub size_bytes: i64,
}

/// `POST /v1/cabinet/maintenance/photos` — uploade une photo (coffre-fort
/// `document`, catégorie `photo`, cabinet-scopée sans patient) à référencer
/// ensuite via `photo_document_ids` sur `POST .../tickets`.
///
/// Champs multipart : `file` (binaire requis, JPEG/PNG ≤ 20 Mo, MIME déclaré
/// vérifié contre le nombre magique, #7302) ; `filename` optionnel.
/// Mêmes gardes antivirus/MIME que `documents::upload_document`/
/// `clinical::upload_patient_document`.
pub async fn upload_maintenance_photo(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Extension(object_storage): Extension<Arc<dyn ObjectStorage>>,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<UploadMaintenancePhotoResponse>), AppError> {
    let mut filename_field: Option<String> = None;
    let mut file_mime: Option<String> = None;
    let mut file_bytes: Option<Vec<u8>> = None;
    let mut file_filename: Option<String> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|_| AppError::ValidationError)?
    {
        let name = field.name().unwrap_or("").to_string();
        match name.as_str() {
            "filename" => {
                filename_field = Some(field.text().await.map_err(|_| AppError::ValidationError)?);
            }
            "file" => {
                file_mime = field
                    .content_type()
                    .map(|s| s.split(';').next().unwrap_or("").trim().to_string());
                file_filename = field.file_name().map(|s| s.to_string());
                let bytes = field.bytes().await.map_err(|_| AppError::ValidationError)?;
                if bytes.len() > MAX_PHOTO_SIZE {
                    return Err(AppError::ValidationError);
                }
                file_bytes = Some(bytes.to_vec());
            }
            _ => {}
        }
    }

    let file_bytes = file_bytes.ok_or(AppError::ValidationError)?;
    if file_bytes.is_empty() {
        return Err(AppError::ValidationError);
    }
    crate::file_scan::reject_eicar(&file_bytes)?;
    let file_mime = file_mime.ok_or(AppError::ValidationError)?;
    if !ALLOWED_PHOTO_MIMES.contains(&file_mime.as_str()) {
        return Err(AppError::ValidationError);
    }
    crate::file_scan::verify_content_matches_declared_mime(&file_bytes, &file_mime)?;

    let size_bytes = file_bytes.len() as i64;
    let fname = filename_field
        .or(file_filename)
        .unwrap_or_else(|| "photo.jpg".to_string());

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let storage_key = upload_storage::store_upload(
        object_storage.as_ref(),
        upload_storage::PREFIX_MAINTENANCE_PHOTO,
        &file_mime,
        file_bytes.clone(),
    )
    .await?;

    let row = sqlx::query(
        "INSERT INTO document \
         (cabinet_id, category, storage_key, filename, mime_type, size_bytes, sha256, \
          scan_status, uploaded_by) \
         VALUES ($1, 'photo', $2, $3, $4, $5, encode(digest($6, 'sha256'), 'hex'), 'pending', $7) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(&storage_key)
    .bind(&fname)
    .bind(&file_mime)
    .bind(size_bytes)
    .bind(&file_bytes)
    .bind(claims.sub)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let document_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'upload_maintenance_photo', 'document', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(document_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        document_id = %document_id,
        size_bytes,
        "maintenance photo uploaded"
    );

    Ok((
        StatusCode::CREATED,
        Json(UploadMaintenancePhotoResponse {
            document_id,
            filename: fname,
            size_bytes,
        }),
    ))
}

/// Une photo jointe à un ticket.
#[derive(Serialize)]
pub struct TicketPhotoDto {
    pub id: Uuid,
    pub document_id: Uuid,
    pub filename: String,
    pub created_at: String,
}

/// `GET /v1/cabinet/maintenance/tickets/:id/photos` — liste les photos jointes
/// à un ticket. Ticket absent/hors tenant → `404`.
pub async fn list_ticket_photos(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<Vec<TicketPhotoDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let ticket_exists =
        sqlx::query("SELECT 1 FROM maintenance_ticket WHERE id = $1 AND cabinet_id = $2")
            .bind(id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if ticket_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let rows = sqlx::query(
        "SELECT p.id, p.document_id, d.filename, p.created_at \
         FROM maintenance_ticket_photo p \
         JOIN document d ON d.id = p.document_id AND d.cabinet_id = p.cabinet_id \
         WHERE p.ticket_id = $1 AND p.cabinet_id = $2 \
         ORDER BY p.created_at",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(|row| -> Result<TicketPhotoDto, AppError> {
            let created_at: chrono::DateTime<chrono::Utc> =
                row.try_get("created_at").map_err(|_| AppError::Internal)?;
            Ok(TicketPhotoDto {
                id: row.try_get("id").map_err(|_| AppError::Internal)?,
                document_id: row.try_get("document_id").map_err(|_| AppError::Internal)?,
                filename: row.try_get("filename").map_err(|_| AppError::Internal)?,
                created_at: created_at.to_rfc3339(),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(data))
}

// ── Dashboard ────────────────────────────────────────────────────────────

/// Réponse de `GET /v1/cabinet/maintenance/stats`.
#[derive(Serialize)]
pub struct MaintenanceStatsResponse {
    /// Tickets non clôturés (`open`/`in_progress`).
    pub open_tickets: i64,
    /// Équipements dont le prochain contrôle (`next_check_at`) est à venir.
    pub planned_checks: i64,
    /// Équipements dont le prochain contrôle est dépassé.
    pub overdue_checks: i64,
}

/// `GET /v1/cabinet/maintenance/stats` — compteurs pour le dashboard cabinet
/// (#7167) : tickets ouverts, contrôles d'équipement planifiés, contrôles en
/// retard. Agrégation SQL directe, aucune nouvelle table (même doctrine que
/// `cabinet_stats.rs`).
pub async fn get_maintenance_stats(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<MaintenanceStatsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT \
           (SELECT COUNT(*) FROM maintenance_ticket \
            WHERE cabinet_id = $1 AND status IN ('open', 'in_progress')) AS open_tickets, \
           (SELECT COUNT(*) FROM cabinet_equipment \
            WHERE cabinet_id = $1 AND next_check_at IS NOT NULL \
              AND next_check_at >= CURRENT_DATE) AS planned_checks, \
           (SELECT COUNT(*) FROM cabinet_equipment \
            WHERE cabinet_id = $1 AND next_check_at IS NOT NULL \
              AND next_check_at < CURRENT_DATE) AS overdue_checks",
    )
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(MaintenanceStatsResponse {
        open_tickets: row
            .try_get("open_tickets")
            .map_err(|_| AppError::Internal)?,
        planned_checks: row
            .try_get("planned_checks")
            .map_err(|_| AppError::Internal)?,
        overdue_checks: row
            .try_get("overdue_checks")
            .map_err(|_| AppError::Internal)?,
    }))
}
