//! Handlers `GET /v1/implant-passport` et `GET /v1/implant-passport/export` — passeport implantaire patient.

use std::sync::Arc;

use axum::body::Body;
use axum::extract::{Extension, State};
use axum::http::{header, StatusCode};
use axum::response::Response;
use axum::Json;
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState, StorageSigner,
};

/// Un implant du passeport implantaire patient.
#[derive(Serialize)]
pub struct ImplantItem {
    pub id: Uuid,
    pub brand: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lot_number: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub placement_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tooth_position: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

/// Réponse de `GET /v1/implant-passport`.
#[derive(Serialize)]
pub struct ImplantPassportResponse {
    pub data: Vec<ImplantItem>,
}

/// `GET /v1/implant-passport` — liste les implants dentaires du patient authentifié.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` (migration 0077).
/// Lecture seule — données non chiffrées (pas de PII directe).
/// Aucun implant → `{ data: [] }`.
pub async fn list_implant_passport(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<ImplantPassportResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — RLS implant_passport_patient_read (migration 0077).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, brand, lot_number, placement_date, tooth_position, notes \
         FROM implant_passport \
         WHERE deleted_at IS NULL \
         ORDER BY placement_date DESC NULLS LAST, id DESC",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data: Vec<ImplantItem> = Vec::with_capacity(rows.len());
    for row in rows {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let brand: String = row.try_get("brand").map_err(|_| AppError::Internal)?;
        let lot_number: Option<String> =
            row.try_get("lot_number").map_err(|_| AppError::Internal)?;
        let placement_date: Option<chrono::NaiveDate> = row
            .try_get("placement_date")
            .map_err(|_| AppError::Internal)?;
        let tooth_position: Option<String> = row
            .try_get("tooth_position")
            .map_err(|_| AppError::Internal)?;
        let notes: Option<String> = row.try_get("notes").map_err(|_| AppError::Internal)?;

        data.push(ImplantItem {
            id,
            brand,
            lot_number,
            placement_date: placement_date.map(|d| d.to_string()),
            tooth_position,
            notes,
        });
    }

    tracing::info!(
        account_id = %claims.account_id,
        count = data.len(),
        "implant passport listed"
    );

    Ok(Json(ImplantPassportResponse { data }))
}

/// `GET /v1/implant-passport/export` — export PDF du passeport implantaire (version 🎭 mockée).
///
/// Token `kind:"patient"` requis. Retourne `302 Found` avec `Location` vers l'URL signée.
/// Échec du signer → `410 link_expired`. Aucun implant présent → ne bloque pas l'export.
pub async fn export_implant_passport(
    State(_state): State<AppState>,
    claims: PatientAccountClaims,
    Extension(signer): Extension<Arc<dyn StorageSigner>>,
) -> Result<Response, AppError> {
    // Version mockée : clé de stockage dérivée du compte patient.
    let storage_key = format!("implant-passport/{}.pdf", claims.account_id);

    let signed_url = signer.sign(&storage_key).ok_or(AppError::LinkExpired)?;

    tracing::info!(
        account_id = %claims.account_id,
        "implant passport export redirected"
    );

    Response::builder()
        .status(StatusCode::FOUND)
        .header(header::LOCATION, &signed_url)
        .header(header::CACHE_CONTROL, "no-store")
        .body(Body::empty())
        .map_err(|_| AppError::Internal)
}
