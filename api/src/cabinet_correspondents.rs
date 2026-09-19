//! Annuaire des correspondants du cabinet (#7194, DP-F8.b) : `GET`/`POST
//! /v1/cabinet/correspondents`, `PATCH`/`DELETE /v1/cabinet/correspondents/:id`
//! et `GET /v1/cabinet/correspondents/:id/stats`.
//!
//! S'appuie sur `cabinet_correspondent` (migration 0280, #7195) : annuaire
//! propre au cabinet (nom, spécialité, coordonnées, RPPS), distinct de
//! `patient_correspondent`/`patient_referring_doctor` (texte libre, scopés
//! compte patient). `patient.referred_by_correspondent_id` pointe vers une
//! ligne de cet annuaire pour mesurer les adressages et le CA apporté.
//!
//! Le moteur de courriers (`letters.rs`, #7197) accepte désormais un
//! `correspondent_id` de cet annuaire et lie le document produit
//! (`document.correspondent_id`, migration 0281) — compté dans les stats
//! comme « courrier envoyé ».

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{is_valid_email_format, AppError, ProSecretaryPlusClaims},
    text_validation, AppState,
};

const MAX_DISPLAY_NAME_LEN: usize = 200;
const MAX_SHORT_FIELD_LEN: usize = 200;
const MAX_ADDRESS_LEN: usize = 500;
const MAX_NOTES_LEN: usize = 2000;

/// `422 validation_error` si `s` (une fois trim) dépasse `max_chars` ou
/// contient un octet NUL, sinon `Ok(())`.
fn validate_optional_field(s: &str, max_chars: usize) -> Result<(), AppError> {
    text_validation::reject_nul_byte(s)?;
    text_validation::validate_max_len(s, max_chars)
}

/// Trim `s`, renvoie `None` si le résultat est vide (un champ optionnel vide
/// ou blanc est stocké `NULL`, pas une chaîne vide).
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

/// Un correspondant du cabinet.
#[derive(Serialize)]
pub struct CorrespondentDto {
    pub id: Uuid,
    pub display_name: String,
    pub specialty: Option<String>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub address: Option<String>,
    pub rpps: Option<String>,
    pub notes: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

fn correspondent_dto_from_row(row: &sqlx::postgres::PgRow) -> Result<CorrespondentDto, AppError> {
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    let updated_at: chrono::DateTime<chrono::Utc> =
        row.try_get("updated_at").map_err(|_| AppError::Internal)?;
    Ok(CorrespondentDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        display_name: row
            .try_get("display_name")
            .map_err(|_| AppError::Internal)?,
        specialty: row.try_get("specialty").map_err(|_| AppError::Internal)?,
        email: row.try_get("email").map_err(|_| AppError::Internal)?,
        phone: row.try_get("phone").map_err(|_| AppError::Internal)?,
        address: row.try_get("address").map_err(|_| AppError::Internal)?,
        rpps: row.try_get("rpps").map_err(|_| AppError::Internal)?,
        notes: row.try_get("notes").map_err(|_| AppError::Internal)?,
        created_at: created_at.to_rfc3339(),
        updated_at: updated_at.to_rfc3339(),
    })
}

// ── GET /v1/cabinet/correspondents ───────────────────────────────────────────

/// `GET /v1/cabinet/correspondents` — liste l'annuaire du cabinet, trié par nom.
///
/// Token pro `secretary`/`practitioner`/`admin` requis (même garde que
/// `letters::list_letter_templates`). RLS scopée via `app.current_cabinet_id`.
pub async fn list_correspondents(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<Vec<CorrespondentDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, display_name, specialty, email, phone, address, rpps, notes, \
                created_at, updated_at \
         FROM cabinet_correspondent \
         ORDER BY display_name",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let correspondents = rows
        .iter()
        .map(correspondent_dto_from_row)
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(correspondents))
}

// ── POST /v1/cabinet/correspondents ──────────────────────────────────────────

/// Corps de `POST /v1/cabinet/correspondents`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateCorrespondentBody {
    pub display_name: String,
    pub specialty: Option<String>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub address: Option<String>,
    pub rpps: Option<String>,
    pub notes: Option<String>,
}

/// `POST /v1/cabinet/correspondents` — crée un correspondant dans l'annuaire
/// du cabinet.
///
/// `display_name` non blanc et borné → `422` sinon. Champs optionnels blancs
/// stockés `NULL`, chacun borné (`422` si dépassé) ; `email`, s'il est fourni,
/// doit être syntaxiquement valide (`422 validation_error` sinon, même garde
/// que `PATCH /v1/account`).
pub async fn create_correspondent(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateCorrespondentBody>,
) -> Result<(StatusCode, Json<CorrespondentDto>), AppError> {
    let display_name = body.display_name.trim().to_string();
    if display_name.is_empty() {
        return Err(AppError::ValidationError);
    }
    validate_optional_field(&display_name, MAX_DISPLAY_NAME_LEN)?;

    let specialty = normalize_optional(body.specialty);
    let email = normalize_optional(body.email);
    let phone = normalize_optional(body.phone);
    let address = normalize_optional(body.address);
    let rpps = normalize_optional(body.rpps);
    let notes = normalize_optional(body.notes);

    for field in [&specialty, &phone, &rpps].into_iter().flatten() {
        validate_optional_field(field, MAX_SHORT_FIELD_LEN)?;
    }
    if let Some(email) = &email {
        validate_optional_field(email, MAX_SHORT_FIELD_LEN)?;
        if !is_valid_email_format(email) {
            return Err(AppError::ValidationError);
        }
    }
    if let Some(address) = &address {
        validate_optional_field(address, MAX_ADDRESS_LEN)?;
    }
    if let Some(notes) = &notes {
        validate_optional_field(notes, MAX_NOTES_LEN)?;
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO cabinet_correspondent \
         (cabinet_id, display_name, specialty, email, phone, address, rpps, notes) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) \
         RETURNING id, display_name, specialty, email, phone, address, rpps, notes, \
                   created_at, updated_at",
    )
    .bind(claims.cabinet_id)
    .bind(&display_name)
    .bind(&specialty)
    .bind(&email)
    .bind(&phone)
    .bind(&address)
    .bind(&rpps)
    .bind(&notes)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let dto = correspondent_dto_from_row(&row)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'create_cabinet_correspondent', 'cabinet_correspondent', $4)",
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
        correspondent_id = %dto.id,
        "cabinet correspondent created"
    );

    Ok((StatusCode::CREATED, Json(dto)))
}

// ── PATCH /v1/cabinet/correspondents/:id ─────────────────────────────────────

/// Corps de `PATCH /v1/cabinet/correspondents/:id`. Champ absent = inchangé ;
/// champ fourni blanc l'efface (stocké `NULL`).
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchCorrespondentBody {
    pub display_name: Option<String>,
    pub specialty: Option<String>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub address: Option<String>,
    pub rpps: Option<String>,
    pub notes: Option<String>,
}

/// `PATCH /v1/cabinet/correspondents/:id` — met à jour un correspondant du
/// cabinet.
///
/// Correspondant absent ou hors tenant → `404`. `display_name`, s'il est
/// fourni, ne peut pas être vide. Mêmes bornes/validations que `POST`.
pub async fn patch_correspondent(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchCorrespondentBody>,
) -> Result<Json<CorrespondentDto>, AppError> {
    if let Some(display_name) = &body.display_name {
        if display_name.trim().is_empty() {
            return Err(AppError::ValidationError);
        }
        validate_optional_field(display_name.trim(), MAX_DISPLAY_NAME_LEN)?;
    }
    // `Option<Option<String>>` : `None` = champ absent (inchangé), `Some(None)`
    // = champ fourni blanc (efface), `Some(Some(v))` = nouvelle valeur.
    let specialty = body.specialty.map(|s| normalize_optional(Some(s)));
    let email = body.email.map(|s| normalize_optional(Some(s)));
    let phone = body.phone.map(|s| normalize_optional(Some(s)));
    let address = body.address.map(|s| normalize_optional(Some(s)));
    let rpps = body.rpps.map(|s| normalize_optional(Some(s)));
    let notes = body.notes.map(|s| normalize_optional(Some(s)));

    for field in [&specialty, &phone, &rpps].into_iter().flatten().flatten() {
        validate_optional_field(field, MAX_SHORT_FIELD_LEN)?;
    }
    if let Some(Some(email)) = &email {
        validate_optional_field(email, MAX_SHORT_FIELD_LEN)?;
        if !is_valid_email_format(email) {
            return Err(AppError::ValidationError);
        }
    }
    if let Some(Some(address)) = &address {
        validate_optional_field(address, MAX_ADDRESS_LEN)?;
    }
    if let Some(Some(notes)) = &notes {
        validate_optional_field(notes, MAX_NOTES_LEN)?;
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let current = sqlx::query(
        "SELECT display_name, specialty, email, phone, address, rpps, notes \
         FROM cabinet_correspondent WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let new_display_name = body.display_name.map(|s| s.trim().to_string()).unwrap_or(
        current
            .try_get("display_name")
            .map_err(|_| AppError::Internal)?,
    );
    let new_specialty = specialty.unwrap_or(
        current
            .try_get("specialty")
            .map_err(|_| AppError::Internal)?,
    );
    let new_email = email.unwrap_or(current.try_get("email").map_err(|_| AppError::Internal)?);
    let new_phone = phone.unwrap_or(current.try_get("phone").map_err(|_| AppError::Internal)?);
    let new_address =
        address.unwrap_or(current.try_get("address").map_err(|_| AppError::Internal)?);
    let new_rpps = rpps.unwrap_or(current.try_get("rpps").map_err(|_| AppError::Internal)?);
    let new_notes = notes.unwrap_or(current.try_get("notes").map_err(|_| AppError::Internal)?);

    let row = sqlx::query(
        "UPDATE cabinet_correspondent \
         SET display_name = $1, specialty = $2, email = $3, phone = $4, \
             address = $5, rpps = $6, notes = $7, updated_at = now() \
         WHERE id = $8 AND cabinet_id = $9 \
         RETURNING id, display_name, specialty, email, phone, address, rpps, notes, \
                   created_at, updated_at",
    )
    .bind(&new_display_name)
    .bind(&new_specialty)
    .bind(&new_email)
    .bind(&new_phone)
    .bind(&new_address)
    .bind(&new_rpps)
    .bind(&new_notes)
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let dto = correspondent_dto_from_row(&row)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'update_cabinet_correspondent', 'cabinet_correspondent', $4)",
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
        correspondent_id = %id,
        "cabinet correspondent updated"
    );

    Ok(Json(dto))
}

// ── DELETE /v1/cabinet/correspondents/:id ────────────────────────────────────

/// `DELETE /v1/cabinet/correspondents/:id` — retire un correspondant de
/// l'annuaire du cabinet.
///
/// Correspondant absent ou hors tenant → `404`. Référencé par un patient
/// adressé (`patient.referred_by_correspondent_id`) ou un courrier
/// (`document.correspondent_id`) → `409 correspondent_in_use` (FK composite,
/// migrations 0280/0281) plutôt qu'un `500` sur la violation `23503`.
pub async fn delete_correspondent(
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

    let deleted = sqlx::query(
        "DELETE FROM cabinet_correspondent WHERE id = $1 AND cabinet_id = $2 RETURNING id",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|e| {
        if is_foreign_key_violation(&e) {
            AppError::CorrespondentInUse
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
         VALUES ($1, $2, $3, 'delete_cabinet_correspondent', 'cabinet_correspondent', $4)",
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
        correspondent_id = %id,
        "cabinet correspondent deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}

// ── GET /v1/cabinet/correspondents/:id/stats ─────────────────────────────────

/// Réponse de `GET /v1/cabinet/correspondents/:id/stats`.
#[derive(Serialize)]
pub struct CorrespondentStatsResponse {
    /// Patients dont `referred_by_correspondent_id` pointe vers ce correspondant.
    pub referred_patients_count: i64,
    /// CA facturé ("facture" = devis `signed`, même terminologie que
    /// `invoice_reminder.rs`) sur ces patients — montant brut des devis
    /// signés, non filtré par le statut de paiement (distinct du CA
    /// encaissé, `cabinet_stats::get_cabinet_billing_stats`).
    pub billed_revenue_cents: i64,
    /// Courriers générés (`letters::generate_patient_letter`) avec ce
    /// correspondant comme destinataire (`document.correspondent_id`).
    pub letters_sent_count: i64,
}

/// `GET /v1/cabinet/correspondents/:id/stats` — adressages, CA apporté,
/// courriers envoyés pour un correspondant du cabinet.
///
/// Correspondant absent ou hors tenant (RLS `tenant_isolation`) → `404`.
pub async fn get_correspondent_stats(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<CorrespondentStatsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT 1 FROM cabinet_correspondent WHERE id = $1")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let referred_row = sqlx::query(
        "SELECT COUNT(*)::bigint AS referred_patients_count \
         FROM patient \
         WHERE cabinet_id = $1 AND referred_by_correspondent_id = $2 AND deleted_at IS NULL",
    )
    .bind(claims.cabinet_id)
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let referred_patients_count: i64 = referred_row
        .try_get("referred_patients_count")
        .map_err(|_| AppError::Internal)?;

    let revenue_row = sqlx::query(
        "SELECT (COALESCE(SUM(q.total_amount), 0) * 100)::bigint AS billed_revenue_cents \
         FROM quote q \
         JOIN patient p ON p.id = q.patient_id \
         WHERE q.cabinet_id = $1 AND q.status = 'signed' AND q.deleted_at IS NULL \
           AND p.referred_by_correspondent_id = $2 AND p.deleted_at IS NULL",
    )
    .bind(claims.cabinet_id)
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let billed_revenue_cents: i64 = revenue_row
        .try_get("billed_revenue_cents")
        .map_err(|_| AppError::Internal)?;

    let letters_row = sqlx::query(
        "SELECT COUNT(*)::bigint AS letters_sent_count \
         FROM document \
         WHERE cabinet_id = $1 AND correspondent_id = $2 AND deleted_at IS NULL",
    )
    .bind(claims.cabinet_id)
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let letters_sent_count: i64 = letters_row
        .try_get("letters_sent_count")
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(CorrespondentStatsResponse {
        referred_patients_count,
        billed_revenue_cents,
        letters_sent_count,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_optional_trims_and_blanks_out_empty() {
        assert_eq!(normalize_optional(Some("  ".to_string())), None);
        assert_eq!(normalize_optional(Some("".to_string())), None);
        assert_eq!(
            normalize_optional(Some("  Dr Martin  ".to_string())),
            Some("Dr Martin".to_string())
        );
        assert_eq!(normalize_optional(None), None);
    }
}
