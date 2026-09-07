//! Profil infirmier + heartbeat de disponibilité : `GET /v1/nurse/profile`,
//! `PATCH /v1/nurse/availability`.
//!
//! Quand/Pourquoi : l'infirmière bascule « en ligne » et pousse sa position pour
//! être éligible au matching de proximité (cf. `nurse.is_online`/`geo`, migration
//! 0233). Le GUC `app.current_nurse_id` (posé depuis `NurseMemberClaims`) borne
//! la RLS `nurse_self` : l'infirmière ne lit/écrit que sa propre ligne.
//! Modes d'échec : token non-`kind:"nurse"` → 403 (extracteur) ; lat/lng fournis
//! l'un sans l'autre → 422.

use axum::extract::{Json, State};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use crate::auth::{AppError, NurseMemberClaims, ProClaims};
use crate::AppState;

/// Un tenant infirmier dont l'utilisateur est membre (pour select-nurse-context).
#[derive(serde::Serialize)]
pub struct NurseMembershipItem {
    pub nurse_id: uuid::Uuid,
    pub role: String,
}

/// `GET /v1/nurse/memberships` — tenants infirmiers de l'utilisateur (token
/// `kind:pro` de login). Résout le chicken-and-egg : l'app appelle ça juste
/// après login pour connaître le `nurse_id` à passer à select-nurse-context.
/// SECURITY DEFINER `user_nurse_memberships` → pas de GUC nurse requis.
pub async fn list_nurse_memberships(
    State(state): State<AppState>,
    claims: ProClaims,
) -> Result<Json<Vec<NurseMembershipItem>>, AppError> {
    let rows = sqlx::query("SELECT nurse_id, role FROM user_nurse_memberships($1)")
        .bind(claims.sub)
        .fetch_all(&state.db)
        .await
        .map_err(|_| AppError::Internal)?;
    let mut out = Vec::with_capacity(rows.len());
    for row in rows {
        out.push(NurseMembershipItem {
            nurse_id: row.try_get("nurse_id").map_err(|_| AppError::Internal)?,
            role: row.try_get("role").map_err(|_| AppError::Internal)?,
        });
    }
    Ok(Json(out))
}

/// Profil public de l'infirmière (annuaire + état de disponibilité).
#[derive(Serialize)]
pub struct NurseProfileResponse {
    pub id: uuid::Uuid,
    pub display_name: String,
    pub adeli: Option<String>,
    pub address: serde_json::Value,
    pub phone: Option<String>,
    pub service_radius_m: i32,
    pub is_listed: bool,
    pub is_online: bool,
}

/// Pose le GUC tenant infirmier sur la transaction/connexion courante.
async fn set_nurse_guc(
    conn: &mut sqlx::PgConnection,
    nurse_id: uuid::Uuid,
) -> Result<(), AppError> {
    sqlx::query("SELECT set_config('app.current_nurse_id', $1, true)")
        .bind(nurse_id.to_string())
        .execute(&mut *conn)
        .await
        .map_err(|_| AppError::Internal)?;
    Ok(())
}

fn map_profile(row: &sqlx::postgres::PgRow) -> Result<NurseProfileResponse, AppError> {
    Ok(NurseProfileResponse {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        display_name: row
            .try_get("display_name")
            .map_err(|_| AppError::Internal)?,
        adeli: row.try_get("adeli").map_err(|_| AppError::Internal)?,
        address: row.try_get("address").map_err(|_| AppError::Internal)?,
        phone: row.try_get("phone").map_err(|_| AppError::Internal)?,
        service_radius_m: row
            .try_get("service_radius_m")
            .map_err(|_| AppError::Internal)?,
        is_listed: row.try_get("is_listed").map_err(|_| AppError::Internal)?,
        is_online: row.try_get("is_online").map_err(|_| AppError::Internal)?,
    })
}

/// `GET /v1/nurse/profile` — profil de l'infirmière du contexte courant.
pub async fn get_nurse_profile(
    State(state): State<AppState>,
    claims: NurseMemberClaims,
) -> Result<Json<NurseProfileResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_nurse_guc(&mut tx, claims.nurse_id).await?;

    let row = sqlx::query(
        "SELECT id, display_name, adeli, address, phone, service_radius_m, is_listed, is_online \
         FROM nurse WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(claims.nurse_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::NotFound)?;
    Ok(Json(map_profile(&row)?))
}

/// Corps de `PATCH /v1/nurse/availability`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AvailabilityBody {
    /// Bascule en ligne / hors ligne (reçoit ou non des offres).
    pub is_online: Option<bool>,
    /// Position courante (heartbeat) — les deux ensemble ou aucun.
    pub lat: Option<f64>,
    pub lng: Option<f64>,
}

/// `PATCH /v1/nurse/availability` — bascule en ligne + pousse la position.
///
/// Met à jour `is_online` (si fourni) et, si `lat`+`lng` fournis, `geo` +
/// `last_seen_geo` + `last_seen_at`. Champs absents = inchangés (COALESCE).
/// `422` si `lat`/`lng` fournis l'un sans l'autre.
pub async fn patch_nurse_availability(
    State(state): State<AppState>,
    claims: NurseMemberClaims,
    Json(body): Json<AvailabilityBody>,
) -> Result<Json<NurseProfileResponse>, AppError> {
    if body.lat.is_some() != body.lng.is_some() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    set_nurse_guc(&mut tx, claims.nurse_id).await?;

    // ST_MakePoint(NULL,NULL) → NULL → COALESCE conserve l'existant : un heartbeat
    // sans position ne l'efface pas. $1=is_online $2=lat $3=lng $4=id.
    let row = sqlx::query(
        "UPDATE nurse SET \
             is_online     = COALESCE($1, is_online), \
             geo           = COALESCE(ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography, geo), \
             last_seen_geo = COALESCE(ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography, last_seen_geo), \
             last_seen_at  = CASE WHEN $2::float8 IS NOT NULL THEN now() ELSE last_seen_at END, \
             updated_at    = now() \
         WHERE id = $4 AND deleted_at IS NULL \
         RETURNING id, display_name, adeli, address, phone, service_radius_m, is_listed, is_online",
    )
    .bind(body.is_online) // $1
    .bind(body.lat) // $2
    .bind(body.lng) // $3
    .bind(claims.nurse_id) // $4
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::NotFound)?;
    Ok(Json(map_profile(&row)?))
}
