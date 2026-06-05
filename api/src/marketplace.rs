//! Référentiels marketplace : routes publiques (pas de JWT requis).

use axum::extract::{Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{auth::AppError, AppState};

#[derive(Serialize)]
pub struct ProfessionItem {
    pub id: Uuid,
    pub label: String,
}

#[derive(Serialize)]
pub struct ListProfessionsResponse {
    pub data: Vec<ProfessionItem>,
}

#[derive(Deserialize)]
pub struct ListSpecialtiesQuery {
    pub profession_id: Option<Uuid>,
}

#[derive(Serialize)]
pub struct SpecialtyItem {
    pub id: Uuid,
    pub profession_id: Option<Uuid>,
    pub label: String,
}

#[derive(Serialize)]
pub struct ListSpecialtiesResponse {
    pub data: Vec<SpecialtyItem>,
}

/// `GET /v1/specialties` — spécialités filtrables par profession (docs/12 §12.1).
///
/// Route publique, pas de JWT. Profession inconnue → tableau vide.
pub async fn list_specialties(
    State(state): State<AppState>,
    Query(params): Query<ListSpecialtiesQuery>,
) -> Result<Json<ListSpecialtiesResponse>, AppError> {
    let rows = sqlx::query_as!(
        SpecialtyItem,
        "SELECT id, profession_id, label FROM specialty \
         WHERE ($1::uuid IS NULL OR profession_id = $1) ORDER BY label",
        params.profession_id
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(Json(ListSpecialtiesResponse { data: rows }))
}

#[derive(Deserialize)]
pub struct ListActsQuery {
    pub specialty_id: Option<Uuid>,
}

#[derive(Serialize)]
pub struct ActItem {
    pub id: Uuid,
    pub specialty_id: Option<Uuid>,
    pub label: String,
    pub motifs: Vec<String>,
}

#[derive(Serialize)]
pub struct ListActsResponse {
    pub data: Vec<ActItem>,
}

/// `GET /v1/acts` — actes CCAM filtrables par spécialité (docs/12 §12.1).
///
/// Route publique, pas de JWT. `motifs` = synonymes texte du besoin patient.
pub async fn list_acts(
    State(state): State<AppState>,
    Query(params): Query<ListActsQuery>,
) -> Result<Json<ListActsResponse>, AppError> {
    let rows = sqlx::query_as!(
        ActItem,
        "SELECT id, specialty_id, label, motifs as \"motifs!\" FROM medical_act \
         WHERE ($1::uuid IS NULL OR specialty_id = $1) ORDER BY label",
        params.specialty_id
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(Json(ListActsResponse { data: rows }))
}

#[derive(Deserialize)]
pub struct SuggestQuery {
    pub q: String,
}

#[derive(Serialize)]
pub struct SuggestItem {
    pub id: Uuid,
    pub label: String,
    pub score: f64,
}

#[derive(Serialize)]
pub struct SuggestResponse {
    pub specialties: Vec<SuggestItem>,
    pub acts: Vec<SuggestItem>,
}

struct SuggestRow {
    id: Uuid,
    label: String,
}

/// `GET /v1/search/suggest` — autocomplete spécialités + actes (docs/12 §12.1).
///
/// Route publique, pas de JWT. `q` min 2 chars → 422. Score fixé à 1.0 au MVP.
/// Garde-fou réglementaire : labels d'orientation uniquement, jamais de diagnostic (07 §8).
pub async fn suggest_search(
    State(state): State<AppState>,
    Query(params): Query<SuggestQuery>,
) -> Result<Json<SuggestResponse>, AppError> {
    if params.q.chars().count() < 2 {
        return Err(AppError::ValidationError);
    }

    let specialty_rows = sqlx::query_as!(
        SuggestRow,
        "SELECT id, label FROM specialty \
         WHERE label ILIKE '%' || $1 || '%' \
         ORDER BY label LIMIT 5",
        params.q
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let act_rows = sqlx::query_as!(
        SuggestRow,
        "SELECT id, label FROM medical_act \
         WHERE label ILIKE '%' || $1 || '%' \
            OR EXISTS (SELECT 1 FROM unnest(motifs) AS m WHERE m ILIKE '%' || $1 || '%') \
         ORDER BY label LIMIT 5",
        params.q
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let specialties = specialty_rows
        .into_iter()
        .map(|r| SuggestItem {
            id: r.id,
            label: r.label,
            score: 1.0,
        })
        .collect();
    let acts = act_rows
        .into_iter()
        .map(|r| SuggestItem {
            id: r.id,
            label: r.label,
            score: 1.0,
        })
        .collect();

    Ok(Json(SuggestResponse { specialties, acts }))
}

/// `GET /v1/professions` — liste exhaustive des professions de santé (docs/12 §12.1).
///
/// Route publique, pas de JWT. Pas de RLS (table plateforme — migration 0009).
pub async fn list_professions(
    State(state): State<AppState>,
) -> Result<Json<ListProfessionsResponse>, AppError> {
    let rows = sqlx::query_as!(
        ProfessionItem,
        "SELECT id, label FROM profession ORDER BY label"
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(Json(ListProfessionsResponse { data: rows }))
}

// ── Provider search ──────────────────────────────────────────────────────────

#[derive(Deserialize)]
pub struct SearchProvidersQuery {
    pub q: Option<String>,
    pub specialty: Option<Uuid>,
    pub near: Option<String>,
    pub place: Option<String>,
    pub radius_km: Option<f64>,
    pub bbox: Option<String>,
    pub sector: Option<String>,
    pub teleconsult: Option<bool>,
    pub pmr: Option<bool>,
    pub languages: Option<String>,
    pub accepts_new: Option<bool>,
    pub available: Option<String>,
    pub sort: Option<String>,
    pub page: Option<i64>,
    pub per_page: Option<i64>,
}

#[derive(Serialize)]
pub struct ProviderItem {
    pub provider_id: Uuid,
    pub display_name: String,
    pub specialty: Option<String>,
    pub sector: Option<String>,
    pub distance_m: Option<f64>,
    pub next_slot_at: Option<String>,
    pub rating_avg: Option<f64>,
    pub geo: Option<serde_json::Value>,
    pub is_listed: bool,
}

#[derive(Serialize)]
pub struct FacetItem {
    pub value: String,
    pub count: i64,
}

#[derive(Serialize)]
pub struct SearchFacets {
    pub specialty: Vec<FacetItem>,
    pub sector: Vec<FacetItem>,
}

#[derive(Serialize)]
pub struct SearchPageInfo {
    pub page: i64,
    pub per_page: i64,
    pub total: i64,
}

#[derive(Serialize)]
pub struct SearchProvidersResponse {
    pub data: Vec<ProviderItem>,
    pub facets: SearchFacets,
    pub page: SearchPageInfo,
}

/// `GET /v1/search/providers` — annuaire public de praticiens (docs/12 §12.1).
///
/// Route publique, pas de JWT. Seuls les providers `is_listed=true` sont exposés
/// (RLS `provider_public_read` + clause WHERE explicite). `place` → geocoding EU
/// non implémenté au MVP (log warning). Distance via PostGIS si `near` fourni.
pub async fn search_providers(
    State(state): State<AppState>,
    Query(params): Query<SearchProvidersQuery>,
) -> Result<Json<SearchProvidersResponse>, AppError> {
    if params.place.is_some() {
        tracing::warn!("search_providers: `place` geocoding not implemented at MVP");
    }

    // Parse `near=lat,lng`
    let (near_lat, near_lng): (Option<f64>, Option<f64>) = match params.near.as_deref() {
        Some(s) => {
            let mut parts = s.splitn(2, ',');
            let lat = parts
                .next()
                .and_then(|v| v.trim().parse::<f64>().ok())
                .ok_or(AppError::ValidationError)?;
            let lng = parts
                .next()
                .and_then(|v| v.trim().parse::<f64>().ok())
                .ok_or(AppError::ValidationError)?;
            (Some(lat), Some(lng))
        }
        None => (None, None),
    };

    // Parse `bbox=minLng,minLat,maxLng,maxLat` (GeoJSON convention)
    let (bbox_min_lng, bbox_min_lat, bbox_max_lng, bbox_max_lat): (
        Option<f64>,
        Option<f64>,
        Option<f64>,
        Option<f64>,
    ) = match params.bbox.as_deref() {
        Some(s) => {
            let parts: Vec<&str> = s.splitn(4, ',').collect();
            if parts.len() != 4 {
                return Err(AppError::ValidationError);
            }
            let min_lng = parts[0]
                .trim()
                .parse::<f64>()
                .map_err(|_| AppError::ValidationError)?;
            let min_lat = parts[1]
                .trim()
                .parse::<f64>()
                .map_err(|_| AppError::ValidationError)?;
            let max_lng = parts[2]
                .trim()
                .parse::<f64>()
                .map_err(|_| AppError::ValidationError)?;
            let max_lat = parts[3]
                .trim()
                .parse::<f64>()
                .map_err(|_| AppError::ValidationError)?;
            (Some(min_lng), Some(min_lat), Some(max_lng), Some(max_lat))
        }
        None => (None, None, None, None),
    };

    let page = params.page.unwrap_or(1).max(1);
    let per_page = params.per_page.unwrap_or(20).clamp(1, 100);
    let offset = (page - 1) * per_page;
    let radius_m: Option<f64> = params.radius_km.map(|r| r * 1000.0);

    // Languages: comma-separated → vec for `&&` array overlap filter
    let lang_filter: Option<Vec<String>> = params
        .languages
        .as_ref()
        .map(|l| {
            l.split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect::<Vec<_>>()
        })
        .filter(|v| !v.is_empty());

    // Sort clause — only whitelisted constants, never user data
    let sort_clause = match params.sort.as_deref() {
        Some("distance") if near_lat.is_some() => {
            "ST_Distance(p.geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography) ASC NULLS LAST, \
             p.display_name ASC"
        }
        Some("rating") => "p.rating_avg DESC NULLS LAST, p.display_name ASC",
        Some("next_slot") => "next_slot_at ASC NULLS LAST, p.display_name ASC",
        _ => "p.display_name ASC",
    };

    // Available filter — hardcoded constants, never user data
    let available_clause = match params.available.as_deref() {
        Some("today") => {
            " AND EXISTS (\
              SELECT 1 FROM availability_slot sl \
              WHERE sl.provider_id = p.id AND sl.status = 'open' \
              AND sl.starts_at >= date_trunc('day', now()) \
              AND sl.starts_at < date_trunc('day', now()) + interval '1 day')"
        }
        Some("week") => {
            " AND EXISTS (\
              SELECT 1 FROM availability_slot sl \
              WHERE sl.provider_id = p.id AND sl.status = 'open' \
              AND sl.starts_at >= now() \
              AND sl.starts_at < now() + interval '7 days')"
        }
        _ => "",
    };

    // $1=near_lat  $2=near_lng  $3=radius_m  $4=q  $5=specialty_id
    // $6=sector    $7=teleconsult  $8=pmr     $9=accepts_new  $10=languages
    // $11=bbox_min_lng  $12=bbox_min_lat  $13=bbox_max_lng  $14=bbox_max_lat
    // $15=per_page  $16=offset
    let sql = format!(
        "SELECT \
             p.id AS provider_id, \
             p.display_name, \
             s.label AS specialty, \
             p.sector, \
             CASE WHEN $1::double precision IS NOT NULL AND $2::double precision IS NOT NULL \
                  THEN ST_Distance(p.geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography) \
                  ELSE NULL END AS distance_m, \
             (SELECT min(sl.starts_at) FROM availability_slot sl \
              WHERE sl.provider_id = p.id AND sl.status = 'open' AND sl.starts_at > now()) AS next_slot_at, \
             p.rating_avg::double precision AS rating_avg, \
             ST_Y(p.geo::geometry) AS geo_lat, \
             ST_X(p.geo::geometry) AS geo_lng, \
             p.is_listed, \
             COUNT(*) OVER() AS total_count \
         FROM provider p \
         LEFT JOIN specialty s ON s.id = p.specialty_id \
         WHERE p.is_listed = true \
             AND ($4::text IS NULL \
                  OR p.display_name ILIKE '%' || $4 || '%' \
                  OR s.label ILIKE '%' || $4 || '%') \
             AND ($5::uuid IS NULL OR p.specialty_id = $5) \
             AND ($6::text IS NULL OR p.sector = $6) \
             AND ($7::boolean IS NULL OR p.teleconsult = $7) \
             AND ($8::boolean IS NULL OR p.pmr = $8) \
             AND ($9::boolean IS NULL OR p.accepts_new_patients = $9) \
             AND ($10::text[] IS NULL \
                  OR (p.languages IS NOT NULL AND p.languages && $10)) \
             AND ($3::double precision IS NULL OR $1::double precision IS NULL \
                  OR p.geo IS NULL \
                  OR ST_DWithin(p.geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3)) \
             AND ($11::double precision IS NULL \
                  OR p.geo IS NULL \
                  OR ST_Within(p.geo::geometry, \
                     ST_MakeEnvelope($11, $12, $13, $14, 4326))) \
             {available_clause} \
         ORDER BY {sort_clause} \
         LIMIT $15 OFFSET $16"
    );

    let rows = sqlx::query(&sql)
        .bind(near_lat) // $1
        .bind(near_lng) // $2
        .bind(radius_m) // $3
        .bind(params.q.as_deref()) // $4
        .bind(params.specialty) // $5
        .bind(params.sector.as_deref()) // $6
        .bind(params.teleconsult) // $7
        .bind(params.pmr) // $8
        .bind(params.accepts_new) // $9
        .bind(lang_filter) // $10
        .bind(bbox_min_lng) // $11
        .bind(bbox_min_lat) // $12
        .bind(bbox_max_lng) // $13
        .bind(bbox_max_lat) // $14
        .bind(per_page) // $15
        .bind(offset) // $16
        .fetch_all(&state.db)
        .await
        .map_err(|_| AppError::Internal)?;

    let mut data: Vec<ProviderItem> = Vec::with_capacity(rows.len());
    let mut total: i64 = 0;

    for row in &rows {
        if let Ok(n) = row.try_get::<i64, _>("total_count") {
            total = n;
        }
        let geo_lat: Option<f64> = row.try_get("geo_lat").unwrap_or(None);
        let geo_lng: Option<f64> = row.try_get("geo_lng").unwrap_or(None);
        let geo = match (geo_lat, geo_lng) {
            (Some(lat), Some(lng)) => Some(serde_json::json!({"lat": lat, "lng": lng})),
            _ => None,
        };
        data.push(ProviderItem {
            provider_id: row.try_get("provider_id").map_err(|_| AppError::Internal)?,
            display_name: row
                .try_get("display_name")
                .map_err(|_| AppError::Internal)?,
            specialty: row.try_get("specialty").unwrap_or(None),
            sector: row.try_get("sector").unwrap_or(None),
            distance_m: row.try_get("distance_m").unwrap_or(None),
            next_slot_at: row
                .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("next_slot_at")
                .unwrap_or(None)
                .map(|dt| dt.to_rfc3339()),
            rating_avg: row.try_get("rating_avg").unwrap_or(None),
            geo,
            is_listed: row.try_get("is_listed").map_err(|_| AppError::Internal)?,
        });
    }

    // Facets: global counts for listed providers (filter-independent at MVP)
    let specialty_rows = sqlx::query(
        "SELECT s.label AS value, COUNT(p.id)::bigint AS count \
         FROM provider p \
         LEFT JOIN specialty s ON s.id = p.specialty_id \
         WHERE p.is_listed = true AND s.label IS NOT NULL \
         GROUP BY s.label \
         ORDER BY count DESC \
         LIMIT 20",
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let sector_rows = sqlx::query(
        "SELECT sector AS value, COUNT(*)::bigint AS count \
         FROM provider \
         WHERE is_listed = true AND sector IS NOT NULL \
         GROUP BY sector \
         ORDER BY count DESC",
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let specialty_facets = specialty_rows
        .iter()
        .map(|r| {
            Ok(FacetItem {
                value: r.try_get("value").map_err(|_| AppError::Internal)?,
                count: r.try_get("count").map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    let sector_facets = sector_rows
        .iter()
        .map(|r| {
            Ok(FacetItem {
                value: r.try_get("value").map_err(|_| AppError::Internal)?,
                count: r.try_get("count").map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(SearchProvidersResponse {
        data,
        facets: SearchFacets {
            specialty: specialty_facets,
            sector: sector_facets,
        },
        page: SearchPageInfo {
            page,
            per_page,
            total,
        },
    }))
}
