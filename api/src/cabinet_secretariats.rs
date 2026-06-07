//! Handlers R12 — CRUD secrétariats + membres.
//!
//! `GET  /v1/cabinet/secretariats`                           → liste des secrétariats du cabinet
//! `POST /v1/cabinet/secretariats`                           → créer (admin)
//! `PATCH  /v1/cabinet/secretariats/:id`                     → renommer (admin)
//! `DELETE /v1/cabinet/secretariats/:id`                     → supprimer (admin)
//! `POST   /v1/cabinet/secretariats/:id/members`             → ajouter membre (admin)
//! `DELETE /v1/cabinet/secretariats/:id/members/:user_id`    → retirer membre (admin)

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminClaims, ProMemberClaims},
    AppState,
};

/// Un secrétariat tel que retourné par `GET /v1/cabinet/secretariats`.
#[derive(Serialize)]
pub struct SecretariatItem {
    pub id: Uuid,
    pub name: String,
    pub created_at: String,
}

/// Corps de `POST /v1/cabinet/secretariats`.
#[derive(Deserialize)]
pub struct CreateSecretariatBody {
    pub name: String,
}

/// Corps de `PATCH /v1/cabinet/secretariats/:id`.
#[derive(Deserialize)]
pub struct PatchSecretariatBody {
    pub name: Option<String>,
}

/// Un membre de secrétariat tel que retourné par `POST /v1/cabinet/secretariats/:id/members`.
#[derive(Serialize)]
pub struct SecretariatMemberItem {
    pub secretariat_id: Uuid,
    pub user_id: Uuid,
    pub role: String,
    pub created_at: String,
}

/// Corps de `POST /v1/cabinet/secretariats/:id/members`.
#[derive(Deserialize)]
pub struct AddSecretariatMemberBody {
    pub user_id: Uuid,
    pub role: String,
}

/// `GET /v1/cabinet/secretariats`
///
/// Liste les secrétariats du cabinet. Accessible à tous les membres pro du cabinet.
/// `cabinet_id` extrait du JWT — RLS scopé via `SET LOCAL`.
pub async fn list_secretariats(
    State(state): State<AppState>,
    claims: ProMemberClaims,
) -> Result<Json<Vec<SecretariatItem>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, name, created_at \
         FROM secretariat \
         WHERE cabinet_id = $1 \
         ORDER BY created_at ASC",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let items = rows
        .into_iter()
        .map(|row| {
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let name: String = row.try_get("name").map_err(|_| AppError::Internal)?;
            let created_at: chrono::DateTime<chrono::Utc> =
                row.try_get("created_at").map_err(|_| AppError::Internal)?;
            Ok(SecretariatItem {
                id,
                name,
                created_at: created_at.to_rfc3339(),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        count = items.len(),
        "secretariats listed"
    );

    Ok(Json(items))
}

/// `POST /v1/cabinet/secretariats`
///
/// Crée un nouveau secrétariat dans le cabinet. Rôle `admin` requis.
/// `cabinet_id` extrait du JWT — RLS scopé via `SET LOCAL`.
pub async fn create_secretariat(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Json(body): Json<CreateSecretariatBody>,
) -> Result<(StatusCode, Json<SecretariatItem>), AppError> {
    if body.name.trim().is_empty() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO secretariat (cabinet_id, name) \
         VALUES ($1, $2) \
         RETURNING id, name, created_at",
    )
    .bind(claims.cabinet_id)
    .bind(body.name.trim())
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let name: String = row.try_get("name").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        secretariat_id = %id,
        "secretariat created"
    );

    Ok((
        StatusCode::CREATED,
        Json(SecretariatItem {
            id,
            name,
            created_at: created_at.to_rfc3339(),
        }),
    ))
}

/// `PATCH /v1/cabinet/secretariats/:id`
///
/// Renomme un secrétariat. Rôle `admin` requis.
/// Secrétariat absent ou hors cabinet → `404`.
pub async fn patch_secretariat(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Path(secretariat_id): Path<Uuid>,
    Json(body): Json<PatchSecretariatBody>,
) -> Result<Json<SecretariatItem>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "UPDATE secretariat \
         SET name = COALESCE($1, name) \
         WHERE id = $2 AND cabinet_id = $3 \
         RETURNING id, name, created_at",
    )
    .bind(body.name.as_deref().map(str::trim))
    .bind(secretariat_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let name: String = row.try_get("name").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        secretariat_id = %id,
        "secretariat updated"
    );

    Ok(Json(SecretariatItem {
        id,
        name,
        created_at: created_at.to_rfc3339(),
    }))
}

/// `DELETE /v1/cabinet/secretariats/:id`
///
/// Supprime un secrétariat. Les membres (`secretariat_membership`) sont supprimés
/// en cascade (ON DELETE CASCADE). Rôle `admin` requis.
/// Secrétariat absent ou hors cabinet → `404`.
pub async fn delete_secretariat(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Path(secretariat_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let deleted = sqlx::query(
        "DELETE FROM secretariat \
         WHERE id = $1 AND cabinet_id = $2 \
         RETURNING id",
    )
    .bind(secretariat_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if deleted.is_none() {
        return Err(AppError::NotFound);
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        secretariat_id = %secretariat_id,
        "secretariat deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}

/// `POST /v1/cabinet/secretariats/:id/members`
///
/// Ajoute un utilisateur du cabinet comme membre d'un secrétariat. Rôle `admin` requis.
/// `role` doit être `secretary` ou `manager`.
/// Si l'utilisateur est déjà membre actif du secrétariat → `409`.
/// L'utilisateur doit être membre actif du cabinet → `404` sinon.
pub async fn add_secretariat_member(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Path(secretariat_id): Path<Uuid>,
    Json(body): Json<AddSecretariatMemberBody>,
) -> Result<(StatusCode, Json<SecretariatMemberItem>), AppError> {
    if !["secretary", "manager"].contains(&body.role.as_str()) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le secrétariat appartient au cabinet courant.
    let sec_exists = sqlx::query("SELECT 1 FROM secretariat WHERE id = $1 AND cabinet_id = $2")
        .bind(secretariat_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if sec_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // Vérifie que l'utilisateur est membre actif du cabinet.
    let member_exists = sqlx::query(
        "SELECT 1 FROM cabinet_membership \
         WHERE cabinet_id = $1 AND user_id = $2 AND active = true",
    )
    .bind(claims.cabinet_id)
    .bind(body.user_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if member_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let row = sqlx::query(
        "INSERT INTO secretariat_membership \
         (cabinet_id, secretariat_id, user_id, role, active) \
         VALUES ($1, $2, $3, $4, true) \
         RETURNING secretariat_id, user_id, role, created_at",
    )
    .bind(claims.cabinet_id)
    .bind(secretariat_id)
    .bind(body.user_id)
    .bind(&body.role)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| {
        if is_unique_violation(&e) {
            AppError::Conflict
        } else {
            AppError::Internal
        }
    })?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let sec_id: Uuid = row
        .try_get("secretariat_id")
        .map_err(|_| AppError::Internal)?;
    let user_id: Uuid = row.try_get("user_id").map_err(|_| AppError::Internal)?;
    let role: String = row.try_get("role").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        secretariat_id = %sec_id,
        user_id = %user_id,
        role = %role,
        "secretariat member added"
    );

    Ok((
        StatusCode::CREATED,
        Json(SecretariatMemberItem {
            secretariat_id: sec_id,
            user_id,
            role,
            created_at: created_at.to_rfc3339(),
        }),
    ))
}

/// `DELETE /v1/cabinet/secretariats/:id/members/:user_id`
///
/// Retire un utilisateur d'un secrétariat (soft-delete : `active = false`).
/// Rôle `admin` requis.
/// Membre absent ou déjà inactif → `404`.
pub async fn remove_secretariat_member(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Path((secretariat_id, target_user_id)): Path<(Uuid, Uuid)>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le secrétariat appartient au cabinet courant.
    let sec_exists = sqlx::query("SELECT 1 FROM secretariat WHERE id = $1 AND cabinet_id = $2")
        .bind(secretariat_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if sec_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let updated = sqlx::query(
        "UPDATE secretariat_membership \
         SET active = false \
         WHERE secretariat_id = $1 AND user_id = $2 AND cabinet_id = $3 AND active = true \
         RETURNING id",
    )
    .bind(secretariat_id)
    .bind(target_user_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if updated.is_none() {
        return Err(AppError::NotFound);
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        secretariat_id = %secretariat_id,
        user_id = %target_user_id,
        "secretariat member removed"
    );

    Ok(StatusCode::NO_CONTENT)
}

fn is_unique_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23505")
    )
}
