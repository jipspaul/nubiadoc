//! Attestation d'information d'un devis (#7203/DP-F5.b) :
//! `GET/POST /v1/cabinet/quotes/:id/attestation` (cabinet, dépôt du texte) +
//! `GET /v1/quotes/:id/attestation` + `POST /v1/quotes/:id/attestation/sign`
//! (patient) — même mécanique de signature stub que `billing::sign_quote`
//! (pas de provider eIDAS réel, `signed_at` posé directement).
//!
//! Table `quote_information_attestation` (migration 0278/#7204) : une ligne
//! par remise d'attestation (historique append-only, pas d'`UPDATE` du texte
//! une fois créée — si le cabinet doit corriger le texte avant signature, il
//! recrée une attestation, refusé tant que la précédente n'est ni signée ni
//! retirée, cf. `create_quote_attestation` ci-dessous). "La" attestation
//! d'un devis = la plus récente (`ORDER BY created_at DESC LIMIT 1`).
//!
//! Règle métier (issue #7203) : tant qu'une attestation existe et n'est pas
//! signée, `POST /v1/quotes/:id/sign` (signature du devis) refuse avec
//! `409 attestation_not_signed` — implémenté dans `billing::sign_quote`.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    permissions::ProBillingClaims,
    text_validation, AppState,
};

const MAX_ATTESTATION_BODY_LEN: usize = 20_000;

/// Body de `POST /v1/cabinet/quotes/:id/attestation`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateQuoteAttestationBody {
    pub body: String,
}

/// Une attestation d'information (forme partagée cabinet/patient).
#[derive(Serialize)]
pub struct QuoteAttestationDto {
    pub id: Uuid,
    pub body: String,
    pub signed_at: Option<String>,
    pub created_at: String,
}

fn attestation_dto_from_row(row: &sqlx::postgres::PgRow) -> Result<QuoteAttestationDto, AppError> {
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    let signed_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("signed_at").map_err(|_| AppError::Internal)?;
    Ok(QuoteAttestationDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        body: row.try_get("body").map_err(|_| AppError::Internal)?,
        signed_at: signed_at.map(|d| d.to_rfc3339()),
        created_at: created_at.to_rfc3339(),
    })
}

/// `POST /v1/cabinet/quotes/:id/attestation` — dépose le texte d'attestation
/// d'information à faire signer au patient avant la signature du devis.
///
/// `ProBillingClaims`. Devis inexistant/hors tenant → `404`. Devis `signed`
/// → `409 quote_locked`. Une attestation non signée existe déjà pour ce
/// devis → `409 attestation_already_pending` (le cabinet doit attendre la
/// signature ou que le patient réponde avant d'en déposer une nouvelle).
/// `body` vide/blanc ou > 20 000 caractères → `422`.
pub async fn create_quote_attestation(
    State(state): State<AppState>,
    claims: ProBillingClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<CreateQuoteAttestationBody>,
) -> Result<(StatusCode, Json<QuoteAttestationDto>), AppError> {
    if body.body.trim().is_empty() {
        return Err(AppError::ValidationError);
    }
    text_validation::reject_nul_byte(&body.body)?;
    text_validation::validate_max_len(&body.body, MAX_ATTESTATION_BODY_LEN)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let quote_row = sqlx::query(
        "SELECT patient_id, status FROM quote \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let patient_id: Uuid = quote_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = quote_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    if status == "signed" {
        return Err(AppError::QuoteLocked);
    }

    let latest = sqlx::query(
        "SELECT signed_at FROM quote_information_attestation \
         WHERE quote_id = $1 AND cabinet_id = $2 \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if let Some(row) = latest {
        let signed_at: Option<chrono::DateTime<chrono::Utc>> =
            row.try_get("signed_at").map_err(|_| AppError::Internal)?;
        if signed_at.is_none() {
            return Err(AppError::AttestationAlreadyPending);
        }
    }

    let row = sqlx::query(
        "INSERT INTO quote_information_attestation (cabinet_id, quote_id, patient_id, body) \
         VALUES ($1, $2, $3, $4) \
         RETURNING id, body, signed_at, created_at",
    )
    .bind(claims.cabinet_id)
    .bind(id)
    .bind(patient_id)
    .bind(&body.body)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let dto = attestation_dto_from_row(&row)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        quote_id = %id,
        attestation_id = %dto.id,
        "quote information attestation created"
    );

    Ok((StatusCode::CREATED, Json(dto)))
}

/// `GET /v1/cabinet/quotes/:id/attestation` — attestation courante d'un devis (vue cabinet).
///
/// Devis inexistant/hors tenant → `404`. Aucune attestation déposée → `404`.
pub async fn get_cabinet_quote_attestation(
    State(state): State<AppState>,
    claims: ProBillingClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<QuoteAttestationDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let quote_exists =
        sqlx::query("SELECT 1 FROM quote WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL")
            .bind(id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if quote_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let row = sqlx::query(
        "SELECT id, body, signed_at, created_at FROM quote_information_attestation \
         WHERE quote_id = $1 AND cabinet_id = $2 \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(attestation_dto_from_row(&row)?))
}

/// `GET /v1/quotes/:id/attestation` — attestation courante d'un devis (vue patient).
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id`
/// (policy `quote_information_attestation_patient_read`, migration 0278).
/// Devis hors patient/`draft`, ou aucune attestation déposée → `404`.
pub async fn get_patient_quote_attestation(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<QuoteAttestationDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, body, signed_at, created_at FROM quote_information_attestation \
         WHERE quote_id = $1 \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(attestation_dto_from_row(&row)?))
}

/// Réponse de `POST /v1/quotes/:id/attestation/sign`.
#[derive(Serialize)]
pub struct SignQuoteAttestationResponse {
    pub signed: bool,
    pub signed_at: String,
}

/// `POST /v1/quotes/:id/attestation/sign` — signe l'attestation d'information
/// courante d'un devis (stub, même mécanique que `billing::sign_quote` :
/// pas d'appel provider eIDAS, `signed_at` posé directement).
///
/// Token `kind:"patient"` requis. RLS lecture via `app.patient_account_id`
/// (policy `quote_information_attestation_patient_read`) ; l'écriture, elle,
/// passe par `app.current_cabinet_id` (policy `tenant_isolation`) — même
/// bascule de scope que `sign_quote` (une session patient ne porte pas de
/// `cabinet_id`, le `cabinet_id` de la ressource est relu puis reposé comme
/// GUC pour l'`UPDATE`).
/// Devis hors patient/`draft`, ou aucune attestation déposée → `404`.
/// Attestation déjà signée → `200` idempotent avec le `signed_at` existant.
pub async fn sign_quote_attestation(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<SignQuoteAttestationResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, cabinet_id, signed_at FROM quote_information_attestation \
         WHERE quote_id = $1 \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let attestation_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let existing_signed_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("signed_at").map_err(|_| AppError::Internal)?;
    if let Some(signed_at) = existing_signed_at {
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(SignQuoteAttestationResponse {
            signed: true,
            signed_at: signed_at.to_rfc3339(),
        }));
    }

    // Bascule de scope pour l'écriture (policy `tenant_isolation`) — voir doc
    // de fonction. Verrou `FOR UPDATE` + relecture pour le même garde-fou
    // double-submit que `billing::sign_quote` (#7015).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let locked = sqlx::query(
        "SELECT signed_at FROM quote_information_attestation \
         WHERE id = $1 AND cabinet_id = $2 \
         FOR UPDATE",
    )
    .bind(attestation_id)
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let locked_signed_at: Option<chrono::DateTime<chrono::Utc>> = locked
        .try_get("signed_at")
        .map_err(|_| AppError::Internal)?;
    if let Some(signed_at) = locked_signed_at {
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(SignQuoteAttestationResponse {
            signed: true,
            signed_at: signed_at.to_rfc3339(),
        }));
    }

    let updated = sqlx::query(
        "UPDATE quote_information_attestation \
         SET signed_at = now(), signature_ref = 'stub' \
         WHERE id = $1 AND cabinet_id = $2 AND signed_at IS NULL \
         RETURNING signed_at",
    )
    .bind(attestation_id)
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::Internal)?;

    let signed_at: chrono::DateTime<chrono::Utc> = updated
        .try_get("signed_at")
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        quote_id = %id,
        attestation_id = %attestation_id,
        "quote information attestation signed"
    );

    Ok(Json(SignQuoteAttestationResponse {
        signed: true,
        signed_at: signed_at.to_rfc3339(),
    }))
}
