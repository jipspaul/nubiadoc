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
