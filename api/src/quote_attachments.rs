//! Pièces jointes d'un devis (#7203/DP-F5.b) :
//! `POST/GET /v1/cabinet/quotes/:id/attachments` (cabinet) +
//! `DELETE /v1/cabinet/quotes/:id/attachments/:attachment_id` +
//! `GET /v1/quotes/:id/attachments` (patient, lecture seule).
//!
//! Table `quote_attachment` (migration 0278/#7204) : rattache un devis soit à
//! un document déjà stocké dans le coffre-fort (`document_id` — consentement
//! scanné, ordonnance…), soit à un modèle de courrier pas encore matérialisé
//! (`template_ref`, id `letter_template`) — jamais les deux à la fois, ni
//! aucun des deux (contrainte `quote_attachment_source_xor`, vérifiée ici
//! avant l'INSERT pour renvoyer `422` plutôt qu'une violation de contrainte
//! en `500`).
//!
//! Téléchargement du document lui-même : réutilise
//! `GET /v1/documents/:id/download` (déjà RLS-scopé patient via
//! `document_patient_read`, migration 0034) — pas de route dédiée ici.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{auth::AppError, permissions::ProBillingClaims, text_validation, AppState};

const VALID_KINDS: &[&str] = &["consent", "prescription", "letter", "other"];

fn validate_kind(kind: &str) -> Result<(), AppError> {
    if VALID_KINDS.contains(&kind) {
        Ok(())
    } else {
        Err(AppError::ValidationError)
    }
}

/// Body de `POST /v1/cabinet/quotes/:id/attachments`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateQuoteAttachmentBody {
    pub kind: String,
    pub document_id: Option<Uuid>,
    pub template_ref: Option<String>,
}

/// Une pièce jointe de devis (forme partagée cabinet/patient).
#[derive(Serialize)]
pub struct QuoteAttachmentDto {
    pub id: Uuid,
    pub kind: String,
    pub document_id: Option<Uuid>,
    pub template_ref: Option<String>,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct ListQuoteAttachmentsResponse {
    pub data: Vec<QuoteAttachmentDto>,
}

fn attachment_dto_from_row(row: &sqlx::postgres::PgRow) -> Result<QuoteAttachmentDto, AppError> {
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    Ok(QuoteAttachmentDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        kind: row.try_get("kind").map_err(|_| AppError::Internal)?,
        document_id: row.try_get("document_id").map_err(|_| AppError::Internal)?,
        template_ref: row
            .try_get("template_ref")
            .map_err(|_| AppError::Internal)?,
        created_at: created_at.to_rfc3339(),
    })
}

/// Vérifie que le devis `id` existe pour ce cabinet (non supprimé) et
/// renvoie son `patient_id` et son `status` — factorisé entre les 3 handlers
/// cabinet ci-dessous.
async fn load_cabinet_quote(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    id: Uuid,
    cabinet_id: Uuid,
) -> Result<(Uuid, String), AppError> {
    let row = sqlx::query(
        "SELECT patient_id, status FROM quote \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(id)
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    Ok((
        row.try_get("patient_id").map_err(|_| AppError::Internal)?,
        row.try_get("status").map_err(|_| AppError::Internal)?,
    ))
}

/// `POST /v1/cabinet/quotes/:id/attachments` — attache une pièce à un devis.
///
/// `ProBillingClaims` (même garde que `send_cabinet_quote`). Devis inexistant
/// ou hors tenant → `404`. Devis déjà `signed` → `409 quote_locked` (immuable,
/// même doctrine que `PATCH /v1/cabinet/quotes/:id`).
/// `kind` ∈ `consent, prescription, letter, other` → `422` sinon.
/// Exactement un de `document_id`/`template_ref` requis → `422` sinon
/// (contrainte `quote_attachment_source_xor`).
/// `document_id` doit référencer un document existant de ce cabinet
/// rattaché au patient du devis → `422` sinon.
/// `template_ref` doit référencer un `letter_template` visible du cabinet
/// (global ou propre) → `422` sinon.
pub async fn create_quote_attachment(
    State(state): State<AppState>,
    claims: ProBillingClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<CreateQuoteAttachmentBody>,
) -> Result<(StatusCode, Json<QuoteAttachmentDto>), AppError> {
    validate_kind(&body.kind)?;
    if let Some(template_ref) = &body.template_ref {
        text_validation::reject_nul_byte(template_ref)?;
        text_validation::validate_max_len(template_ref, 200)?;
    }
    if body.document_id.is_some() == body.template_ref.is_some() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let (patient_id, status) = load_cabinet_quote(&mut tx, id, claims.cabinet_id).await?;
    if status == "signed" {
        return Err(AppError::QuoteLocked);
    }

    if let Some(document_id) = body.document_id {
        let doc = sqlx::query(
            "SELECT patient_id FROM document \
             WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
        )
        .bind(document_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        let doc_patient_id: Option<Uuid> = doc
            .ok_or(AppError::ValidationError)?
            .try_get("patient_id")
            .map_err(|_| AppError::Internal)?;
        if doc_patient_id != Some(patient_id) {
            return Err(AppError::ValidationError);
        }
    }

    if let Some(template_ref) = &body.template_ref {
        let template_id = Uuid::parse_str(template_ref).map_err(|_| AppError::ValidationError)?;
        let exists = sqlx::query(
            "SELECT 1 FROM letter_template \
             WHERE id = $1 AND (cabinet_id IS NULL OR cabinet_id = $2)",
        )
        .bind(template_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::ValidationError);
        }
    }

    let row = sqlx::query(
        "INSERT INTO quote_attachment (cabinet_id, quote_id, kind, document_id, template_ref) \
         VALUES ($1, $2, $3, $4, $5) \
         RETURNING id, kind, document_id, template_ref, created_at",
    )
    .bind(claims.cabinet_id)
    .bind(id)
    .bind(&body.kind)
    .bind(body.document_id)
    .bind(&body.template_ref)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let dto = attachment_dto_from_row(&row)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        quote_id = %id,
        attachment_id = %dto.id,
        kind = %dto.kind,
        "quote attachment created"
    );

    Ok((StatusCode::CREATED, Json(dto)))
}

/// `GET /v1/cabinet/quotes/:id/attachments` — liste les pièces jointes d'un devis (vue cabinet).
pub async fn list_cabinet_quote_attachments(
    State(state): State<AppState>,
    claims: ProBillingClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<ListQuoteAttachmentsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    load_cabinet_quote(&mut tx, id, claims.cabinet_id).await?;

    let rows = sqlx::query(
        "SELECT id, kind, document_id, template_ref, created_at FROM quote_attachment \
         WHERE quote_id = $1 AND cabinet_id = $2 ORDER BY created_at",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in &rows {
        data.push(attachment_dto_from_row(row)?);
    }

    Ok(Json(ListQuoteAttachmentsResponse { data }))
}

/// `DELETE /v1/cabinet/quotes/:id/attachments/:attachment_id` — retire une pièce jointe.
///
/// Devis inexistant/hors tenant ou pièce jointe hors devis → `404`. Devis
/// `signed` → `409 quote_locked`, même doctrine que la création.
pub async fn delete_quote_attachment(
    State(state): State<AppState>,
    claims: ProBillingClaims,
    Path((id, attachment_id)): Path<(Uuid, Uuid)>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let (_, status) = load_cabinet_quote(&mut tx, id, claims.cabinet_id).await?;
    if status == "signed" {
        return Err(AppError::QuoteLocked);
    }

    let deleted = sqlx::query(
        "DELETE FROM quote_attachment WHERE id = $1 AND quote_id = $2 AND cabinet_id = $3",
    )
    .bind(attachment_id)
    .bind(id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if deleted.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        quote_id = %id,
        attachment_id = %attachment_id,
        "quote attachment deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}

/// `GET /v1/quotes/:id/attachments` — liste les pièces jointes d'un devis (vue patient).
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id`
/// (policy `quote_attachment_patient_read`, migration 0278) : un devis
/// `draft` ou hors patient est invisible (liste vide plutôt qu'erreur, même
/// choix que le reste des sous-ressources patient de `quote`).
pub async fn list_patient_quote_attachments(
    State(state): State<AppState>,
    claims: crate::auth::PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<ListQuoteAttachmentsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, kind, document_id, template_ref, created_at FROM quote_attachment \
         WHERE quote_id = $1 ORDER BY created_at",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in &rows {
        data.push(attachment_dto_from_row(row)?);
    }

    Ok(Json(ListQuoteAttachmentsResponse { data }))
}
