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

#[derive(Deserialize)]
pub struct ListActsQuery {
    pub specialty_id: Option<Uuid>,
}

/// `GET /v1/acts` — actes CCAM filtrables par spécialité (docs/12 §12.1).
///
/// Route publique, pas de JWT. Pas de RLS (table plateforme — migration 0009).
pub async fn list_acts(
    State(state): State<AppState>,
    Query(filter): Query<ListActsQuery>,
) -> Result<Json<ListActsResponse>, AppError> {
    let rows = sqlx::query_as!(
        ActItem,
        "SELECT id, specialty_id, label, COALESCE(motifs, '{}') AS \"motifs!\" \
         FROM medical_act \
         WHERE ($1::uuid IS NULL OR specialty_id = $1) \
         ORDER BY label",
        filter.specialty_id as Option<Uuid>
    )
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(Json(ListActsResponse { data: rows }))
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
