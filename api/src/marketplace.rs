//! Référentiels marketplace : routes publiques (pas de JWT requis).

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

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
    #[serde(default)]
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

// ── Slot search ──────────────────────────────────────────────────────────────

#[derive(Serialize)]
pub struct SlotRef {
    pub slot_id: Uuid,
    pub starts_at: String,
}

#[derive(Serialize)]
pub struct SlotProviderItem {
    pub provider_id: Uuid,
    pub display_name: String,
    pub distance_m: Option<f64>,
    pub first_slot_at: String,
    pub slots: Vec<SlotRef>,
}

#[derive(Serialize)]
pub struct SearchSlotsResponse {
    pub data: Vec<SlotProviderItem>,
}

/// Fragment SQL du filtre `available` sur `sl.starts_at` (constantes hardcodées,
/// jamais de données utilisateur interpolées). Vocabulaire aligné sur celui émis
/// par `detect_available` (`/search/parse`) : `today`, `week`/`this_week`, et les
/// noms de jours anglais (`monday`…`sunday`).
fn available_time_clause(available: Option<&str>) -> &'static str {
    match available {
        Some("today") => {
            " AND sl.starts_at >= date_trunc('day', now()) \
              AND sl.starts_at < date_trunc('day', now()) + interval '1 day'"
        }
        Some("week") | Some("this_week") => " AND sl.starts_at < now() + interval '7 days'",
        Some("monday") => " AND EXTRACT(DOW FROM sl.starts_at) = 1",
        Some("tuesday") => " AND EXTRACT(DOW FROM sl.starts_at) = 2",
        Some("wednesday") => " AND EXTRACT(DOW FROM sl.starts_at) = 3",
        Some("thursday") => " AND EXTRACT(DOW FROM sl.starts_at) = 4",
        Some("friday") => " AND EXTRACT(DOW FROM sl.starts_at) = 5",
        Some("saturday") => " AND EXTRACT(DOW FROM sl.starts_at) = 6",
        Some("sunday") => " AND EXTRACT(DOW FROM sl.starts_at) = 0",
        _ => "",
    }
}

/// `GET /v1/search/slots` — prochains créneaux disponibles par praticien (docs/12 §12.1).
///
/// Route publique, pas de JWT. Mêmes filtres que `/v1/search/providers`.
/// Retourne uniquement les créneaux `status='open'` et `online_booking=true`
/// (RLS `slot_public_read`), triés par `first_slot_at` ascendant.
pub async fn search_slots(
    State(state): State<AppState>,
    Query(params): Query<SearchProvidersQuery>,
) -> Result<Json<SearchSlotsResponse>, AppError> {
    if params.place.is_some() {
        tracing::warn!("search_slots: `place` geocoding not implemented at MVP");
    }

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

    let radius_m: Option<f64> = params.radius_km.map(|r| r * 1000.0);

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

    let available_clause = available_time_clause(params.available.as_deref());

    // $1=near_lat  $2=near_lng  $3=radius_m  $4=q  $5=specialty_id
    // $6=sector    $7=teleconsult  $8=pmr     $9=accepts_new  $10=languages
    // $11=bbox_min_lng  $12=bbox_min_lat  $13=bbox_max_lng  $14=bbox_max_lat
    let sql = format!(
        "SELECT \
             p.id AS provider_id, \
             p.display_name, \
             CASE WHEN $1::double precision IS NOT NULL AND $2::double precision IS NOT NULL \
                  THEN ST_Distance(p.geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography) \
                  ELSE NULL END AS distance_m, \
             sl.id AS slot_id, \
             sl.starts_at \
         FROM availability_slot sl \
         JOIN provider p ON p.id = sl.provider_id \
         LEFT JOIN specialty s ON s.id = p.specialty_id \
         WHERE p.is_listed = true \
             AND sl.status = 'open' \
             AND sl.deleted_at IS NULL \
             AND sl.online_booking = true \
             AND sl.starts_at > now() \
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
                  OR (p.geo IS NOT NULL \
                      AND ST_DWithin(p.geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3))) \
             AND ($11::double precision IS NULL \
                  OR (p.geo IS NOT NULL \
                      AND ST_Within(p.geo::geometry, \
                          ST_MakeEnvelope($11, $12, $13, $14, 4326)))) \
             {available_clause} \
         ORDER BY sl.starts_at ASC"
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
        .fetch_all(&state.db)
        .await
        .map_err(|_| AppError::Internal)?;

    // Group by provider, preserving first-slot order (rows already sorted ASC by starts_at)
    let mut data: Vec<SlotProviderItem> = Vec::new();
    for row in &rows {
        let provider_id: Uuid = row.try_get("provider_id").map_err(|_| AppError::Internal)?;
        let starts_at: chrono::DateTime<chrono::Utc> =
            row.try_get("starts_at").map_err(|_| AppError::Internal)?;
        let slot_ref = SlotRef {
            slot_id: row.try_get("slot_id").map_err(|_| AppError::Internal)?,
            starts_at: starts_at.to_rfc3339(),
        };
        if let Some(entry) = data.iter_mut().find(|e| e.provider_id == provider_id) {
            entry.slots.push(slot_ref);
        } else {
            let distance_m: Option<f64> = row.try_get("distance_m").unwrap_or(None);
            data.push(SlotProviderItem {
                provider_id,
                display_name: row
                    .try_get("display_name")
                    .map_err(|_| AppError::Internal)?,
                distance_m,
                first_slot_at: starts_at.to_rfc3339(),
                slots: vec![slot_ref],
            });
        }
    }

    Ok(Json(SearchSlotsResponse { data }))
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
    let available_time = available_time_clause(params.available.as_deref());
    let available_clause = if available_time.is_empty() {
        String::new()
    } else {
        format!(
            " AND EXISTS (\
              SELECT 1 FROM availability_slot sl \
              WHERE sl.provider_id = p.id AND sl.status = 'open' \
              AND sl.deleted_at IS NULL AND sl.online_booking = true{available_time})"
        )
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
              WHERE sl.provider_id = p.id AND sl.status = 'open' \
              AND sl.deleted_at IS NULL AND sl.online_booking = true \
              AND sl.starts_at > now()) AS next_slot_at, \
             p.rating_avg::double precision AS rating_avg, \
             ST_Y(p.geo::geometry) AS geo_lat, \
             ST_X(p.geo::geometry) AS geo_lng, \
             p.is_listed, \
             COUNT(*) OVER() AS total_count \
         FROM provider p \
         LEFT JOIN specialty s ON s.id = p.specialty_id \
         LEFT JOIN profession pr ON pr.id = s.profession_id \
         WHERE p.is_listed = true \
             AND ($4::text IS NULL \
                  OR p.display_name ILIKE '%' || $4 || '%' \
                  OR s.label ILIKE '%' || $4 || '%' \
                  OR pr.label ILIKE '%' || $4 || '%') \
             AND ($5::uuid IS NULL OR p.specialty_id = $5) \
             AND ($6::text IS NULL OR p.sector = $6) \
             AND ($7::boolean IS NULL OR p.teleconsult = $7) \
             AND ($8::boolean IS NULL OR p.pmr = $8) \
             AND ($9::boolean IS NULL OR p.accepts_new_patients = $9) \
             AND ($10::text[] IS NULL \
                  OR (p.languages IS NOT NULL AND p.languages && $10)) \
             AND ($3::double precision IS NULL OR $1::double precision IS NULL \
                  OR (p.geo IS NOT NULL \
                      AND ST_DWithin(p.geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, $3))) \
             AND ($11::double precision IS NULL \
                  OR (p.geo IS NOT NULL \
                      AND ST_Within(p.geo::geometry, \
                          ST_MakeEnvelope($11, $12, $13, $14, 4326)))) \
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

// ── Provider profile ──────────────────────────────────────────────────────────

/// Réponse de `GET /v1/providers/:id` (docs/12 §12.2).
#[derive(Serialize)]
pub struct ProviderProfile {
    pub provider_id: Uuid,
    pub display_name: String,
    pub specialty: Option<String>,
    pub profession: Option<String>,
    pub sector: Option<String>,
    pub rpps_verified: bool,
    pub is_listed: bool,
    pub bio: Option<String>,
    pub languages: Option<Vec<String>>,
    pub address: Option<serde_json::Value>,
    pub geo: Option<serde_json::Value>,
    pub tiers_payant: Option<bool>,
    pub teleconsult: Option<bool>,
    pub pmr: Option<bool>,
    pub establishment_id: Option<Uuid>,
    pub rating_avg: Option<f64>,
    pub review_count: i64,
}

/// `GET /v1/providers/:id` — profil public complet d'un praticien (docs/12 §12.2).
///
/// Route publique, pas de JWT. Provider `is_listed=false` ou inexistant → `404`
/// (masquer l'existence pour ne pas divulguer les profils non listés).
pub async fn get_provider(
    State(state): State<AppState>,
    Path(provider_id): Path<Uuid>,
) -> Result<Json<ProviderProfile>, AppError> {
    let row = sqlx::query(
        "SELECT \
             p.id AS provider_id, \
             p.display_name, \
             s.label AS specialty, \
             pr.label AS profession, \
             p.sector, \
             p.rpps_verified, \
             p.is_listed, \
             p.bio, \
             p.languages, \
             e.address, \
             ST_Y(p.geo::geometry) AS geo_lat, \
             ST_X(p.geo::geometry) AS geo_lng, \
             p.tiers_payant, \
             p.teleconsult, \
             p.pmr, \
             p.establishment_id, \
             p.rating_avg::double precision AS rating_avg, \
             p.rating_count \
         FROM provider p \
         LEFT JOIN specialty s  ON s.id  = p.specialty_id \
         LEFT JOIN profession pr ON pr.id = s.profession_id \
         LEFT JOIN establishment e ON e.id = p.establishment_id \
         WHERE p.id = $1 AND p.is_listed = true",
    )
    .bind(provider_id)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let geo_lat: Option<f64> = row.try_get("geo_lat").unwrap_or(None);
    let geo_lng: Option<f64> = row.try_get("geo_lng").unwrap_or(None);
    let geo = match (geo_lat, geo_lng) {
        (Some(lat), Some(lng)) => Some(serde_json::json!({"lat": lat, "lng": lng})),
        _ => None,
    };

    let review_count: i32 = row.try_get("rating_count").unwrap_or(0);

    Ok(Json(ProviderProfile {
        provider_id: row.try_get("provider_id").map_err(|_| AppError::Internal)?,
        display_name: row
            .try_get("display_name")
            .map_err(|_| AppError::Internal)?,
        specialty: row.try_get("specialty").unwrap_or(None),
        profession: row.try_get("profession").unwrap_or(None),
        sector: row.try_get("sector").unwrap_or(None),
        rpps_verified: row
            .try_get("rpps_verified")
            .map_err(|_| AppError::Internal)?,
        is_listed: row.try_get("is_listed").map_err(|_| AppError::Internal)?,
        bio: row.try_get("bio").unwrap_or(None),
        languages: row.try_get("languages").unwrap_or(None),
        address: row.try_get("address").unwrap_or(None),
        geo,
        tiers_payant: row.try_get("tiers_payant").unwrap_or(None),
        teleconsult: row.try_get("teleconsult").unwrap_or(None),
        pmr: row.try_get("pmr").unwrap_or(None),
        establishment_id: row.try_get("establishment_id").unwrap_or(None),
        rating_avg: row.try_get("rating_avg").unwrap_or(None),
        review_count: review_count as i64,
    }))
}

// ── Provider availability ─────────────────────────────────────────────────────

#[derive(Serialize)]
pub struct AvailabilitySlotItem {
    pub slot_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub motif: Option<String>,
}

#[derive(Serialize)]
pub struct ProviderAvailabilityResponse {
    pub data: Vec<AvailabilitySlotItem>,
}

struct AvailabilitySlotRow {
    slot_id: Uuid,
    starts_at: chrono::DateTime<chrono::Utc>,
    ends_at: chrono::DateTime<chrono::Utc>,
    motif: Option<String>,
}

#[derive(Deserialize)]
pub struct AvailabilityQuery {
    pub from: Option<String>,
    pub to: Option<String>,
    pub motif: Option<String>,
}

/// `GET /v1/providers/:id/availability` — 50 prochains créneaux ouverts (docs/12 §12.2).
///
/// Route publique, pas de JWT. Provider inexistant ou `is_listed=false` → `404`.
/// Créneaux filtrés `status='open'` + `online_booking=true` + `starts_at > now()`,
/// bornables par `?from=&to=` (RFC3339) et `?motif=`, triés ASC, limite 50.
pub async fn get_provider_availability(
    State(state): State<AppState>,
    Path(provider_id): Path<Uuid>,
    Query(params): Query<AvailabilityQuery>,
) -> Result<Json<ProviderAvailabilityResponse>, AppError> {
    sqlx::query!(
        "SELECT id FROM provider WHERE id = $1 AND is_listed = true",
        provider_id
    )
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let from = params
        .from
        .as_deref()
        .map(|s| s.parse::<chrono::DateTime<chrono::Utc>>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;
    let to = params
        .to
        .as_deref()
        .map(|s| s.parse::<chrono::DateTime<chrono::Utc>>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let rows = sqlx::query_as!(
        AvailabilitySlotRow,
        r#"SELECT id AS "slot_id!", starts_at, ends_at, motif
           FROM availability_slot
           WHERE provider_id = $1
             AND status = 'open'
             AND deleted_at IS NULL
             AND online_booking = true
             AND starts_at > now()
             AND ($2::timestamptz IS NULL OR starts_at >= $2)
             AND ($3::timestamptz IS NULL OR starts_at < $3)
             AND ($4::text IS NULL OR motif = $4)
           ORDER BY starts_at ASC
           LIMIT 50"#,
        provider_id,
        from,
        to,
        params.motif,
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let data = rows
        .into_iter()
        .map(|r| AvailabilitySlotItem {
            slot_id: r.slot_id,
            starts_at: r.starts_at.to_rfc3339(),
            ends_at: r.ends_at.to_rfc3339(),
            motif: r.motif,
        })
        .collect();

    Ok(Json(ProviderAvailabilityResponse { data }))
}

// ── Slot hold ─────────────────────────────────────────────────────────────────

/// Réponse de `POST /v1/slots/:id/hold`.
#[derive(Serialize)]
pub struct SlotHoldResponse {
    pub hold_token: String,
    pub expires_at: String,
}

/// `POST /v1/slots/:id/hold` — bloque un créneau 5 min (marketplace, issue #1659).
///
/// JWT patient requis. Génère un `hold_token` UUID aléatoire, INSERT dans
/// `slot_holds`, passe le slot en `status='held'`. Contrainte UNIQUE sur
/// `slot_id` → `409 slot_taken` si déjà held par un autre patient.
/// Slot inexistant → `404`. Slot `held` ou `booked` → `409 slot_taken`.
pub async fn hold_slot(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(slot_id): Path<Uuid>,
) -> Result<(StatusCode, Json<SlotHoldResponse>), AppError> {
    let hold_token = Uuid::new_v4().to_string();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Claim + INSERT atomiques via claim_and_hold_slot() SECURITY DEFINER
    // (cf. migration 0120). La fonction contourne la RLS `slot_holds` (policy
    // slot_hold_cabinet_isolation, migration 0110) qui exige app.current_cabinet_id
    // — GUC jamais posé dans le parcours patient, d'où l'ancien 500 (#3259).
    // Retour : NULL → 404 ; 'claimed' → 200 ; autre ('taken'/statut) → 409.
    let row =
        sqlx::query("SELECT claim_result, hold_expires_at FROM claim_and_hold_slot($1, $2, $3)")
            .bind(slot_id)
            .bind(claims.sub)
            .bind(&hold_token)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    let claim_result: Option<String> = row
        .try_get("claim_result")
        .map_err(|_| AppError::Internal)?;
    match claim_result.as_deref() {
        None => return Err(AppError::NotFound),
        Some("claimed") => {} // claim + hold réussis
        Some(_) => return Err(AppError::SlotTaken),
    };

    let expires_at: chrono::DateTime<chrono::Utc> = row
        .try_get("hold_expires_at")
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok((
        StatusCode::OK,
        Json(SlotHoldResponse {
            hold_token,
            expires_at: expires_at.to_rfc3339(),
        }),
    ))
}

// ── Recherche en langage naturel (parse) ─────────────────────────────────────

/// Corps de `POST /v1/search/parse`.
#[derive(Deserialize)]
pub struct ParseSearchBody {
    pub q: String,
}

/// Filtres structurés — reprend les query params de `GET /v1/search/providers`
/// (voir [`SearchProvidersQuery`]). Les champs absents sont sérialisés en `null`.
#[derive(Serialize)]
pub struct ParsedQuery {
    pub q: Option<String>,
    pub specialty: Option<Uuid>,
    pub place: Option<String>,
    pub near: Option<String>,
    pub sector: Option<String>,
    pub available: Option<String>,
    pub teleconsult: Option<bool>,
}

#[derive(Serialize)]
pub struct ParseSearchResponse {
    pub query: ParsedQuery,
    pub interpretation: String,
    /// `"keywords"` (passe mots-clés gratuite) ou `"llm"` (secours Claude).
    pub source: String,
}

/// `POST /v1/search/parse` — traduit une requête en langage naturel en filtres
/// structurés (docs/12 §12.1). Route publique, pas de JWT.
///
/// Mode **hybride** : passe 1 par mots-clés (toujours, gratuite), puis passe 2
/// via Claude en secours si la requête reste ambiguë ET que `ANTHROPIC_API_KEY`
/// est présente. Sans clé, l'endpoint fonctionne en mode dégradé (`source:"keywords"`).
///
/// `q` < 2 caractères → 422 (comme `suggest_search`).
pub async fn parse_search(
    State(state): State<AppState>,
    Json(body): Json<ParseSearchBody>,
) -> Result<Json<ParseSearchResponse>, AppError> {
    let raw = body.q.trim().to_string();
    if raw.chars().count() < 2 {
        return Err(AppError::ValidationError);
    }

    // ── Passe 1 : mots-clés (toujours, gratuite) ──
    let (mut query, mut interpretation) = keyword_parse(&state.db, &raw).await;
    let mut source = "keywords".to_string();

    // Ambiguïté : aucune spécialité résolue OU phrase longue (> 6 mots).
    let word_count = raw.split_whitespace().count();
    let ambiguous = query.specialty.is_none() || word_count > 6;

    // ── Passe 2 : LLM en secours (dégradation propre sans clé) ──
    if ambiguous {
        if let Ok(key) = std::env::var("ANTHROPIC_API_KEY") {
            if !key.trim().is_empty() {
                if let Some((llm_query, llm_interp)) = llm_parse(&state.db, &raw, &key).await {
                    query = llm_query;
                    interpretation = llm_interp;
                    source = "llm".to_string();
                }
            }
        }
    }

    Ok(Json(ParseSearchResponse {
        query,
        interpretation,
        source,
    }))
}

/// Mots vides ignorés lors de la résolution de spécialité (évite les faux positifs
/// ILIKE sur « pas », « pour », « secteur »…).
const PARSE_STOPWORDS: &[&str] = &[
    "pres",
    "près",
    "proche",
    "autour",
    "alentours",
    "dispo",
    "disponible",
    "cette",
    "semaine",
    "soir",
    "aujourd",
    "aujourdhui",
    "pour",
    "avec",
    "dans",
    "sur",
    "les",
    "des",
    "une",
    "chez",
    "secteur",
    "conventionne",
    "conventionné",
    "conventionnee",
    "cher",
    "distance",
    "visio",
    "teleconsultation",
    "téléconsultation",
    "rendez",
    "vous",
    "lundi",
    "mardi",
    "mercredi",
    "jeudi",
    "vendredi",
    "samedi",
    "dimanche",
];

/// Passe mots-clés : heuristiques FR + résolution de spécialité en base.
async fn keyword_parse(db: &sqlx::PgPool, raw: &str) -> (ParsedQuery, String) {
    let lower = raw.to_lowercase();

    let sector = if lower.contains("pas cher")
        || lower.contains("conventionné")
        || lower.contains("conventionnee")
        || lower.contains("secteur 1")
    {
        Some("1".to_string())
    } else {
        None
    };

    let available = detect_available(&lower);

    let teleconsult = if lower.contains("téléconsult")
        || lower.contains("teleconsult")
        || lower.contains("visio")
        || lower.contains("à distance")
        || lower.contains("a distance")
    {
        Some(true)
    } else {
        None
    };

    let place = detect_place(raw);

    let (specialty, specialty_label, clean_q) = resolve_specialty(db, raw).await;

    let query = ParsedQuery {
        q: clean_q,
        specialty,
        place,
        near: None,
        sector,
        available,
        teleconsult,
    };

    let interpretation = build_interpretation(&query, specialty_label.as_deref());
    (query, interpretation)
}

/// Détecte une disponibilité (« ce soir », « cette semaine », un jour de semaine…).
fn detect_available(lower: &str) -> Option<String> {
    if lower.contains("ce soir") || lower.contains("aujourd'hui") || lower.contains("aujourdhui") {
        return Some("today".to_string());
    }
    if lower.contains("cette semaine") {
        return Some("this_week".to_string());
    }
    let days = [
        ("lundi", "monday"),
        ("mardi", "tuesday"),
        ("mercredi", "wednesday"),
        ("jeudi", "thursday"),
        ("vendredi", "friday"),
        ("samedi", "saturday"),
        ("dimanche", "sunday"),
    ];
    for (fr, en) in days {
        if lower.contains(fr) {
            return Some(en.to_string());
        }
    }
    None
}

/// Extrait un lieu depuis « près de X », « autour de X », « à X ».
fn detect_place(raw: &str) -> Option<String> {
    let words: Vec<&str> = raw.split_whitespace().collect();
    let lower: Vec<String> = words.iter().map(|w| w.to_lowercase()).collect();
    let n = words.len();

    for i in 0..n {
        // « près de X », « autour de X », « proche de X »
        if matches!(
            lower[i].as_str(),
            "près" | "pres" | "autour" | "proche" | "alentours"
        ) && i + 2 < n
            && matches!(lower[i + 1].as_str(), "de" | "du" | "des" | "d'")
        {
            if let Some(p) = clean_place_word(words[i + 2]) {
                return Some(p);
            }
        }

        // « à X » : on exige un nom propre (majuscule) et on écarte « à distance ».
        if (lower[i] == "à" || lower[i] == "a")
            && i + 1 < n
            && lower[i + 1] != "distance"
            && words[i + 1].chars().next().is_some_and(char::is_uppercase)
        {
            if let Some(p) = clean_place_word(words[i + 1]) {
                return Some(p);
            }
        }
    }
    None
}

/// Nettoie un mot-lieu (retire la ponctuation de bord). `None` si vide.
fn clean_place_word(w: &str) -> Option<String> {
    let cleaned = w.trim_matches(|c: char| !c.is_alphanumeric());
    if cleaned.is_empty() {
        None
    } else {
        Some(cleaned.to_string())
    }
}

/// Résout une spécialité (uuid + label + `q` nettoyé) via ILIKE sur
/// `specialty.label`, `medical_act.label`/`motifs`, puis `profession.label`.
/// Retourne au premier mot significatif qui matche.
async fn resolve_specialty(
    db: &sqlx::PgPool,
    raw: &str,
) -> (Option<Uuid>, Option<String>, Option<String>) {
    for word in raw.split_whitespace() {
        let term = word.trim_matches(|c: char| !c.is_alphanumeric());
        if term.chars().count() < 3 {
            continue;
        }
        if PARSE_STOPWORDS.contains(&term.to_lowercase().as_str()) {
            continue;
        }

        // 1) Spécialité par label.
        let sql = "SELECT id, label FROM specialty \
                   WHERE label ILIKE '%' || $1 || '%' ORDER BY label LIMIT 1";
        if let Ok(Some(row)) = sqlx::query(sql).bind(term).fetch_optional(db).await {
            if let Ok(id) = row.try_get::<Uuid, _>("id") {
                let label = row.try_get::<String, _>("label").unwrap_or_default();
                return (Some(id), Some(label), Some(term.to_lowercase()));
            }
        }

        // 2) Acte médical (label ou motif) → sa spécialité.
        let sql = "SELECT s.id AS id, s.label AS label \
                   FROM medical_act m JOIN specialty s ON s.id = m.specialty_id \
                   WHERE m.label ILIKE '%' || $1 || '%' \
                      OR EXISTS (SELECT 1 FROM unnest(m.motifs) AS mo WHERE mo ILIKE '%' || $1 || '%') \
                   ORDER BY s.label LIMIT 1";
        if let Ok(Some(row)) = sqlx::query(sql).bind(term).fetch_optional(db).await {
            if let Ok(id) = row.try_get::<Uuid, _>("id") {
                let label = row.try_get::<String, _>("label").unwrap_or_default();
                return (Some(id), Some(label), Some(term.to_lowercase()));
            }
        }

        // 3) Profession (ex. « dentiste » → « Chirurgien-dentiste »).
        // Une profession avec une seule spécialité peut être résolue précisément ;
        // sinon (ex. Chirurgien-dentiste = Omnipratique + Implantologie…) on NE
        // collapse PAS sur une spécialité arbitraire : specialty reste `None` et
        // la recherche reste à l'échelle de la profession via `q` (cf. #3618).
        let sql = "SELECT pr.label AS profession_label, s.id AS specialty_id, \
                          s.label AS specialty_label \
                   FROM profession pr JOIN specialty s ON s.profession_id = pr.id \
                   WHERE pr.label ILIKE '%' || $1 || '%' ORDER BY s.label";
        if let Ok(rows) = sqlx::query(sql).bind(term).fetch_all(db).await {
            if rows.len() == 1 {
                if let Ok(id) = rows[0].try_get::<Uuid, _>("specialty_id") {
                    let label = rows[0]
                        .try_get::<String, _>("specialty_label")
                        .unwrap_or_default();
                    return (Some(id), Some(label), Some(term.to_lowercase()));
                }
            } else if let Some(row) = rows.first() {
                let label = row
                    .try_get::<String, _>("profession_label")
                    .unwrap_or_default();
                return (None, Some(label), Some(term.to_lowercase()));
            }
        }
    }
    (None, None, None)
}

/// Construit une interprétation lisible en français.
fn build_interpretation(query: &ParsedQuery, specialty_label: Option<&str>) -> String {
    let mut parts: Vec<String> = Vec::new();

    if let Some(label) = specialty_label {
        parts.push(capitalize(label));
    } else if let Some(q) = &query.q {
        parts.push(capitalize(q));
    } else {
        parts.push("Recherche".to_string());
    }

    if query.sector.as_deref() == Some("1") {
        parts.push("secteur 1".to_string());
    }
    if query.teleconsult == Some(true) {
        parts.push("en téléconsultation".to_string());
    }
    if let Some(place) = &query.place {
        parts.push(format!("près de {place}"));
    }

    let mut interp = parts.join(" ");
    if let Some(avail) = &query.available {
        interp.push_str(&format!(", {}", available_fr(avail)));
    }
    interp
}

/// Rend une disponibilité lisible en français.
fn available_fr(a: &str) -> String {
    let day = match a {
        "today" => "aujourd'hui",
        "this_week" => "cette semaine",
        "monday" => "lundi",
        "tuesday" => "mardi",
        "wednesday" => "mercredi",
        "thursday" => "jeudi",
        "friday" => "vendredi",
        "saturday" => "samedi",
        "sunday" => "dimanche",
        other => other,
    };
    format!("disponible {day}")
}

/// Met la première lettre en majuscule.
fn capitalize(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        Some(f) => f.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

/// Passe 2 : appelle Claude (`claude-haiku-4-5-20251001`) pour extraire le JSON
/// structuré. Client async, timeout court (~4 s). Toute erreur réseau/parse →
/// `None` (fallback silencieux sur le résultat mots-clés — jamais de 500).
async fn llm_parse(db: &sqlx::PgPool, raw: &str, api_key: &str) -> Option<(ParsedQuery, String)> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(4))
        .build()
        .ok()?;

    let prompt = format!(
        "Tu es un assistant qui traduit une requête patient d'annuaire médical en filtres de recherche.\n\
         Requête : \"{raw}\".\n\
         Réponds UNIQUEMENT avec un objet JSON valide (aucun texte autour), avec exactement ces clés :\n\
         - q : chaîne (spécialité ou motif principal) ou null\n\
         - place : quartier/ville mentionné ou null\n\
         - near : null\n\
         - sector : \"1\" si le patient veut du conventionné / pas cher / secteur 1, sinon null\n\
         - available : \"today\", \"this_week\", ou un jour (\"monday\"..\"sunday\") ou null\n\
         - teleconsult : true si téléconsultation/visio/à distance, sinon null\n\
         - interpretation : phrase courte en français résumant la demande"
    );

    let body = serde_json::json!({
        "model": "claude-haiku-4-5-20251001",
        "max_tokens": 512,
        "messages": [{ "role": "user", "content": prompt }],
    });

    let resp = client
        .post("https://api.anthropic.com/v1/messages")
        .header("x-api-key", api_key)
        .header("anthropic-version", "2023-06-01")
        .header("content-type", "application/json")
        .json(&body)
        .send()
        .await
        .ok()?;

    if !resp.status().is_success() {
        return None;
    }

    let payload: serde_json::Value = resp.json().await.ok()?;
    let text = payload.get("content")?.as_array()?.iter().find_map(|b| {
        if b.get("type").and_then(serde_json::Value::as_str) == Some("text") {
            b.get("text").and_then(serde_json::Value::as_str)
        } else {
            None
        }
    })?;

    let json_str = extract_json_object(text)?;
    let parsed: serde_json::Value = serde_json::from_str(&json_str).ok()?;

    let q = parsed
        .get("q")
        .and_then(serde_json::Value::as_str)
        .map(str::to_string);

    // La spécialité (uuid) reste résolue en base à partir du `q` extrait par le LLM.
    let specialty = match &q {
        Some(term) => resolve_specialty(db, term).await.0,
        None => None,
    };

    let query = ParsedQuery {
        q,
        specialty,
        place: parsed
            .get("place")
            .and_then(serde_json::Value::as_str)
            .map(str::to_string),
        near: parsed
            .get("near")
            .and_then(serde_json::Value::as_str)
            .map(str::to_string),
        sector: parsed
            .get("sector")
            .and_then(serde_json::Value::as_str)
            .map(str::to_string),
        available: parsed
            .get("available")
            .and_then(serde_json::Value::as_str)
            .map(str::to_string),
        teleconsult: parsed
            .get("teleconsult")
            .and_then(serde_json::Value::as_bool),
    };

    let interpretation = parsed
        .get("interpretation")
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
        .unwrap_or_else(|| raw.to_string());

    Some((query, interpretation))
}

/// Extrait le premier objet JSON `{ … }` d'une chaîne (le modèle peut l'entourer
/// de texte malgré la consigne).
fn extract_json_object(text: &str) -> Option<String> {
    let start = text.find('{')?;
    let end = text.rfind('}')?;
    if end > start {
        Some(text[start..=end].to_string())
    } else {
        None
    }
}
