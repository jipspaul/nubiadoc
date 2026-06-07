//! Handler `GET /v1/notifications` — centre de notifications in-app.

use axum::{
    extract::{Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, MeClaims},
    AppState,
};

/// Paramètres de requête pour `GET /v1/notifications`.
#[derive(Deserialize)]
pub struct ListNotificationsQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
    pub unread_only: Option<bool>,
}

/// Une notification in-app.
#[derive(Serialize)]
pub struct NotificationItem {
    pub id: Uuid,
    pub kind: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    pub is_read: bool,
    pub created_at: String,
}

/// Métadonnées de pagination.
#[derive(Serialize)]
pub struct NotificationsPage {
    pub next_cursor: Option<String>,
}

/// Réponse de `GET /v1/notifications`.
#[derive(Serialize)]
pub struct NotificationsResponse {
    pub data: Vec<NotificationItem>,
    pub page: NotificationsPage,
}

fn encode_cursor(created_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", created_at.timestamp_micros(), id)
}

fn decode_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/notifications` — liste paginée des notifications in-app du porteur du token.
///
/// RLS `notification_owner_select` (migration 0053) : filtre sur `app.current_user_id`.
/// Pagination cursor-based (`?cursor=`, `?limit=` défaut 20, max 100).
/// Filtre optionnel `?unread_only=true`.
/// `body` déchiffré côté serveur (core/crypto KMS) ; `null` tant que NUB-T3 n'est pas livré.
/// Pas de PII dans les logs.
pub async fn list_notifications(
    State(state): State<AppState>,
    claims: MeClaims,
    Query(params): Query<ListNotificationsQuery>,
) -> Result<Json<NotificationsResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let cursor = params.cursor.as_deref().and_then(decode_cursor);
    let unread_only = params.unread_only.unwrap_or(false);

    let unread_clause = if unread_only {
        " AND is_read = false"
    } else {
        ""
    };
    let cursor_clause = if cursor.is_some() {
        " AND (created_at < $3 OR (created_at = $3 AND id < $4))"
    } else {
        ""
    };

    let sql = format!(
        "SELECT id, kind, title, is_read, created_at \
         FROM notification \
         WHERE app_user_id = $2\
         {unread_clause}\
         {cursor_clause} \
         ORDER BY created_at DESC, id DESC \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // RLS notification_owner_select (migration 0053) : exige app.current_user_id.
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let fetch_limit = limit + 1;

    let rows = match cursor {
        Some((cursor_ts, cursor_id)) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(claims.sub)
            .bind(cursor_ts)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        None => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(claims.sub)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<NotificationItem> = Vec::with_capacity(visible.len());
    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let kind: String = row.try_get("kind").map_err(|_| AppError::Internal)?;
        let title: String = row.try_get("title").map_err(|_| AppError::Internal)?;
        let is_read: bool = row.try_get("is_read").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        // Déchiffrement KMS (core/crypto NUB-T3) — non implémenté → body null.
        let body: Option<String> = None;

        last_created_at = Some(created_at);
        last_id = Some(id);

        data.push(NotificationItem {
            id,
            kind,
            title,
            body,
            is_read,
            created_at: created_at.to_rfc3339(),
        });
    }

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(ts, id)| encode_cursor(ts, id))
    } else {
        None
    };

    tracing::info!(
        user_id = %claims.sub,
        count = data.len(),
        "notifications listed"
    );

    Ok(Json(NotificationsResponse {
        data,
        page: NotificationsPage { next_cursor },
    }))
}
