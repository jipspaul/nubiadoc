//! Handler `POST /v1/waiting-list` — inscription d'un patient sur la liste d'attente (US-P12).

use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

/// Corps de `POST /v1/waiting-list`.
#[derive(Deserialize)]
pub struct CreateWaitingListBody {
    /// Identifiant du provider (praticien) souhaité.
    pub provider_id: Uuid,
    /// Motif de consultation (optionnel).
    pub motif: Option<String>,
    /// Date de début souhaitée ISO 8601 (optionnel).
    pub start_date: Option<String>,
    /// Date de fin souhaitée ISO 8601 (optionnel).
    pub end_date: Option<String>,
}

/// Réponse de `POST /v1/waiting-list`.
#[derive(Serialize)]
pub struct CreateWaitingListResponse {
    pub id: Uuid,
    pub status: String,
}

/// `POST /v1/waiting-list` — inscrit le patient sur la liste d'attente pour un praticien.
///
/// Token `kind:"patient"` requis → 401/403 sinon.
/// `provider_id` dans le body → 404 si inconnu.
/// `cabinet_id` déduit du provider (jamais du body).
/// Doublon actif (même patient, même provider, status='active') → 409 already_on_waiting_list.
/// Répond `201 { id, status: "active" }`.
pub async fn create_waiting_list_entry(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<CreateWaitingListBody>,
) -> Result<(StatusCode, Json<CreateWaitingListResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Résout le cabinet via le provider (policy provider_public_read : is_listed = true).
    let provider_row =
        sqlx::query("SELECT cabinet_id, practitioner_id FROM provider WHERE id = $1")
            .bind(body.provider_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = provider_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id_opt: Option<Uuid> = provider_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    // Un provider sans praticien lié n'est pas valide pour la liste d'attente.
    let _practitioner_id = practitioner_id_opt.ok_or(AppError::NotFound)?;

    // Scope cabinet pour les requêtes soumises à la RLS tenant_isolation.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Résout le dossier patient dans ce cabinet.
    let patient_row = sqlx::query(
        "SELECT id FROM patient \
         WHERE patient_account_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(claims.account_id)
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let patient_id: Uuid = patient_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Anti-doublon : vérifie si une entrée active existe déjà pour ce patient + provider.
    let existing = sqlx::query(
        "SELECT id FROM waiting_list_entry \
         WHERE patient_id = $1 AND provider_id = $2 AND status = 'active'",
    )
    .bind(patient_id)
    .bind(body.provider_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if existing.is_some() {
        return Err(AppError::AlreadyOnWaitingList);
    }

    // Construit desired_window depuis les champs optionnels.
    let desired_window = json!({
        "motif": body.motif,
        "start_date": body.start_date,
        "end_date": body.end_date,
    });

    let row = sqlx::query(
        "INSERT INTO waiting_list_entry \
         (cabinet_id, patient_id, provider_id, desired_window) \
         VALUES ($1, $2, $3, $4) \
         RETURNING id, status",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(body.provider_id)
    .bind(&desired_window)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        waiting_list_entry_id = %id,
        cabinet_id = %cabinet_id,
        "waiting list entry created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateWaitingListResponse { id, status }),
    ))
}
