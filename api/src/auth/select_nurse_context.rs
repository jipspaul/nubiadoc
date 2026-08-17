//! Handler `POST /v1/auth/select-nurse-context`.
//!
//! Clone de `select_pharmacy_context` (tenant pharmacie) pour le tenant infirmier :
//! un utilisateur `kind:"pro"` (login commun) échange son token contre un JWT scopé
//! sur le tenant `nurse` dont il est membre actif (`NurseContextClaims`, `kind:"nurse"`).

use axum::extract::{Json, State};
use axum::http::{header, HeaderMap, HeaderValue};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use crate::AppState;

use super::{AppError, NurseContextClaims, ProClaims};

/// Corps de la requête `POST /v1/auth/select-nurse-context`.
#[derive(Deserialize)]
pub struct SelectNurseContextBody {
    nurse_id: Uuid,
}

/// Contexte inclus dans la réponse.
#[derive(Serialize)]
pub struct SelectNurseContextContext {
    nurse_id: Uuid,
    role: String,
}

/// Réponse de `POST /v1/auth/select-nurse-context`.
#[derive(Serialize)]
pub struct SelectNurseContextResponse {
    access_token: String,
    token_type: String,
    expires_in: u64,
    context: SelectNurseContextContext,
}

/// `POST /v1/auth/select-nurse-context` — émet un JWT scopé sur le tenant infirmier.
///
/// Le porteur doit être authentifié via le login commun (`ProClaims`, `kind == "pro"`).
/// L'endpoint vérifie l'appartenance active via `user_nurse_memberships` (SECURITY
/// DEFINER, contourne la RLS nurse-scoped) puis émet un `NurseContextClaims`
/// (`kind = "nurse"`, `nurse_id`, `role`).
///
/// `404` si `nurse_id` n'existe pas (anti-énumération : indistinguable d'un tenant
/// non listé pour un non-membre). `403 no_membership` si non-membre actif.
pub async fn select_nurse_context(
    State(state): State<AppState>,
    claims: ProClaims,
    Json(body): Json<SelectNurseContextBody>,
) -> Result<(HeaderMap, Json<SelectNurseContextResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    let row =
        sqlx::query("SELECT nurse_id, role FROM user_nurse_memberships($1) WHERE nurse_id = $2")
            .bind(claims.sub)
            .bind(body.nurse_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        // 404 si le tenant n'existe pas (borné à l'annuaire public, anti-énumération),
        // 403 si l'utilisateur n'en est pas membre actif.
        let exists = sqlx::query("SELECT 1 FROM nurse WHERE id = $1 AND is_listed")
            .bind(body.nurse_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        tx.rollback().await.ok();
        return Err(if exists.is_none() {
            AppError::NotFound
        } else {
            AppError::NoActiveMembership
        });
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let nurse_id: Uuid = row.try_get("nurse_id").map_err(|_| AppError::Internal)?;
    let role: String = row.try_get("role").map_err(|_| AppError::Internal)?;

    const EXPIRES_IN: u64 = 900;
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + EXPIRES_IN;

    let access_token = encode(
        &Header::default(),
        &NurseContextClaims {
            sub: claims.sub,
            kind: "nurse".to_string(),
            nurse_id,
            role: role.clone(),
            exp,
        },
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|_| AppError::Internal)?;

    tracing::info!(user_id = %claims.sub, nurse_id = %nurse_id, "nurse context selected");

    // Secure (#3846) : ce cookie porte un JWT de session (OWASP ASVS 3.4.1).
    let cookie = format!(
        "nubia_jwt={}; HttpOnly; Secure; Path=/; SameSite=Strict",
        access_token
    );
    let mut headers = HeaderMap::new();
    headers.insert(
        header::SET_COOKIE,
        HeaderValue::from_str(&cookie).map_err(|_| AppError::Internal)?,
    );

    Ok((
        headers,
        Json(SelectNurseContextResponse {
            access_token,
            token_type: "Bearer".to_string(),
            expires_in: EXPIRES_IN,
            context: SelectNurseContextContext { nurse_id, role },
        }),
    ))
}
