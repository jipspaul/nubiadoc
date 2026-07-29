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
    /// #3788 : la profession est le terme de recherche n°1 (« dentiste ») —
    /// `parse`/`search/providers` la reconnaissaient déjà, l'autocomplétion non.
    pub professions: Vec<SuggestItem>,
}

struct SuggestRow {
    id: Uuid,
    label: String,
}

/// `GET /v1/search/suggest` — autocomplete professions + spécialités + actes (docs/12 §12.1).
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
    // #4394 : Postgres text refuse l'octet NUL au bind — non filtré, il
    // faisait échouer les 3 requêtes ci-dessous en 500 (masqué Internal).
    crate::text_validation::reject_nul_byte(&params.q)?;
    // #3796 : repli d'accents (« detartrage » doit matcher « Détartrage »),
    // même schéma que search_ccam_acts (consultations.rs) et la recherche
    // pharmacie — normalisation Rust (minuscules) + translate() SQL des deux
    // côtés de la comparaison.
    let q = params.q.trim().to_lowercase();

    let specialty_rows = sqlx::query_as!(
        SuggestRow,
        "SELECT id, label FROM specialty \
         WHERE translate(lower(label), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                LIKE '%' || translate($1, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
         ORDER BY label LIMIT 5",
        q
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let act_rows = sqlx::query_as!(
        SuggestRow,
        "SELECT id, label FROM medical_act \
         WHERE translate(lower(label), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                LIKE '%' || translate($1, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
            OR EXISTS (SELECT 1 FROM unnest(motifs) AS m \
                       WHERE translate(lower(m), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                              LIKE '%' || translate($1, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%') \
         ORDER BY label LIMIT 5",
        q
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    // #4398 : cette branche liait params.q BRUT (ni trim ni translate),
    // contrairement à specialties/acts ci-dessus — un espace de tête ou un
    // accent faisait silencieusement disparaître la profession n°1 des
    // termes de recherche (marketplace.rs:118-120).
    let profession_rows = sqlx::query_as!(
        SuggestRow,
        "SELECT id, label FROM profession \
         WHERE translate(lower(label), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                LIKE '%' || translate($1, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
         ORDER BY label LIMIT 5",
        q
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
    let professions = profession_rows
        .into_iter()
        .map(|r| SuggestItem {
            id: r.id,
            label: r.label,
            score: 1.0,
        })
        .collect();

    Ok(Json(SuggestResponse {
        specialties,
        acts,
        professions,
    }))
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
    pub tiers_payant: Option<bool>,
    pub sort: Option<String>,
    pub page: Option<i64>,
    pub per_page: Option<i64>,
    /// `/search/slots` uniquement (#3885) : restreint à un praticien précis.
    /// `Option<String>` (pas `Option<Uuid>`) et validé manuellement dans le
    /// handler, comme `near`/`bbox` ci-dessus — un `Option<Uuid>` typé ferait
    /// échouer la désérialisation Query AVANT le handler, avec le rejet 400
    /// par défaut d'axum au lieu du `422 validation_error` attendu ici.
    pub provider_id: Option<String>,
    /// `/search/slots` uniquement (#3885) : restreint aux créneaux d'une
    /// journée précise, format `YYYY-MM-DD`.
    pub date: Option<String>,
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
    pub page: SearchPageInfo,
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

/// Lookup géo statique (#3753) : `place` (nom de ville) était parsé par
/// `/search/parse` et par les query params `search_providers`/`search_slots`,
/// mais totalement ignoré par le SQL — un vrai géocodage externe reste hors
/// scope MVP (docs/12), mais laisser `place` silencieusement sans effet
/// produisait des résultats nationaux pour une recherche nommant une ville
/// (« dentiste à Paris » renvoyait des praticiens de Lyon). Couvre les
/// grandes villes françaises (dont celles du jeu de seed) ; toute ville hors
/// liste reste ignorée — comportement historique inchangé pour ces cas-là.
const KNOWN_CITY_COORDS: &[(&str, f64, f64)] = &[
    ("paris", 48.8566, 2.3522),
    ("lyon", 45.7640, 4.8357),
    ("marseille", 43.2965, 5.3698),
    ("toulouse", 43.6047, 1.4442),
    ("nice", 43.7102, 7.2620),
    ("nantes", 47.2184, -1.5536),
    ("strasbourg", 48.5734, 7.7521),
    ("montpellier", 43.6108, 3.8767),
    ("bordeaux", 44.8378, -0.5792),
    ("lille", 50.6292, 3.0573),
    ("rennes", 48.1173, -1.6778),
];

/// Rayon (km) appliqué par défaut à un filtre géo (`near` ou `place` résolu)
/// quand aucun `radius_km` explicite n'est fourni par l'appelant. Sans lui,
/// `ST_DWithin` (search_providers) est court-circuité par `radius IS NULL`
/// → annuaire national renvoyé, filtre de proximité silencieusement ignoré
/// (#4387 : n'était appliqué qu'à `place`, pas à `near`).
const GEO_DEFAULT_RADIUS_KM: f64 = 20.0;

fn resolve_place_coords(place: &str) -> Option<(f64, f64)> {
    let needle = place.trim().to_lowercase();
    KNOWN_CITY_COORDS
        .iter()
        .find(|(name, _, _)| *name == needle)
        .map(|(_, lat, lng)| (*lat, *lng))
}

/// `(lat, lng, radius_km)` résolus par [`resolve_geo_filter`].
type GeoFilter = (Option<f64>, Option<f64>, Option<f64>);

/// Résout le filtre géo `near`/`place` en `(lat, lng, radius_km effectif)`.
/// `near` (coordonnées explicites) est toujours prioritaire sur `place` si les
/// deux sont fournis. `place` résolu via `KNOWN_CITY_COORDS` (#3753).
/// Rayon par défaut `GEO_DEFAULT_RADIUS_KM` appliqué aux DEUX branches quand
/// `radius_km` est omis (#4387 : `near` seul l'ignorait, annuaire national
/// renvoyé au lieu d'un rayon de proximité).
fn resolve_geo_filter(
    near: Option<&str>,
    place: Option<&str>,
    radius_km: Option<f64>,
) -> Result<GeoFilter, AppError> {
    if let Some(s) = near {
        let mut parts = s.splitn(2, ',');
        let lat = parts
            .next()
            .and_then(|v| v.trim().parse::<f64>().ok())
            .ok_or(AppError::ValidationError)?;
        let lng = parts
            .next()
            .and_then(|v| v.trim().parse::<f64>().ok())
            .ok_or(AppError::ValidationError)?;
        return Ok((
            Some(lat),
            Some(lng),
            Some(radius_km.unwrap_or(GEO_DEFAULT_RADIUS_KM)),
        ));
    }
    if let Some(p) = place {
        if let Some((lat, lng)) = resolve_place_coords(p) {
            return Ok((
                Some(lat),
                Some(lng),
                Some(radius_km.unwrap_or(GEO_DEFAULT_RADIUS_KM)),
            ));
        }
        tracing::warn!(place = %p, "place inconnu du lookup géo statique, filtre ignoré");
    }
    Ok((None, None, radius_km))
}

/// `GET /v1/search/slots` — prochains créneaux disponibles par praticien (docs/12 §12.1).
///
/// Route publique, pas de JWT. Mêmes filtres que `/v1/search/providers`, PLUS
/// `provider_id` (restreint à un praticien) et `date` (format `YYYY-MM-DD`,
/// restreint aux créneaux de ce jour) — #3885, valeur syntaxiquement invalide
/// → `422 validation_error`. `page`/`per_page`/`sort` désormais appliqués
/// (#3871) : pagination au grain PRATICIEN (pas au grain créneau — une page
/// de 20 praticiens peut contenir un nombre variable de créneaux chacun),
/// même sémantique `sort` que `/search/providers` (`distance`, `rating`,
/// `next_slot`, défaut chronologique).
/// Retourne uniquement les créneaux `status='open'` et `online_booking=true`
/// (RLS `slot_public_read`) ; au sein d'un praticien, les créneaux restent
/// triés par `starts_at` ascendant.
pub async fn search_slots(
    State(state): State<AppState>,
    Query(params): Query<SearchProvidersQuery>,
) -> Result<Json<SearchSlotsResponse>, AppError> {
    // #3796 : repli d'accents, même schéma que suggest_search.
    // #4394 : NUL byte non filtré → 500 au bind (même défaut que suggest_search).
    if let Some(q) = params.q.as_deref() {
        crate::text_validation::reject_nul_byte(q)?;
    }
    let q_norm = params.q.as_deref().map(|s| s.trim().to_lowercase());
    let (near_lat, near_lng, radius_km) = resolve_geo_filter(
        params.near.as_deref(),
        params.place.as_deref(),
        params.radius_km,
    )?;

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

    let radius_m: Option<f64> = radius_km.map(|r| r * 1000.0);

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

    // provider_id/date (#3885) : acceptés par la query string mais jusque-là
    // jamais appliqués au SQL (aucune colonne de filtre correspondante) —
    // silencieusement ignorés, 200 même sur une valeur syntaxiquement invalide.
    // Parsés manuellement (comme near/bbox ci-dessus) plutôt que typés
    // Option<Uuid>/Option<NaiveDate> sur la query struct : un champ typé
    // ferait échouer la désérialisation Query AVANT le handler, avec le rejet
    // 400 par défaut d'axum au lieu du 422 validation_error attendu ici.
    let provider_id_filter: Option<Uuid> = params
        .provider_id
        .as_deref()
        .map(Uuid::parse_str)
        .transpose()
        .map_err(|_| AppError::ValidationError)?;
    let date_filter: Option<chrono::NaiveDate> = params
        .date
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let page = params.page.unwrap_or(1).max(1);
    let per_page = params.per_page.unwrap_or(20).clamp(1, 100);
    let offset = (page - 1).saturating_mul(per_page);

    // Sort clause — mêmes clés que /search/providers, alias du SELECT ci-dessous
    // (functional dependency sur p.id, clé primaire de provider — autorise de
    // sélectionner p.display_name/p.geo sans les mettre dans GROUP BY).
    let sort_clause = match params.sort.as_deref() {
        Some("distance") if near_lat.is_some() => "distance_m ASC NULLS LAST, p.display_name ASC",
        Some("rating") => "rating_avg DESC NULLS LAST, p.display_name ASC",
        _ => "next_slot_at ASC NULLS LAST, p.display_name ASC",
    };

    // from_where_clause partagé entre le COUNT, la page de praticiens et la
    // requête de créneaux (#3871) : `page`/`per_page`/`sort` étaient acceptés
    // par la query string mais jamais appliqués — aucun LIMIT/OFFSET, tri
    // `sl.starts_at ASC` codé en dur — 2800 créneaux renvoyés d'un bloc quel
    // que soit `page`. Pagination au grain PRATICIEN (comme /search/providers) :
    // une page de résultats regroupe tous les créneaux des praticiens de cette
    // page, pas un simple LIMIT sur les lignes créneau (qui couperait un
    // praticien au milieu de sa liste de créneaux).
    //
    // $1=near_lat  $2=near_lng  $3=radius_m  $4=q  $5=specialty_id
    // $6=sector    $7=teleconsult  $8=pmr     $9=accepts_new  $10=languages
    // $11=bbox_min_lng  $12=bbox_min_lat  $13=bbox_max_lng  $14=bbox_max_lat
    // $15=tiers_payant  $16=provider_id  $17=date
    let from_where_clause = format!(
        "FROM availability_slot sl \
         JOIN provider p ON p.id = sl.provider_id \
         LEFT JOIN specialty s ON s.id = p.specialty_id \
         LEFT JOIN profession pr ON pr.id = s.profession_id \
         WHERE p.is_listed = true \
             AND sl.status = 'open' \
             AND sl.deleted_at IS NULL \
             AND sl.online_booking = true \
             AND sl.starts_at > now() \
             AND ($4::text IS NULL \
                  OR translate(lower(p.display_name), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                       LIKE '%' || translate($4, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
                  OR translate(lower(s.label), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                       LIKE '%' || translate($4, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
                  OR translate(lower(pr.label), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                       LIKE '%' || translate($4, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%') \
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
             AND ($15::boolean IS NULL OR p.tiers_payant = $15) \
             AND ($16::uuid IS NULL OR p.id = $16) \
             AND ($17::date IS NULL OR sl.starts_at::date = $17) \
             {available_clause}"
    );

    let count_sql = format!("SELECT COUNT(DISTINCT p.id) AS total_count {from_where_clause}");

    let providers_sql = format!(
        "SELECT p.id AS provider_id, p.display_name, \
             CASE WHEN $1::double precision IS NOT NULL AND $2::double precision IS NOT NULL \
                  THEN ST_Distance(p.geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography) \
                  ELSE NULL END AS distance_m, \
             MIN(sl.starts_at) AS next_slot_at, \
             (SELECT avg(rating)::double precision FROM review \
              WHERE provider_id = p.id AND status = 'published') AS rating_avg \
         {from_where_clause} \
         GROUP BY p.id \
         ORDER BY {sort_clause} \
         LIMIT $18 OFFSET $19"
    );

    let total: i64 = sqlx::query(&count_sql)
        .bind(near_lat) // $1
        .bind(near_lng) // $2
        .bind(radius_m) // $3
        .bind(q_norm.as_deref()) // $4
        .bind(params.specialty) // $5
        .bind(params.sector.as_deref()) // $6
        .bind(params.teleconsult) // $7
        .bind(params.pmr) // $8
        .bind(params.accepts_new) // $9
        .bind(lang_filter.clone()) // $10
        .bind(bbox_min_lng) // $11
        .bind(bbox_min_lat) // $12
        .bind(bbox_max_lng) // $13
        .bind(bbox_max_lat) // $14
        .bind(params.tiers_payant) // $15
        .bind(provider_id_filter) // $16
        .bind(date_filter) // $17
        .fetch_one(&state.db)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get("total_count")
        .map_err(|_| AppError::Internal)?;

    let provider_rows = sqlx::query(&providers_sql)
        .bind(near_lat) // $1
        .bind(near_lng) // $2
        .bind(radius_m) // $3
        .bind(q_norm.as_deref()) // $4
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
        .bind(params.tiers_payant) // $15
        .bind(provider_id_filter) // $16
        .bind(date_filter) // $17
        .bind(per_page) // $18
        .bind(offset) // $19
        .fetch_all(&state.db)
        .await
        .map_err(|_| AppError::Internal)?;

    let mut data: Vec<SlotProviderItem> = Vec::with_capacity(provider_rows.len());
    let mut provider_ids: Vec<Uuid> = Vec::with_capacity(provider_rows.len());
    for row in &provider_rows {
        let provider_id: Uuid = row.try_get("provider_id").map_err(|_| AppError::Internal)?;
        let next_slot_at: chrono::DateTime<chrono::Utc> = row
            .try_get("next_slot_at")
            .map_err(|_| AppError::Internal)?;
        provider_ids.push(provider_id);
        data.push(SlotProviderItem {
            provider_id,
            display_name: row
                .try_get("display_name")
                .map_err(|_| AppError::Internal)?,
            distance_m: row.try_get("distance_m").unwrap_or(None),
            first_slot_at: next_slot_at.to_rfc3339(),
            slots: Vec::new(),
        });
    }

    // Créneaux des praticiens de CETTE page uniquement — mêmes filtres au
    // grain créneau que from_where_clause (déjà appliqués côté praticien,
    // mais status/deleted_at/online_booking/starts_at/available_clause/date
    // restent nécessaires ici pour ne récupérer que les créneaux éligibles :
    // un provider peut passer le filtre `date` via un autre créneau que ceux
    // listés ici, donc `date` doit être réappliqué au grain créneau (#3885).
    if !provider_ids.is_empty() {
        let slots_sql = format!(
            "SELECT sl.id AS slot_id, sl.provider_id, sl.starts_at \
             FROM availability_slot sl \
             WHERE sl.provider_id = ANY($1) \
                 AND sl.status = 'open' \
                 AND sl.deleted_at IS NULL \
                 AND sl.online_booking = true \
                 AND sl.starts_at > now() \
                 AND ($2::date IS NULL OR sl.starts_at::date = $2) \
                 {available_clause} \
             ORDER BY sl.starts_at ASC"
        );
        let slot_rows = sqlx::query(&slots_sql)
            .bind(&provider_ids)
            .bind(date_filter)
            .fetch_all(&state.db)
            .await
            .map_err(|_| AppError::Internal)?;

        for row in &slot_rows {
            let provider_id: Uuid = row.try_get("provider_id").map_err(|_| AppError::Internal)?;
            let starts_at: chrono::DateTime<chrono::Utc> =
                row.try_get("starts_at").map_err(|_| AppError::Internal)?;
            if let Some(entry) = data.iter_mut().find(|e| e.provider_id == provider_id) {
                entry.slots.push(SlotRef {
                    slot_id: row.try_get("slot_id").map_err(|_| AppError::Internal)?,
                    starts_at: starts_at.to_rfc3339(),
                });
            }
        }
    }

    Ok(Json(SearchSlotsResponse {
        data,
        page: SearchPageInfo {
            page,
            per_page,
            total,
        },
    }))
}

/// `GET /v1/search/providers` — annuaire public de praticiens (docs/12 §12.1).
///
/// Route publique, pas de JWT. Seuls les providers `is_listed=true` sont exposés
/// (RLS `provider_public_read` + clause WHERE explicite). `place` résolu via
/// le lookup géo statique `KNOWN_CITY_COORDS` (#3753, vrai géocodage externe
/// hors scope MVP). Distance via PostGIS si `near` ou `place` fourni.
pub async fn search_providers(
    State(state): State<AppState>,
    Query(params): Query<SearchProvidersQuery>,
) -> Result<Json<SearchProvidersResponse>, AppError> {
    // #3796 : repli d'accents, même schéma que suggest_search/search_slots.
    // #4394 : NUL byte non filtré → 500 au bind.
    if let Some(q) = params.q.as_deref() {
        crate::text_validation::reject_nul_byte(q)?;
    }
    let q_norm = params.q.as_deref().map(|s| s.trim().to_lowercase());
    let (near_lat, near_lng, radius_km) = resolve_geo_filter(
        params.near.as_deref(),
        params.place.as_deref(),
        params.radius_km,
    )?;

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
    let offset = (page - 1).saturating_mul(per_page);
    let radius_m: Option<f64> = radius_km.map(|r| r * 1000.0);

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
        Some("rating") => "rating_avg DESC NULLS LAST, p.display_name ASC",
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
    // $15=tiers_payant  $16=per_page  $17=offset
    //
    // from_where_clause est partagé entre la requête paginée et le COUNT
    // dédié ci-dessous (#3840) : COUNT(*) OVER() portait le total par les
    // LIGNES PAGINÉES elles-mêmes — une page hors plage (OFFSET > nb de
    // résultats) renvoie 0 ligne, donc total retombait à 0 au lieu du vrai
    // total, indépendamment de la page demandée.
    let from_where_clause = format!(
        "FROM provider p \
         LEFT JOIN specialty s ON s.id = p.specialty_id \
         LEFT JOIN profession pr ON pr.id = s.profession_id \
         WHERE p.is_listed = true \
             AND ($4::text IS NULL \
                  OR translate(lower(p.display_name), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                       LIKE '%' || translate($4, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
                  OR translate(lower(s.label), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                       LIKE '%' || translate($4, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
                  OR translate(lower(pr.label), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                       LIKE '%' || translate($4, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%') \
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
             AND ($15::boolean IS NULL OR p.tiers_payant = $15) \
             {available_clause}"
    );

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
             (SELECT avg(rating)::double precision FROM review \
              WHERE provider_id = p.id AND status = 'published') AS rating_avg, \
             ST_Y(p.geo::geometry) AS geo_lat, \
             ST_X(p.geo::geometry) AS geo_lng, \
             p.is_listed \
         {from_where_clause} \
         ORDER BY {sort_clause} \
         LIMIT $16 OFFSET $17"
    );

    let count_sql = format!("SELECT COUNT(*) AS total_count {from_where_clause}");

    let total: i64 = sqlx::query(&count_sql)
        .bind(near_lat) // $1
        .bind(near_lng) // $2
        .bind(radius_m) // $3
        .bind(q_norm.as_deref()) // $4
        .bind(params.specialty) // $5
        .bind(params.sector.as_deref()) // $6
        .bind(params.teleconsult) // $7
        .bind(params.pmr) // $8
        .bind(params.accepts_new) // $9
        .bind(lang_filter.clone()) // $10
        .bind(bbox_min_lng) // $11
        .bind(bbox_min_lat) // $12
        .bind(bbox_max_lng) // $13
        .bind(bbox_max_lat) // $14
        .bind(params.tiers_payant) // $15
        .fetch_one(&state.db)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get("total_count")
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&sql)
        .bind(near_lat) // $1
        .bind(near_lng) // $2
        .bind(radius_m) // $3
        .bind(q_norm.as_deref()) // $4
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
        .bind(params.tiers_payant) // $15
        .bind(per_page) // $16
        .bind(offset) // $17
        .fetch_all(&state.db)
        .await
        .map_err(|_| AppError::Internal)?;

    let mut data: Vec<ProviderItem> = Vec::with_capacity(rows.len());

    for row in &rows {
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
             (SELECT avg(rating)::double precision FROM review \
              WHERE provider_id = p.id AND status = 'published') AS rating_avg, \
             (SELECT count(*) FROM review \
              WHERE provider_id = p.id AND status = 'published') AS rating_count \
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

    // count(*) renvoie bigint (i64), pas int — auparavant p.rating_count (int)
    // rendait i32 correct ; le sous-select ci-dessus exige i64.
    let review_count: i64 = row.try_get("rating_count").unwrap_or(0);

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
        review_count,
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

/// Construit une interprétation lisible en français. `place` n'est annoncé
/// « près de {place} » que s'il résout dans `KNOWN_CITY_COORDS` (#4484) —
/// sinon le filtre géo est silencieusement ignoré par search_providers/
/// search_slots, et promettre une proximité non appliquée serait trompeur.
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
        // #4484 : « près de {place} » promet un filtrage géographique que
        // search_providers/search_slots n'appliquent que pour les villes de
        // KNOWN_CITY_COORDS (géocodage externe hors scope MVP) — pour toute
        // autre ville, l'annuaire national était renvoyé sans que
        // l'interprétation ne le laisse deviner. Phrasé neutre (sans « près
        // de ») pour les villes non résolues : n'affirme pas une proximité
        // qui ne sera pas appliquée.
        if resolve_place_coords(place).is_some() {
            parts.push(format!("près de {place}"));
        } else {
            parts.push(format!("à {place}"));
        }
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
