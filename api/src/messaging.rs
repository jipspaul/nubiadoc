//! Handler pour la messagerie patient : GET /v1/conversations.

use axum::{
    extract::{Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

#[derive(Deserialize)]
pub struct ListConversationsQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

/// Un fil de messagerie patient ↔ cabinet.
#[derive(Serialize)]
pub struct ConversationItem {
    pub id: Uuid,
    pub cabinet_id: Uuid,
    pub cabinet_name: String,
    /// ISO 8601 UTC du dernier message, ou `null` si aucun message encore.
    pub last_message_at: Option<String>,
    /// Messages reçus (practitioner/secretary) non lus (`read_at IS NULL`).
    pub unread_count: i64,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

#[derive(Serialize)]
pub struct ConversationsResponse {
    pub data: Vec<ConversationItem>,
    pub page: PageInfo,
}

fn encode_cursor(last_message_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", last_message_at.timestamp_micros(), id)
}

fn decode_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/conversations` — liste paginée des fils de messagerie du patient connecté.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` :
/// - `conversation_patient_read` (migration 0029) : filtre les fils du patient.
/// - `cabinet_patient_read` (migration 0035) : autorise la lecture du nom du cabinet.
/// - `message_patient_read` (migration 0029) : filtre les messages des fils du patient.
///
/// Triée par `last_message_at DESC NULLS LAST, id DESC`.
pub async fn list_conversations(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(params): Query<ListConversationsQuery>,
) -> Result<Json<ConversationsResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let cursor = params.cursor.as_deref().and_then(decode_cursor);

    let cursor_clause = if cursor.is_some() {
        " WHERE (last_message_at < $2 OR (last_message_at = $2 AND id < $3) OR last_message_at IS NULL)"
    } else {
        ""
    };

    let sql = format!(
        "WITH conv AS ( \
             SELECT \
                 c.id, \
                 c.cabinet_id, \
                 cab.raison_sociale AS cabinet_name, \
                 (SELECT MAX(m.created_at) FROM message m WHERE m.conversation_id = c.id) \
                     AS last_message_at, \
                 (SELECT COUNT(*) FROM message m \
                  WHERE m.conversation_id = c.id \
                    AND m.sender_kind IN ('practitioner','secretary') \
                    AND m.read_at IS NULL) AS unread_count \
             FROM conversation c \
             JOIN cabinet cab ON cab.id = c.cabinet_id \
         ) \
         SELECT id, cabinet_id, cabinet_name, last_message_at, unread_count \
         FROM conv \
         {cursor_clause} \
         ORDER BY last_message_at DESC NULLS LAST, id DESC \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — policies 0029 + 0035 : conversation, message et cabinet lisibles.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let fetch_limit = limit + 1;

    let rows = match cursor {
        Some((cursor_ts, cursor_id)) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cursor_ts)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        None => sqlx::query(&sql)
            .bind(fetch_limit)
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

    let mut data: Vec<ConversationItem> = Vec::with_capacity(visible.len());
    let mut last_lma: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
        let cabinet_name: String = row
            .try_get("cabinet_name")
            .map_err(|_| AppError::Internal)?;
        let lma: Option<chrono::DateTime<chrono::Utc>> = row
            .try_get("last_message_at")
            .map_err(|_| AppError::Internal)?;
        let unread_count: i64 = row
            .try_get("unread_count")
            .map_err(|_| AppError::Internal)?;

        last_lma = lma;
        last_id = Some(id);

        data.push(ConversationItem {
            id,
            cabinet_id,
            cabinet_name,
            last_message_at: lma.map(|dt| dt.to_rfc3339()),
            unread_count,
        });
    }

    // Cursor only when the last visible row has a non-null last_message_at.
    let next_cursor = if has_more {
        last_lma.zip(last_id).map(|(dt, id)| encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        account_id = %claims.account_id,
        count = data.len(),
        has_more,
        "conversations listed"
    );

    Ok(Json(ConversationsResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}
