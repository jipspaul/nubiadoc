//! Handlers R11 — assignation docteur ↔ secrétariat.
//!
//! `GET /v1/cabinet/providers/:id/secretariats` — liste les assignations d'un praticien.
//! `PUT /v1/cabinet/providers/:id/secretariats` — met à jour `active` sur chaque entrée.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

/// Un item d'assignation tel que retourné par `GET /v1/cabinet/providers/:id/secretariats`.
#[derive(Serialize)]
pub struct ProviderSecretariatItem {
    pub secretariat_id: Uuid,
    pub active: bool,
}

/// Corps de la requête `PUT /v1/cabinet/providers/:id/secretariats`.
#[derive(Deserialize)]
pub struct PutProviderSecretatriatsBody {
    pub secretariat_id: Uuid,
    pub active: bool,
}

/// `GET /v1/cabinet/providers/:id/secretariats`
///
/// Retourne la liste des assignations `provider_secretariat` pour le praticien `:id`.
/// Seuls les rôles `practitioner` et `admin` peuvent appeler cet endpoint (403 sinon).
/// `cabinet_id` extrait du JWT — RLS scopé via `SET LOCAL`.
pub async fn get_provider_secretariats(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
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
        "SELECT secretariat_id, active \
         FROM provider_secretariat \
         WHERE provider_id = $1 \
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
            let active: bool = row.try_get("active").map_err(|_| AppError::Internal)?;
            Ok(ProviderSecretariatItem {
                secretariat_id,
                active,
            })
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
/// Met à jour le flag `active` pour une assignation docteur ↔ secrétariat.
/// Si l'assignation n'existe pas encore, elle est créée (upsert via `ON CONFLICT`).
/// Rôles autorisés : `practitioner`, `admin` (403 pour `secretary`).
/// `cabinet_id` extrait du JWT — RLS scopé via `SET LOCAL`.
pub async fn put_provider_secretariats(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(provider_id): Path<Uuid>,
    Json(body): Json<PutProviderSecretatriatsBody>,
) -> Result<Json<ProviderSecretariatItem>, AppError> {
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

    // Vérifie que le secrétariat appartient au cabinet courant (RLS + WHERE explicite).
    let sec_exists = sqlx::query("SELECT 1 FROM secretariat WHERE id = $1 AND cabinet_id = $2")
        .bind(body.secretariat_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if sec_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // Upsert : si l'entrée active existe → UPDATE active.
    // L'index unique est sur (provider_id, secretariat_id) WHERE active,
    // donc un INSERT sur une entrée désactivée ne viole pas la contrainte.
    // On utilise un UPDATE + INSERT conditionnel pour rester simple.
    let updated = sqlx::query(
        "UPDATE provider_secretariat \
         SET active = $1 \
         WHERE provider_id = $2 AND secretariat_id = $3 \
         RETURNING secretariat_id, active",
    )
    .bind(body.active)
    .bind(provider_id)
    .bind(body.secretariat_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let row = if let Some(r) = updated {
        r
    } else {
        // Pas d'entrée existante → INSERT.
        sqlx::query(
            "INSERT INTO provider_secretariat (provider_id, secretariat_id, active) \
             VALUES ($1, $2, $3) \
             RETURNING secretariat_id, active",
        )
        .bind(provider_id)
        .bind(body.secretariat_id)
        .bind(body.active)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let secretariat_id: Uuid = row
        .try_get("secretariat_id")
        .map_err(|_| AppError::Internal)?;
    let active: bool = row.try_get("active").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        provider_id = %provider_id,
        secretariat_id = %secretariat_id,
        active,
        "provider secretariat assignment updated"
    );

    Ok(Json(ProviderSecretariatItem {
        secretariat_id,
        active,
    }))
}
