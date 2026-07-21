//! Handler `POST /v1/support/conversations` (#4169, "Support comme produit"
//! §4.2) — ouvre le fil de support cabinet ↔ Nubia.
//!
//! Réutilise `conversation`/`message` (scope `platform_support`, débloqué par
//! #4168) plutôt qu'un système de ticketing parallèle : une fois créé, ce fil
//! est lu/répondu via les endpoints `POST/GET /v1/cabinet/conversations/:id/
//! messages` déjà existants (`cabinet_messaging.rs`) — ils ne font aucun cas
//! spécial de `scope != 'clinical'`, donc `platform_support` y transite déjà
//! sans changement.

use axum::http::StatusCode;
use axum::{extract::State, Json};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminClaims},
    AppState,
};

/// Réponse de `POST /v1/support/conversations`.
#[derive(Serialize)]
pub struct SupportConversationResponse {
    pub conversation_id: Uuid,
    pub created_at: String,
}

/// `POST /v1/support/conversations` — ouvre (ou ré-ouvre) le fil de support
/// du cabinet appelant.
///
/// Rôle `admin` uniquement (`ProAdminClaims`) — tout autre rôle pro → `403`,
/// token patient/pharma → `403`, pas de token → `401`.
/// `cabinet_id` extrait du JWT, jamais du body (invariant tenancy).
/// Idempotent : un cabinet n'a qu'UN SEUL fil de support
/// (`conversation_uniq_platform_support_cabinet`, migration 0170) — un appel
/// répété renvoie toujours `201` avec le même `conversation_id` (même
/// convention que `messaging::create_conversation`, qui ne distingue pas non
/// plus 200/201 sur le chemin idempotent).
pub async fn open_support_conversation(
    State(state): State<AppState>,
    claims: ProAdminClaims,
) -> Result<(StatusCode, Json<SupportConversationResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO conversation (cabinet_id, scope, patient_id) \
         VALUES ($1, 'platform_support', NULL) \
         ON CONFLICT (cabinet_id) WHERE scope = 'platform_support' \
         DO UPDATE SET scope = EXCLUDED.scope \
         RETURNING id, created_at",
    )
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let conversation_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        conversation_id = %conversation_id,
        "support conversation opened"
    );

    Ok((
        StatusCode::CREATED,
        Json(SupportConversationResponse {
            conversation_id,
            created_at: created_at.to_rfc3339(),
        }),
    ))
}
