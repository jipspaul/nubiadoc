//! Handlers R11 — assignation docteur ↔ secrétariat.
//!
//! `GET /v1/cabinet/providers/:id/secretariats` — liste les secrétariats actifs d'un praticien.
//! `PUT /v1/cabinet/providers/:id/secretariats` — remplace l'intégralité des assignations actives.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminOrManagerClaims},
    AppState,
};

/// Un item d'assignation tel que retourné par `GET /v1/cabinet/providers/:id/secretariats`.
#[derive(Serialize)]
pub struct ProviderSecretariatItem {
    pub secretariat_id: Uuid,
}

/// Corps de la requête `PUT /v1/cabinet/providers/:id/secretariats`.
#[derive(Deserialize)]
pub struct PutProviderSecretatriatsBody {
    pub secretariat_ids: Vec<Uuid>,
}

/// `GET /v1/cabinet/providers/:id/secretariats`
///
/// Retourne la liste des secrétariats actifs où le praticien `:id` est assigné.
/// Rôles autorisés : `admin`, `manager` (403 pour `secretary` et `practitioner`).
/// `cabinet_id` extrait du JWT — RLS scopé via `SET LOCAL`.
pub async fn get_provider_secretariats(
    State(state): State<AppState>,
    claims: ProAdminOrManagerClaims,
    Path(provider_id): Path<Uuid>,
) -> Result<Json<Vec<ProviderSecretariatItem>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le provider appartient bien au cabinet courant (RLS + WHERE explicite).
    let exists = sqlx::query("SELECT 1 FROM provider WHERE id = $1 AND cabinet_id = $2")
        .bind(provider_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if exists.is_none() {
        return Err(AppError::NotFound);
    }

    let rows = sqlx::query(
        "SELECT secretariat_id \
         FROM provider_secretariat \
         WHERE provider_id = $1 AND active = true \
         ORDER BY created_at ASC",
    )
    .bind(provider_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let items = rows
        .into_iter()
        .map(|row| {
            let secretariat_id: Uuid = row
                .try_get("secretariat_id")
                .map_err(|_| AppError::Internal)?;
            Ok(ProviderSecretariatItem { secretariat_id })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        provider_id = %provider_id,
        count = items.len(),
        "provider secretariats listed"
    );

    Ok(Json(items))
}

/// `PUT /v1/cabinet/providers/:id/secretariats`
///
/// Remplace l'intégralité des assignations actives du praticien par la liste fournie.
/// Les assignations existantes sont désactivées (`active = false`) puis les nouvelles
/// sont insérées. Chaque `secretariat_id` doit appartenir au cabinet courant.
/// Rôles autorisés : `admin`, `manager` (403 pour `secretary` et `practitioner`).
pub async fn put_provider_secretariats(
    State(state): State<AppState>,
    claims: ProAdminOrManagerClaims,
    Path(provider_id): Path<Uuid>,
    Json(body): Json<PutProviderSecretatriatsBody>,
) -> Result<Json<Vec<ProviderSecretariatItem>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le provider appartient bien au cabinet courant.
    let exists = sqlx::query("SELECT 1 FROM provider WHERE id = $1 AND cabinet_id = $2")
        .bind(provider_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if exists.is_none() {
        return Err(AppError::NotFound);
    }

    // Désactive toutes les assignations actives existantes (remplacement complet).
    sqlx::query(
        "UPDATE provider_secretariat SET active = false \
         WHERE provider_id = $1 AND active = true",
    )
    .bind(provider_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Insère les nouvelles assignations en validant l'appartenance au cabinet.
    for sec_id in &body.secretariat_ids {
        let sec_exists =
            sqlx::query("SELECT 1 FROM secretariat WHERE id = $1 AND cabinet_id = $2")
                .bind(sec_id)
                .bind(claims.cabinet_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;

        if sec_exists.is_none() {
            return Err(AppError::NotFound);
        }

        sqlx::query(
            "INSERT INTO provider_secretariat (provider_id, secretariat_id, active) \
             VALUES ($1, $2, true)",
        )
        .bind(provider_id)
        .bind(sec_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let items = body
        .secretariat_ids
        .into_iter()
        .map(|secretariat_id| ProviderSecretariatItem { secretariat_id })
        .collect();

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        provider_id = %provider_id,
        "provider secretariat assignments replaced"
    );

    Ok(Json(items))
}
