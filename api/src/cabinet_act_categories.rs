//! `GET/PUT /v1/cabinet/settings/act-categories` (#7186) — réglage cabinet
//! des catégories d'actes CCAM activées (mode « full ortho » : masquer les
//! catégories non pratiquées par le cabinet, ex. chirurgie/implanto pour un
//! cabinet 100% orthodontie).
//!
//! Repose sur `ccam_act.category` + `cabinet_act_category_setting` (migration
//! 0283, #7187) : une ligne = un override explicite (activée/désactivée) ;
//! l'absence de ligne vaut catégorie active par défaut (doc de la migration).
//! `GET /v1/ccam/acts` (`ccam_acts.rs`) applique ce réglage pour filtrer le
//! catalogue exposé au praticien.

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use crate::{
    auth::{AppError, ProAdminOrManagerClaims},
    AppState,
};

/// Liste autorisée des catégories — doit rester synchronisée avec le CHECK
/// Postgres posé par la migration 0283 (`ccam_act_category_check` /
/// `cabinet_act_category_setting_category_check`).
pub(crate) const ACT_CATEGORIES: [&str; 12] = [
    "consultation",
    "soins_conservateurs",
    "endo",
    "paro",
    "prothese",
    "ortho",
    "chirurgie",
    "implanto",
    "imagerie",
    "atm",
    "esthetique",
    "appareillages",
];

#[derive(Serialize)]
pub struct ActCategorySetting {
    pub category: String,
    pub enabled: bool,
}

#[derive(Serialize)]
pub struct ActCategoriesResponse {
    pub data: Vec<ActCategorySetting>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActCategorySettingInput {
    pub category: String,
    pub enabled: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UpdateActCategoriesBody {
    pub categories: Vec<ActCategorySettingInput>,
}

/// Charge le réglage courant du cabinet (transaction où le GUC
/// `app.current_cabinet_id` est déjà posé) : chaque catégorie de
/// `ACT_CATEGORIES`, avec `enabled` = l'override si présent, sinon `true`
/// (défaut applicatif — cf. doc de la migration 0283).
async fn load_settings(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: uuid::Uuid,
) -> Result<Vec<ActCategorySetting>, AppError> {
    let rows = sqlx::query(
        "SELECT category, enabled FROM cabinet_act_category_setting WHERE cabinet_id = $1",
    )
    .bind(cabinet_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut overrides = std::collections::HashMap::with_capacity(rows.len());
    for row in rows {
        let category: String = row.try_get("category").map_err(|_| AppError::Internal)?;
        let enabled: bool = row.try_get("enabled").map_err(|_| AppError::Internal)?;
        overrides.insert(category, enabled);
    }

    Ok(ACT_CATEGORIES
        .into_iter()
        .map(|category| ActCategorySetting {
            enabled: overrides.get(category).copied().unwrap_or(true),
            category: category.to_string(),
        })
        .collect())
}

/// `GET /v1/cabinet/settings/act-categories` — réglage courant, une entrée
/// par catégorie connue (défaut `enabled: true` si jamais réglée).
pub async fn get_act_categories(
    State(state): State<AppState>,
    claims: ProAdminOrManagerClaims,
) -> Result<Json<ActCategoriesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let data = load_settings(&mut tx, claims.cabinet_id).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(ActCategoriesResponse { data }))
}

/// `PUT /v1/cabinet/settings/act-categories` — upsert des overrides soumis
/// (partiel : les catégories absentes du body gardent leur réglage actuel).
/// `400` si une `category` soumise n'appartient pas à `ACT_CATEGORIES`.
pub async fn update_act_categories(
    State(state): State<AppState>,
    claims: ProAdminOrManagerClaims,
    Json(body): Json<UpdateActCategoriesBody>,
) -> Result<Json<ActCategoriesResponse>, AppError> {
    for item in &body.categories {
        if !ACT_CATEGORIES.contains(&item.category.as_str()) {
            return Err(AppError::InvalidActCategory);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    for item in &body.categories {
        sqlx::query(
            "INSERT INTO cabinet_act_category_setting (cabinet_id, category, enabled) \
             VALUES ($1, $2, $3) \
             ON CONFLICT (cabinet_id, category) \
             DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now()",
        )
        .bind(claims.cabinet_id)
        .bind(&item.category)
        .bind(item.enabled)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    let data = load_settings(&mut tx, claims.cabinet_id).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        "cabinet act-categories setting updated"
    );

    Ok(Json(ActCategoriesResponse { data }))
}
