//! Handler `POST /v1/auth/select-pharmacy-context`.

use axum::extract::{Json, State};
use axum::http::{header, HeaderMap, HeaderValue};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use crate::AppState;

use super::{AppError, PharmaContextClaims, ProClaims};

/// Corps de la requête `POST /v1/auth/select-pharmacy-context`.
#[derive(Deserialize)]
pub struct SelectPharmacyContextBody {
    pharmacy_id: Uuid,
}

/// Contexte inclus dans la réponse de `POST /v1/auth/select-pharmacy-context`.
#[derive(Serialize)]
pub struct SelectPharmacyContextContext {
    pharmacy_id: Uuid,
    role: String,
}

/// Réponse de `POST /v1/auth/select-pharmacy-context`.
#[derive(Serialize)]
pub struct SelectPharmacyContextResponse {
    access_token: String,
    token_type: String,
    expires_in: u64,
    context: SelectPharmacyContextContext,
}

/// `POST /v1/auth/select-pharmacy-context` — émet un JWT scopé sur la pharmacie demandée.
///
/// Le porteur doit être authentifié via le login commun (`ProClaims`, `kind == "pro"`
/// après `POST /v1/auth/login`). L'endpoint vérifie que l'utilisateur est membre actif
/// de la `pharmacy_id` demandée via `user_pharmacy_memberships` (SECURITY DEFINER,
/// contourne la RLS pharmacy-scoped) puis émet un `PharmaContextClaims` portant
/// `kind = "pharma"`, `pharmacy_id` et `role`.
///
/// Retourne `404` si `pharmacy_id` n'existe pas (anti-énumération : indistinguable
/// d'une pharmacie non listée pour un non-membre).
/// Retourne `403 no_membership` si l'utilisateur n'est pas membre actif.
pub async fn select_pharmacy_context(
    State(state): State<AppState>,
    claims: ProClaims,
    Json(body): Json<SelectPharmacyContextBody>,
) -> Result<(HeaderMap, Json<SelectPharmacyContextResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT pharmacy_id, role FROM user_pharmacy_memberships($1) WHERE pharmacy_id = $2",
    )
    .bind(claims.sub)
    .bind(body.pharmacy_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        // 404 si la pharmacie n'existe pas, 403 si l'utilisateur n'en est pas membre.
        // La vérification d'existence passe par le GUC pharmacie (policy pharmacy_self) :
        // pour un non-membre, seule une pharmacie listée est distinguable — on borne
        // donc l'existence à l'annuaire public (anti-énumération).
        let exists = sqlx::query("SELECT 1 FROM pharmacy WHERE id = $1 AND is_listed")
            .bind(body.pharmacy_id)
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

    let pharmacy_id: Uuid = row.try_get("pharmacy_id").map_err(|_| AppError::Internal)?;
    let role: String = row.try_get("role").map_err(|_| AppError::Internal)?;

    const EXPIRES_IN: u64 = 900;
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + EXPIRES_IN;

    let access_token = encode(
        &Header::default(),
        &PharmaContextClaims {
            sub: claims.sub,
            kind: "pharma".to_string(),
            pharmacy_id,
            role: role.clone(),
            exp,
        },
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %claims.sub,
        pharmacy_id = %pharmacy_id,
        "pharmacy context selected"
    );

    // Secure (#3846) : ce cookie porte un JWT de session — sans Secure, un
    // downgrade http:// du domaine le transmettrait en clair (OWASP ASVS 3.4.1).
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
        Json(SelectPharmacyContextResponse {
            access_token,
            token_type: "Bearer".to_string(),
            expires_in: EXPIRES_IN,
            context: SelectPharmacyContextContext { pharmacy_id, role },
        }),
    ))
}
