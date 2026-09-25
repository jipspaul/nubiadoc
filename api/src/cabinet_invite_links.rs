//! `POST /v1/cabinet/invite-links` (#7148, DP-F25.b) — lien d'invitation
//! copiable par rôle : un admin génère une URL à usage multiple, expirable,
//! que `POST /v1/auth/register` (`invite_link_token`) résout pour créer un
//! nouveau compte pro rattaché au cabinet avec ce rôle — distinct de
//! l'invitation nominative par e-mail (`cabinet_secretariats.rs::provision_staff`,
//! `auth/register.rs::register_invited`).
//!
//! Stockage : `cabinet_invite_link` (migration 0299, #7149) — RLS ouverte
//! pour `nubia_app`, filtrage applicatif (`cabinet_id` ici pour l'admin,
//! `token` côté `register.rs::register_via_invite_link` pour l'invité
//! anonyme, pas encore authentifié).

use axum::{extract::State, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminClaims},
    AppState,
};

/// Rôles valides pour un lien d'invitation — même énumération que
/// `cabinet_membership.role` (CHECK, migration 0098) et celle du CHECK de
/// `cabinet_invite_link.role` (migration 0299).
const VALID_ROLES: &[&str] = &["practitioner", "secretary", "admin", "manager", "doctor"];

/// Durée de validité par défaut d'un lien, en jours, quand
/// `expires_in_days` n'est pas fourni.
const DEFAULT_EXPIRES_IN_DAYS: i64 = 30;
/// Nombre d'utilisations par défaut quand `max_uses` n'est pas fourni —
/// cohérent avec l'intention "URL à usage multiple" documentée en migration
/// 0299 (le défaut de la colonne, 1, est pensé pour un usage nominatif).
const DEFAULT_MAX_USES: i32 = 20;

/// Corps de `POST /v1/cabinet/invite-links`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateInviteLinkBody {
    /// `practitioner` | `secretary` | `admin` | `manager` | `doctor`.
    pub role: String,
    /// Nombre d'acceptations autorisées avant épuisement du lien (défaut
    /// [`DEFAULT_MAX_USES`]) — doit être strictement positif.
    pub max_uses: Option<i32>,
    /// Durée de validité en jours (défaut [`DEFAULT_EXPIRES_IN_DAYS`]) —
    /// doit être strictement positive.
    pub expires_in_days: Option<i64>,
}

/// Réponse de `POST /v1/cabinet/invite-links`.
#[derive(Serialize)]
pub struct InviteLinkResponse {
    pub id: Uuid,
    pub role: String,
    /// Jeton opaque, aussi consommable seul par
    /// `POST /v1/auth/register { invite_link_token }`.
    pub token: String,
    /// URL complète copiable (`APP_BASE_URL` + route front d'inscription).
    pub url: String,
    pub max_uses: i32,
    pub expires_at: String,
}

/// `POST /v1/cabinet/invite-links` — génère un lien d'invitation copiable
/// pour un rôle donné.
///
/// Rôle `admin` requis. `role` hors énumération, ou `max_uses`/
/// `expires_in_days` fournis mais `<= 0` → `422 validation_error`.
/// `cabinet_id` toujours extrait du JWT. Retourne
/// `201 { id, role, token, url, max_uses, expires_at }`.
pub async fn create_invite_link(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Json(body): Json<CreateInviteLinkBody>,
) -> Result<(StatusCode, Json<InviteLinkResponse>), AppError> {
    if !VALID_ROLES.contains(&body.role.as_str()) {
        return Err(AppError::ValidationError);
    }
    let max_uses = body.max_uses.unwrap_or(DEFAULT_MAX_USES);
    if max_uses <= 0 {
        return Err(AppError::ValidationError);
    }
    let expires_in_days = body.expires_in_days.unwrap_or(DEFAULT_EXPIRES_IN_DAYS);
    if expires_in_days <= 0 {
        return Err(AppError::ValidationError);
    }

    let token = Uuid::new_v4().to_string();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO cabinet_invite_link \
         (cabinet_id, role, token, expires_at, max_uses, created_by) \
         VALUES ($1, $2, $3, now() + ($4::bigint * interval '1 day'), $5, $6) \
         RETURNING id, expires_at",
    )
    .bind(claims.cabinet_id)
    .bind(&body.role)
    .bind(&token)
    .bind(expires_in_days)
    .bind(max_uses)
    .bind(claims.sub)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let expires_at: chrono::DateTime<chrono::Utc> =
        row.try_get("expires_at").map_err(|_| AppError::Internal)?;

    let app_base_url =
        std::env::var("APP_BASE_URL").unwrap_or_else(|_| "https://app.nubia.invalid".to_string());
    let url = format!("{app_base_url}/register?invite_link_token={token}");

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        actor_id = %claims.sub,
        invite_link_id = %id,
        role = %body.role,
        "cabinet invite link created"
    );

    Ok((
        StatusCode::CREATED,
        Json(InviteLinkResponse {
            id,
            role: body.role,
            token,
            url,
            max_uses,
            expires_at: expires_at.to_rfc3339(),
        }),
    ))
}
