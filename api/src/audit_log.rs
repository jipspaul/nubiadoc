//! Handler `GET /v1/cabinet/audit-log` (#4155), lecture du journal d'accès
//! (`audit_log`, migration 0008 ; lecture ajoutée en migration 0195, #4155).
//!
//! `ProAdminOrManagerClaims` : réponse aux demandes de contrôle CNIL/patient
//! ("qui a consulté mon dossier ?") — réservé aux rôles admin/manager,
//! secretary/practitioner → 403.

use axum::{
    extract::{Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminOrManagerClaims},
    AppState,
};

/// Query de `GET /v1/cabinet/audit-log`. `from`/`to` en `YYYY-MM-DD`
/// (bornes inclusives, jour entier). `limit` (défaut 200, max 500) et
/// `offset` bornent le résultat (même convention que `cabinet_quotes.rs`).
#[derive(Deserialize)]
pub struct AuditLogQuery {
    pub from: Option<String>,
    pub to: Option<String>,
    pub entity: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Une entrée du journal d'accès.
#[derive(Serialize)]
pub struct AuditLogEntry {
    pub id: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actor_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actor_role: Option<String>,
    pub action: String,
    pub entity: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entity_id: Option<Uuid>,
    pub metadata: serde_json::Value,
    pub occurred_at: String,
}

/// Réponse de `GET /v1/cabinet/audit-log`.
#[derive(Serialize)]
pub struct AuditLogResponse {
    pub data: Vec<AuditLogEntry>,
}

/// `GET /v1/cabinet/audit-log` — journal d'accès du cabinet, filtrable par
/// date/entité, du plus récent au plus ancien.
///
/// `from`/`to` invalides (hors `YYYY-MM-DD`) → 422. Bornes sur `occurred_at`
/// en `timestamptz` (pas de cast `::date` sur la colonne de partitionnement,
/// pour ne pas défaire l'élagage de partitions).
pub async fn get_cabinet_audit_log(
    State(state): State<AppState>,
    claims: ProAdminOrManagerClaims,
    Query(params): Query<AuditLogQuery>,
) -> Result<Json<AuditLogResponse>, AppError> {
    let from = params
        .from
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?
        .and_then(|d| d.and_hms_opt(0, 0, 0))
        .map(|dt| chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(dt, chrono::Utc));
    let to = params
        .to
        .as_deref()
        .map(|s| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?
        .and_then(|d| d.and_hms_opt(23, 59, 59))
        .map(|dt| chrono::DateTime::<chrono::Utc>::from_naive_utc_and_offset(dt, chrono::Utc));

    let limit: i64 = params.limit.unwrap_or(200).clamp(1, 500);
    let offset: i64 = params.offset.unwrap_or(0).max(0);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, actor_id, actor_role, action, entity, entity_id, metadata, occurred_at \
         FROM audit_log \
         WHERE cabinet_id = $1 \
           AND ($2::timestamptz IS NULL OR occurred_at >= $2) \
           AND ($3::timestamptz IS NULL OR occurred_at <= $3) \
           AND ($4::text IS NULL OR entity = $4) \
         ORDER BY occurred_at DESC \
         LIMIT $5 OFFSET $6",
    )
    .bind(claims.cabinet_id)
    .bind(from)
    .bind(to)
    .bind(&params.entity)
    .bind(limit)
    .bind(offset)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in &rows {
        let occurred_at: chrono::DateTime<chrono::Utc> =
            row.try_get("occurred_at").map_err(|_| AppError::Internal)?;
        data.push(AuditLogEntry {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            actor_id: row.try_get("actor_id").map_err(|_| AppError::Internal)?,
            actor_role: row.try_get("actor_role").map_err(|_| AppError::Internal)?,
            action: row.try_get("action").map_err(|_| AppError::Internal)?,
            entity: row.try_get("entity").map_err(|_| AppError::Internal)?,
            entity_id: row.try_get("entity_id").map_err(|_| AppError::Internal)?,
            metadata: row.try_get("metadata").map_err(|_| AppError::Internal)?,
            occurred_at: occurred_at.to_rfc3339(),
        });
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        count = data.len(),
        "audit log consulted"
    );

    Ok(Json(AuditLogResponse { data }))
}
