//! Handlers `GET /v1/implant-passport`, `GET /v1/implant-passport/export`
//! (lecture patient) et `POST /v1/cabinet/patients/:id/implants` (écriture
//! praticien, #4140) — passeport implantaire.

use std::sync::Arc;

use axum::body::Body;
use axum::extract::{Extension, Path, State};
use axum::http::{header, StatusCode};
use axum::response::Response;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, ProPractitionerClaims},
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

// ── POST /v1/cabinet/patients/:id/implants ────────────────────────────────

/// Corps de `POST /v1/cabinet/patients/:id/implants`.
#[derive(Deserialize)]
pub struct CreateImplantBody {
    pub brand: String,
    pub implant_ref: String,
    #[serde(default)]
    pub lot_number: Option<String>,
    #[serde(default)]
    pub placement_date: Option<String>,
    #[serde(default)]
    pub tooth_position: Option<String>,
    #[serde(default)]
    pub notes: Option<String>,
}

/// Réponse de `POST /v1/cabinet/patients/:id/implants`.
#[derive(Serialize)]
pub struct CreateImplantResponse {
    pub implant_id: Uuid,
}

/// `POST /v1/cabinet/patients/:id/implants` — enregistre un implant posé (#4140).
///
/// Praticien uniquement (`ProPractitionerClaims`) — `cabinet_id` extrait du
/// JWT, jamais du body (invariant tenancy). `patient_id` (path) inexistant ou
/// hors tenant → `404`. Garde §14 (relation de soin, même pattern que
/// `prescriptions.rs::create_prescription`/`dental_chart.rs`) : praticien
/// sans `appointment` avec ce patient dans ce cabinet → `403`. `brand`/
/// `implant_ref` vides → `422`. Visible ensuite côté patient via
/// `GET /v1/implant-passport`.
pub async fn create_implant(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
    Json(body): Json<CreateImplantBody>,
) -> Result<(StatusCode, Json<CreateImplantResponse>), AppError> {
    let brand = body.brand.trim().to_string();
    let implant_ref = body.implant_ref.trim().to_string();
    if brand.is_empty() || implant_ref.is_empty() {
        return Err(AppError::ValidationError);
    }
    crate::text_validation::reject_nul_byte(&brand)?;
    crate::text_validation::reject_nul_byte(&implant_ref)?;
    if let Some(lot) = &body.lot_number {
        crate::text_validation::reject_nul_byte(lot)?;
    }
    if let Some(tooth) = &body.tooth_position {
        crate::text_validation::reject_nul_byte(tooth)?;
    }
    if let Some(notes) = &body.notes {
        crate::text_validation::reject_nul_byte(notes)?;
    }
    let placement_date: Option<chrono::NaiveDate> = body
        .placement_date
        .as_deref()
        .map(|s| s.parse::<chrono::NaiveDate>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

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

    // Garde §14 (relation de soin) — même pattern que
    // prescriptions.rs/dental_chart.rs/periodontal_chart.rs.
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
           AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    let implant_row = sqlx::query(
        "INSERT INTO implant_passport \
         (cabinet_id, patient_id, implant_ref, brand, lot_number, placement_date, tooth_position, notes) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(&implant_ref)
    .bind(&brand)
    .bind(body.lot_number.as_deref())
    .bind(placement_date)
    .bind(body.tooth_position.as_deref())
    .bind(body.notes.as_deref())
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let implant_id: Uuid = implant_row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        implant_id = %implant_id,
        "implant created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateImplantResponse { implant_id }),
    ))
}
