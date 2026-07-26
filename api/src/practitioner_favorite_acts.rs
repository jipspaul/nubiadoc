//! Handlers `GET/POST /v1/cabinet/practitioners/me/favorite-acts` et
//! `DELETE /v1/cabinet/practitioners/me/favorite-acts/:ccam_code` (#4112,
//! table `practitioner_favorite_act`, migration 0181).
//!
//! Ownership fin (un praticien ne gère que SES favoris, pas ceux d'un
//! confrère du même cabinet) appliqué ici, pas par la RLS (tenant-only,
//! cf. doc de la migration 0181) — chaque requête résout `practitioner_id`
//! depuis le JWT (`user_id` + `cabinet_id`), jamais depuis le body/query.

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

/// Un acte CCAM favori (jointure avec le catalogue pour le libellé/tarif —
/// évite un aller-retour supplémentaire côté client).
#[derive(Serialize)]
pub struct FavoriteActItem {
    pub ccam_code: String,
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tarif_cents: Option<i32>,
    pub position: i32,
}

#[derive(Serialize)]
pub struct FavoriteActsResponse {
    pub data: Vec<FavoriteActItem>,
}

#[derive(Deserialize)]
pub struct CreateFavoriteActBody {
    pub ccam_code: String,
}

/// Résout l'id `practitioner` du JWT appelant. `404` si le compte n'est pas
/// (encore) un `practitioner` de ce cabinet.
///
/// #4364 : `practitioner` est en RLS `tenant_isolation` FORCE (migration
/// 0011) — exécuté sans `app.current_cabinet_id` posé au préalable sur LA
/// MÊME connexion/transaction, `current_setting` renvoie `''`, la ligne
/// n'est jamais visible → 404 systématique même pour un praticien valide.
/// Prend donc la transaction (où l'appelant a déjà posé le GUC), jamais le
/// pool brut — cf. `scheduling.rs::call_next_patient`, seul appelant qui
/// fonctionnait avant ce fix.
async fn resolve_practitioner_id(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    user_id: Uuid,
) -> Result<Uuid, AppError> {
    sqlx::query("SELECT id FROM practitioner WHERE user_id = $1 AND cabinet_id = $2")
        .bind(user_id)
        .bind(cabinet_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?
        .map(|r| r.try_get("id").map_err(|_| AppError::Internal))
        .transpose()?
        .ok_or(AppError::NotFound)
}

/// `GET /v1/cabinet/practitioners/me/favorite-acts` — favoris du praticien
/// appelant, triés par `position`.
pub async fn list_favorite_acts(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
) -> Result<Json<FavoriteActsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let practitioner_id = resolve_practitioner_id(&mut tx, claims.cabinet_id, claims.sub).await?;

    let rows = sqlx::query(
        "SELECT f.ccam_code, c.label, c.tarif_cents, f.position \
         FROM practitioner_favorite_act f \
         JOIN ccam_act c ON c.code = f.ccam_code \
         WHERE f.practitioner_id = $1 \
         ORDER BY f.position",
    )
    .bind(practitioner_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .into_iter()
        .map(|r| {
            Ok(FavoriteActItem {
                ccam_code: r.try_get("ccam_code").map_err(|_| AppError::Internal)?,
                label: r.try_get("label").map_err(|_| AppError::Internal)?,
                tarif_cents: r.try_get("tarif_cents").map_err(|_| AppError::Internal)?,
                position: r.try_get("position").map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(FavoriteActsResponse { data }))
}

/// `POST /v1/cabinet/practitioners/me/favorite-acts` — ajoute un favori.
/// `position` auto-assignée (dernière + 1) — non demandée par l'issue côté
/// body, la réorganisation manuelle pourra être ajoutée dans une issue
/// dédiée si besoin. `409` si déjà favori (`UNIQUE`, pré-vérifié).
/// `422` si `ccam_code` ne correspond à aucun acte du catalogue.
pub async fn create_favorite_act(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Json(body): Json<CreateFavoriteActBody>,
) -> Result<Json<FavoriteActItem>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let practitioner_id = resolve_practitioner_id(&mut tx, claims.cabinet_id, claims.sub).await?;

    let act =
        sqlx::query("SELECT label, tarif_cents FROM ccam_act WHERE code = $1 AND active = true")
            .bind(&body.ccam_code)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    let Some(act) = act else {
        return Err(AppError::ValidationError);
    };
    let label: String = act.try_get("label").map_err(|_| AppError::Internal)?;
    let tarif_cents: Option<i32> = act.try_get("tarif_cents").map_err(|_| AppError::Internal)?;

    let existing = sqlx::query(
        "SELECT 1 FROM practitioner_favorite_act WHERE practitioner_id = $1 AND ccam_code = $2",
    )
    .bind(practitioner_id)
    .bind(&body.ccam_code)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if existing.is_some() {
        return Err(AppError::FavoriteActAlreadyExists);
    }

    let position: i32 = sqlx::query(
        "SELECT COALESCE(MAX(position), 0) + 1 AS next_position \
         FROM practitioner_favorite_act WHERE practitioner_id = $1",
    )
    .bind(practitioner_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .try_get("next_position")
    .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO practitioner_favorite_act (practitioner_id, cabinet_id, ccam_code, position) \
         VALUES ($1, $2, $3, $4)",
    )
    .bind(practitioner_id)
    .bind(claims.cabinet_id)
    .bind(&body.ccam_code)
    .bind(position)
    .execute(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            AppError::FavoriteActAlreadyExists
        }
        _ => AppError::Internal,
    })?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        ccam_code = %body.ccam_code,
        "practitioner favorite act created"
    );

    Ok(Json(FavoriteActItem {
        ccam_code: body.ccam_code,
        label,
        tarif_cents,
        position,
    }))
}

/// `DELETE /v1/cabinet/practitioners/me/favorite-acts/:ccam_code` — retire
/// un favori. `404` si ce n'était pas un favori du praticien appelant.
pub async fn delete_favorite_act(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(ccam_code): Path<String>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let practitioner_id = resolve_practitioner_id(&mut tx, claims.cabinet_id, claims.sub).await?;

    let deleted = sqlx::query(
        "DELETE FROM practitioner_favorite_act \
         WHERE practitioner_id = $1 AND ccam_code = $2 \
         RETURNING id",
    )
    .bind(practitioner_id)
    .bind(&ccam_code)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if deleted.is_none() {
        return Err(AppError::NotFound);
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        ccam_code = %ccam_code,
        "practitioner favorite act deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}
