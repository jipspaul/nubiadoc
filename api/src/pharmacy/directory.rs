//! Annuaire public des pharmacies : `GET /v1/pharmacies`.

use axum::extract::{Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::auth::AppError;
use crate::AppState;

/// Paramètres de `GET /v1/pharmacies`.
#[derive(Deserialize)]
pub struct SearchPharmaciesQuery {
    pub q: Option<String>,
    pub lat: Option<f64>,
    pub lng: Option<f64>,
    pub radius_km: Option<f64>,
    pub per_page: Option<i64>,
}

/// Une pharmacie de l'annuaire public.
#[derive(Serialize)]
pub struct PharmacyItem {
    pub id: Uuid,
    pub raison_sociale: String,
    pub address: serde_json::Value,
    pub phone: Option<String>,
    pub distance_m: Option<f64>,
}

/// Réponse de `GET /v1/pharmacies`.
#[derive(Serialize)]
pub struct SearchPharmaciesResponse {
    pub data: Vec<PharmacyItem>,
}

/// `GET /v1/pharmacies` — annuaire public des pharmacies listées.
///
/// Route publique, pas de JWT (pattern `GET /v1/search/providers`). La policy RLS
/// `pharmacy_public_read` ne laisse passer que `is_listed AND deleted_at IS NULL`
/// (aucun GUC posé) ; le filtre est répété dans le WHERE en défense en profondeur.
///
/// Filtres : `q` (raison sociale, ville ou code postal, insensible à la casse
/// ET aux accents — cf. `search_ccam_acts`, #3578), `lat`+`lng` (tri par
/// distance, PostGIS) et `radius_km` (borne la recherche).
/// `422` si `lat`/`lng` sont fournis l'un sans l'autre ou si `radius_km` est
/// fourni sans point.
pub async fn search_pharmacies(
    State(state): State<AppState>,
    Query(params): Query<SearchPharmaciesQuery>,
) -> Result<Json<SearchPharmaciesResponse>, AppError> {
    // #7817 : même doctrine géo que /v1/search/providers et /v1/search/slots
    // (#7774) — bornes de validation lat/lng/radius_km ET rayon par défaut
    // (`GEO_DEFAULT_RADIUS_KM`) via `resolve_geo_filter`, plutôt qu'une
    // validation inline affaiblie qui laissait passer `lat=999`/`NaN`/
    // `radius_km<=0` et ne bornait pas le filtre géo quand `radius_km` était
    // omis (annuaire national renvoyé au lieu d'un rayon de 20km).
    let (near_lat, near_lng, radius_km) = crate::marketplace::resolve_geo_filter(
        None,
        params.lat,
        params.lng,
        None,
        params.radius_km,
    )?;

    // #4394 : NUL byte non filtré → 500 au bind (translate()/ILIKE).
    if let Some(q) = params.q.as_deref() {
        crate::text_validation::reject_nul_byte(q)?;
    }

    let radius_m: Option<f64> = radius_km.map(|r| r * 1000.0);
    let per_page = params.per_page.unwrap_or(20).clamp(1, 50);
    // q normalisée (trim + minuscules) ; la normalisation des accents se fait
    // en SQL via translate(), même pattern que search_ccam_acts (#3226).
    let q = params
        .q
        .as_deref()
        .map(|s| s.trim().to_lowercase())
        .filter(|q| !q.is_empty());

    // $1=lat  $2=lng  $3=radius_m  $4=q  $5=limit
    let rows = sqlx::query(
        "SELECT id, raison_sociale, address, phone, \
                CASE WHEN $1::float8 IS NOT NULL AND geo IS NOT NULL \
                     THEN ST_Distance(geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography) \
                END AS distance_m \
         FROM pharmacy \
         WHERE is_listed AND deleted_at IS NULL \
           AND ($4::text IS NULL \
                OR translate(lower(raison_sociale), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                     LIKE '%' || translate($4, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
                OR translate(lower(address->>'city'), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                     LIKE '%' || translate($4, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
                OR address->>'postal_code' ILIKE '%' || $4 || '%') \
           AND ($3::float8 IS NULL \
                OR (geo IS NOT NULL \
                    AND ST_DWithin(geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3))) \
         ORDER BY distance_m ASC NULLS LAST, raison_sociale ASC \
         LIMIT $5",
    )
    .bind(near_lat) // $1
    .bind(near_lng) // $2
    .bind(radius_m) // $3
    .bind(q.as_deref()) // $4
    .bind(per_page) // $5
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in rows {
        data.push(PharmacyItem {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            raison_sociale: row
                .try_get("raison_sociale")
                .map_err(|_| AppError::Internal)?,
            address: row.try_get("address").map_err(|_| AppError::Internal)?,
            phone: row.try_get("phone").map_err(|_| AppError::Internal)?,
            distance_m: row.try_get("distance_m").map_err(|_| AppError::Internal)?,
        });
    }

    Ok(Json(SearchPharmaciesResponse { data }))
}
