//! Annuaire public géolocalisé des infirmières : `GET /v1/search/nurses`.
//!
//! Quand/Pourquoi : le patient (ou l'app) cherche les infirmières proches avant de
//! poser une demande de visite ; c'est aussi la base du matching de proximité
//! (mêmes prédicats `ST_DWithin`/`ST_Distance` que le fan-out d'offres). Route
//! publique sans JWT (pattern `GET /v1/pharmacies` / `search_providers`) : la RLS
//! `nurse_public_read` ne laisse passer que `is_listed AND deleted_at IS NULL`,
//! filtre répété dans le WHERE en défense en profondeur.
//! Modes d'échec : `lat`/`lng` fournis l'un sans l'autre, ou `radius_km` sans
//! point → 422.

use axum::extract::{Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::auth::AppError;
use crate::AppState;

/// Paramètres de `GET /v1/search/nurses`.
#[derive(Deserialize)]
pub struct SearchNursesQuery {
    pub q: Option<String>,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub radius_km: Option<f64>,
    /// Ne renvoyer que les infirmières actuellement en ligne (dispo).
    pub online_only: Option<bool>,
    pub per_page: Option<i64>,
}

/// Une infirmière de l'annuaire public.
#[derive(Serialize)]
pub struct NurseItem {
    pub id: Uuid,
    pub display_name: String,
    pub address: serde_json::Value,
    pub phone: Option<String>,
    pub is_online: bool,
    pub distance_m: Option<f64>,
}

/// Réponse de `GET /v1/search/nurses`.
#[derive(Serialize)]
pub struct SearchNursesResponse {
    pub data: Vec<NurseItem>,
}

/// `GET /v1/search/nurses` — annuaire public des infirmières listées, trié par
/// proximité si `lat`+`lng`. `online_only=true` borne aux disponibles.
pub async fn search_nurses(
    State(state): State<AppState>,
    Query(params): Query<SearchNursesQuery>,
) -> Result<Json<SearchNursesResponse>, AppError> {
    if params.lat.is_some() != params.lng.is_some()
        || (params.radius_km.is_some() && params.lat.is_none())
    {
        return Err(AppError::ValidationError);
    }

    if let Some(q) = params.q.as_deref() {
        crate::text_validation::reject_nul_byte(q)?;
    }

    let radius_m: Option<f64> = params.radius_km.map(|r| r * 1000.0);
    let per_page = params.per_page.unwrap_or(20).clamp(1, 50);
    let online_only = params.online_only.unwrap_or(false);
    let q = params
        .q
        .as_deref()
        .map(|s| s.trim().to_lowercase())
        .filter(|q| !q.is_empty());

    // $1=lat $2=lng $3=radius_m $4=q $5=online_only $6=limit
    let rows = sqlx::query(
        "SELECT id, display_name, address, phone, is_online, \
                CASE WHEN $1::float8 IS NOT NULL AND geo IS NOT NULL \
                     THEN ST_Distance(geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography) \
                END AS distance_m \
         FROM nurse \
         WHERE is_listed AND deleted_at IS NULL \
           AND (NOT $5::bool OR is_online) \
           AND ($4::text IS NULL \
                OR translate(lower(display_name), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                     LIKE '%' || translate($4, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
                OR translate(lower(address->>'city'), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                     LIKE '%' || translate($4, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
                OR address->>'postal_code' ILIKE '%' || $4 || '%') \
           AND ($3::float8 IS NULL \
                OR (geo IS NOT NULL \
                    AND ST_DWithin(geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3))) \
         ORDER BY distance_m ASC NULLS LAST, display_name ASC \
         LIMIT $6",
    )
    .bind(params.lat) // $1
    .bind(params.lng) // $2
    .bind(radius_m) // $3
    .bind(q.as_deref()) // $4
    .bind(online_only) // $5
    .bind(per_page) // $6
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in rows {
        data.push(NurseItem {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            display_name: row.try_get("display_name").map_err(|_| AppError::Internal)?,
            address: row.try_get("address").map_err(|_| AppError::Internal)?,
            phone: row.try_get("phone").map_err(|_| AppError::Internal)?,
            is_online: row.try_get("is_online").map_err(|_| AppError::Internal)?,
            distance_m: row.try_get("distance_m").map_err(|_| AppError::Internal)?,
        });
    }

    Ok(Json(SearchNursesResponse { data }))
}
