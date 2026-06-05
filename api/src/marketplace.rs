//! Référentiels marketplace : routes publiques (pas de JWT requis).

use axum::extract::State;
use axum::Json;
use serde::Serialize;
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
