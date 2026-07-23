//! Handlers `/v1/waiting-list` — inscription et annulation d'un patient sur la
//! liste d'attente (US-P12), et `GET /v1/account/waiting-list` (#4357) —
//! lecture des propres inscriptions du patient (jusque-là aucun GET patient
//! n'existait, rendant l'`id` nécessaire au `cancel` irrécupérable dès que
//! la réponse initiale du `POST` était perdue).

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
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

    // Valide start_date/end_date : dates ISO parsables et fenêtre cohérente (end >= start).
    let start_date: Option<chrono::NaiveDate> = match body.start_date.as_deref() {
        Some(s) => Some(s.parse().map_err(|_| AppError::ValidationError)?),
        None => None,
    };
    let end_date: Option<chrono::NaiveDate> = match body.end_date.as_deref() {
        Some(s) => Some(s.parse().map_err(|_| AppError::ValidationError)?),
        None => None,
    };
    if let (Some(start), Some(end)) = (start_date, end_date) {
        if end < start {
            return Err(AppError::ValidationError);
        }
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

/// Une entrée de liste d'attente, vue patient.
#[derive(Serialize)]
pub struct WaitingListEntryItem {
    pub id: Uuid,
    pub cabinet_id: Uuid,
    pub provider_id: Uuid,
    pub desired_window: serde_json::Value,
    pub status: String,
    pub created_at: String,
}

/// Réponse de `GET /v1/account/waiting-list`.
#[derive(Serialize)]
pub struct ListWaitingListResponse {
    pub data: Vec<WaitingListEntryItem>,
}

/// `GET /v1/account/waiting-list` — les inscriptions du patient sur les
/// listes d'attente (#4357 : sans ce GET, un patient inscrit ne pouvait ni
/// voir son inscription ni récupérer l'`id` requis par
/// `POST /v1/waiting-list/:id/cancel` — cul-de-sac dès que le client perdait
/// l'id de la réponse `POST` initiale).
///
/// Token `kind:"patient"` requis. Ownership via policy RLS
/// `waiting_list_entry_patient_read` (migration 0146) — ne renvoie que les
/// entrées liées à un `patient` du compte, toutes cabinets confondus, tous
/// statuts (actif/annulé/honoré) pour un historique complet.
pub async fn list_waiting_list_entries(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<ListWaitingListResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, cabinet_id, provider_id, desired_window, status, created_at \
         FROM waiting_list_entry \
         ORDER BY created_at DESC",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in &rows {
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        data.push(WaitingListEntryItem {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            cabinet_id: row.try_get("cabinet_id").map_err(|_| AppError::Internal)?,
            provider_id: row.try_get("provider_id").map_err(|_| AppError::Internal)?,
            desired_window: row
                .try_get("desired_window")
                .map_err(|_| AppError::Internal)?,
            status: row.try_get("status").map_err(|_| AppError::Internal)?,
            created_at: created_at.to_rfc3339(),
        });
    }

    Ok(Json(ListWaitingListResponse { data }))
}

/// Réponse de `POST /v1/waiting-list/:id/cancel`.
#[derive(Serialize)]
pub struct CancelWaitingListResponse {
    pub id: Uuid,
    pub status: String,
}

/// `POST /v1/waiting-list/:id/cancel` — le patient retire son entrée de la
/// liste d'attente (seule sortie possible côté patient, hors `offer` cabinet).
///
/// Token `kind:"patient"` requis. Ownership via policy RLS
/// `waiting_list_entry_patient_read` (migration 0146, `app.patient_account_id`)
/// → 404 si l'entrée n'existe pas ou appartient à un autre patient.
/// Vérifie status == 'active' → sinon 409 `invalid_status`.
/// Passe l'entrée en `status = 'cancelled'`, ce qui libère l'anti-doublon
/// (index unique partiel `WHERE status = 'active'`, migration 0096) et permet
/// au patient de se réinscrire (#3737).
pub async fn cancel_waiting_list_entry(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(entry_id): Path<Uuid>,
) -> Result<Json<CancelWaitingListResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — waiting_list_entry_patient_read (policy 0146) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query("SELECT id, status, cabinet_id FROM waiting_list_entry WHERE id = $1")
        .bind(entry_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    if status != "active" {
        return Err(AppError::InvalidStatus);
    }
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;

    // Scope cabinet pour l'UPDATE (tenant_isolation, policy 0011).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query("UPDATE waiting_list_entry SET status = 'cancelled' WHERE id = $1")
        .bind(entry_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        waiting_list_entry_id = %entry_id,
        "waiting list entry cancelled"
    );

    Ok(Json(CancelWaitingListResponse {
        id: entry_id,
        status: "cancelled".to_string(),
    }))
}
