//! Référentiels marketplace : routes publiques (pas de JWT requis).

use axum::extract::{Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
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
