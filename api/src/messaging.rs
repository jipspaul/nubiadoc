//! Handlers pour la messagerie patient :
//! GET /v1/conversations, POST /v1/conversations,
//! GET /v1/conversations/:id/messages.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::IntoResponse,
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

/// Paramètres de `GET /v1/conversations/:id/messages`.
#[derive(Deserialize)]
pub struct ListMessagesQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

/// Un message dans un fil de messagerie.
#[derive(Serialize)]
pub struct MessageItem {
    pub id: Uuid,
    /// Contenu chiffré (base64 de `body_ciphertext`). Déchiffrement côté client via `body_key_ref`.
    pub body: String,
    pub body_key_ref: String,
    pub sender_kind: String,
    pub created_at: String,
    pub read_at: Option<String>,
}

#[derive(Serialize)]
pub struct MessagesResponse {
    pub data: Vec<MessageItem>,
    pub page: PageInfo,
}

/// `GET /v1/conversations/:id/messages` — liste paginée des messages d'un fil.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` :
/// - `message_patient_read` (migration 0029) : filtre les messages des fils du patient.
/// - `conversation_patient_read` (migration 0029) : vérif que le fil appartient au patient.
///
/// Trié par `created_at DESC, id DESC`. Conversation hors tenant → 404.
/// Audit `read_message` (zéro PII) — `cabinet_id` extrait de la conversation.
pub async fn get_conversation_messages(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(conversation_id): Path<Uuid>,
    Query(params): Query<ListMessagesQuery>,
) -> Result<Json<MessagesResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let cursor = params.cursor.as_deref().and_then(decode_cursor);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope RLS patient — policies message_patient_read + conversation_patient_read.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que la conversation est accessible (RLS filtre si hors tenant → None = 404).
    let conv_row = sqlx::query("SELECT cabinet_id FROM conversation WHERE id = $1")
        .bind(conversation_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let conv_row = conv_row.ok_or(AppError::NotFound)?;
    let cabinet_id: Uuid = conv_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;

    let cursor_clause = if cursor.is_some() {
        " AND (created_at < $3 OR (created_at = $3 AND id < $4))"
    } else {
        ""
    };

    let sql = format!(
        "SELECT id, encode(body_ciphertext, 'base64') AS body, body_key_ref, \
                sender_kind, created_at, read_at \
         FROM message \
         WHERE conversation_id = $1 \
         {cursor_clause} \
         ORDER BY created_at DESC, id DESC \
         LIMIT $2"
    );

    let fetch_limit = limit + 1;

    let rows = match cursor {
        Some((cursor_ts, cursor_id)) => sqlx::query(&sql)
            .bind(conversation_id)
            .bind(fetch_limit)
            .bind(cursor_ts)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        None => sqlx::query(&sql)
            .bind(conversation_id)
            .bind(fetch_limit)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
    };

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<MessageItem> = Vec::with_capacity(visible.len());
    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let body: String = row.try_get("body").map_err(|_| AppError::Internal)?;
        let body_key_ref: String = row
            .try_get("body_key_ref")
            .map_err(|_| AppError::Internal)?;
        let sender_kind: String = row.try_get("sender_kind").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        let read_at: Option<chrono::DateTime<chrono::Utc>> =
            row.try_get("read_at").map_err(|_| AppError::Internal)?;

        last_created_at = Some(created_at);
        last_id = Some(id);

        data.push(MessageItem {
            id,
            body,
            body_key_ref,
            sender_kind,
            created_at: created_at.to_rfc3339(),
            read_at: read_at.map(|dt| dt.to_rfc3339()),
        });
    }

    // Audit read_message — app.current_cabinet_id requis par la policy RLS WITH CHECK.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'read_message', 'conversation', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(conversation_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        account_id = %claims.account_id,
        conversation_id = %conversation_id,
        count = data.len(),
        has_more,
        "messages listed"
    );

    Ok(Json(MessagesResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}

/// Corps de la requête `POST /v1/conversations/:id/messages`.
#[derive(Deserialize)]
pub struct SendMessageBody {
    pub body: String,
}

/// Réponse de `POST /v1/conversations/:id/messages`.
#[derive(Serialize)]
pub struct SendMessageResponse {
    pub message_id: Uuid,
}

const URGENT_KEYWORDS: &[&str] = &[
    "urgent",
    "urgence",
    "urgences",
    "douleur intense",
    "très douloureux",
    "très douloureuse",
    "saignement",
    "saigne",
    "gonflement",
    "fracture",
    "fièvre",
];

fn triage(body: &str) -> (&'static str, Option<String>) {
    let lower = body.to_lowercase();
    let matched: Vec<&str> = URGENT_KEYWORDS
        .iter()
        .filter(|&&kw| lower.contains(kw))
        .copied()
        .collect();
    if matched.is_empty() {
        ("normal", None)
    } else {
        ("urgent", Some(matched.join(", ")))
    }
}

/// `POST /v1/conversations/:id/messages` — envoie un message dans un fil existant.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` (vérif conversation)
/// puis `app.current_cabinet_id` (INSERT message — policy `tenant_isolation`).
/// Conversation hors tenant → 404.
/// Chiffrement POC : `body_ciphertext` = UTF-8 brut, `body_key_ref` = `"poc-stub"`.
/// Chiffrement réel KMS prévu avec NUB-T3 (`core/crypto`).
/// `triage_flag` calculé par mots-clés — priorisation visuelle uniquement (§07 §8.3).
pub async fn send_message(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(conversation_id): Path<Uuid>,
    Json(body): Json<SendMessageBody>,
) -> Result<impl IntoResponse, AppError> {
    let (triage_flag, triage_reason) = triage(&body.body);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope RLS patient — policies conversation_patient_read + message_patient_read.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que la conversation est accessible (RLS filtre si hors tenant → None = 404).
    let conv_row = sqlx::query("SELECT cabinet_id FROM conversation WHERE id = $1")
        .bind(conversation_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let conv_row = conv_row.ok_or(AppError::NotFound)?;
    let cabinet_id: Uuid = conv_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;

    // Scope RLS cabinet pour INSERT message (policy tenant_isolation WITH CHECK).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO message \
         (cabinet_id, conversation_id, sender_kind, sender_id, \
          body_ciphertext, body_key_ref, triage_flag, triage_reason) \
         VALUES ($1, $2, 'patient', $3, $4, $5, $6, $7) \
         RETURNING id",
    )
    .bind(cabinet_id)
    .bind(conversation_id)
    .bind(claims.sub)
    .bind(body.body.as_bytes())
    .bind("poc-stub")
    .bind(triage_flag)
    .bind(triage_reason.as_deref())
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let message_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Stub notification au cabinet — implémentation réelle avec NUB-T4.
    tracing::info!(
        account_id = %claims.account_id,
        conversation_id = %conversation_id,
        message_id = %message_id,
        triage_flag,
        "message envoyé — notification cabinet stub"
    );

    Ok((
        StatusCode::CREATED,
        Json(SendMessageResponse { message_id }),
    ))
}

/// Corps de la requête `POST /v1/conversations`.
#[derive(Deserialize)]
pub struct CreateConversationBody {
    pub cabinet_id: Uuid,
}

/// Réponse de `POST /v1/conversations`.
#[derive(Serialize)]
pub struct CreateConversationResponse {
    pub conversation_id: Uuid,
    pub existing: bool,
}

/// `POST /v1/conversations` — démarre un fil de messagerie patient ↔ cabinet.
///
/// Idempotent : un seul fil par couple `(patient_account_id, cabinet_id)` — contrainte
/// DB unique. Cabinet inexistant ou non listé (`is_listed=false`) → `404`.
/// Fil existant → `200 + existing:true`. Nouveau fil → `201 + existing:false`.
pub async fn create_conversation(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<CreateConversationBody>,
) -> Result<impl IntoResponse, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Vérifie que le cabinet a au moins un praticien listé (lecture publique sans GUC).
    let listed =
        sqlx::query("SELECT 1 FROM provider WHERE cabinet_id = $1 AND is_listed = true LIMIT 1")
            .bind(body.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    if listed.is_none() {
        return Err(AppError::NotFound);
    }

    // Scope RLS au cabinet cible pour la table conversation (SET LOCAL — scoped à tx).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(body.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Tente l'insertion — ON CONFLICT DO NOTHING pour l'idempotence.
    let row = sqlx::query(
        "INSERT INTO conversation (patient_account_id, cabinet_id) \
         VALUES ($1, $2) \
         ON CONFLICT (patient_account_id, cabinet_id) DO NOTHING \
         RETURNING id",
    )
    .bind(claims.account_id)
    .bind(body.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (conversation_id, existing) = if let Some(r) = row {
        let id: Uuid = r.try_get("id").map_err(|_| AppError::Internal)?;
        (id, false)
    } else {
        // Fil existant — le récupérer (RLS via GUC déjà positionné).
        let existing_row = sqlx::query(
            "SELECT id FROM conversation \
             WHERE patient_account_id = $1 AND cabinet_id = $2",
        )
        .bind(claims.account_id)
        .bind(body.cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        let id: Uuid = existing_row.try_get("id").map_err(|_| AppError::Internal)?;
        (id, true)
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        patient_account_id = %claims.account_id,
        cabinet_id = %body.cabinet_id,
        conversation_id = %conversation_id,
        existing,
        "conversation created or fetched"
    );

    let response = CreateConversationResponse {
        conversation_id,
        existing,
    };

    if existing {
        Ok((StatusCode::OK, Json(response)).into_response())
    } else {
        Ok((StatusCode::CREATED, Json(response)).into_response())
    }
}
