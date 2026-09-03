//! Messagerie patient ↔ pharmacie (lot B6) — espace `/v1/pharmacy`.
//!
//! Mêmes formes JSON que `/v1/cabinet/conversations*` (le front réutilise ses
//! DTOs avec `basePath: '/pharmacy'`). `triage_flag` toujours `normal` : la
//! priorisation d'urgence est un outil cabinet, pas officine.

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PharmaMemberClaims},
    notify,
    realtime::WsHub,
    AppState,
};

// ── GET /v1/pharmacy/conversations ────────────────────────────────────────────

/// Une conversation dans la liste pharmacie (mêmes clés que le cabinet).
#[derive(Serialize)]
pub struct ConversationItem {
    pub id: Uuid,
    pub patient_name: String,
    pub unread_count: i64,
    pub last_message_at: Option<String>,
    /// Aperçu (tronqué) du dernier message — même contrat que
    /// `CabinetConversationItem.last_message_preview` (#3854). Absent avant
    /// ce fix : le front réutilise ses DTOs cabinet côté pharmacie et
    /// affichait « Aucun message » sur TOUT fil, y compris avec des non-lus.
    pub last_message_preview: Option<String>,
    pub scope: String,
    pub status: String,
}

/// Réponse de `GET /v1/pharmacy/conversations`.
#[derive(Serialize)]
pub struct ConversationsResponse {
    pub data: Vec<ConversationItem>,
}

/// `GET /v1/pharmacy/conversations` — fils patient ↔ pharmacie du tenant.
/// Tri : dernier message d'abord. RLS `conversation_pharmacy_all`.
pub async fn list_pharmacy_conversations(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
) -> Result<Json<ConversationsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT c.id, \
                COALESCE(c.patient_display_name, 'Patient') AS patient_name, \
                c.scope, c.status, \
                (SELECT MAX(m.created_at) FROM message m \
                 WHERE m.conversation_id = c.id) AS last_message_at, \
                (SELECT m.body_ciphertext FROM message m \
                 WHERE m.conversation_id = c.id \
                 ORDER BY m.created_at DESC, m.id DESC LIMIT 1) AS last_body, \
                (SELECT COUNT(*) FROM message m \
                 WHERE m.conversation_id = c.id \
                   AND m.sender_kind = 'patient' AND m.read_at IS NULL) AS unread_count \
         FROM conversation c \
         WHERE c.deleted_at IS NULL \
         ORDER BY last_message_at DESC NULLS LAST, c.id DESC \
         LIMIT 100",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(|row| {
            // POC chiffrement : UTF-8 brut, aperçu tronqué à 120 caractères
            // (même contrat que list_cabinet_conversations).
            let last_body: Option<Vec<u8>> =
                row.try_get("last_body").map_err(|_| AppError::Internal)?;
            let last_message_preview = last_body
                .and_then(|b| String::from_utf8(b).ok())
                .map(|t| t.chars().take(120).collect::<String>());

            Ok(ConversationItem {
                id: row.try_get("id").map_err(|_| AppError::Internal)?,
                patient_name: row
                    .try_get("patient_name")
                    .map_err(|_| AppError::Internal)?,
                unread_count: row
                    .try_get("unread_count")
                    .map_err(|_| AppError::Internal)?,
                last_message_at: row
                    .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("last_message_at")
                    .map_err(|_| AppError::Internal)?
                    .map(|dt| dt.to_rfc3339()),
                last_message_preview,
                scope: row.try_get("scope").map_err(|_| AppError::Internal)?,
                status: row.try_get("status").map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(ConversationsResponse { data }))
}

// ── GET /v1/pharmacy/conversations/:id/messages ───────────────────────────────

/// Un message du fil (mêmes clés que le cabinet — chiffrement POC UTF-8).
/// `sender` reprend `sender_kind` : `MessageDto.fromJson` (front) exige la
/// clé `sender`, non-nullable — seul cet endpoint ne l'émettait pas (#3712),
/// faisant planter le fil pharmacie au décodage. Même pattern que
/// `CabinetMessageItem` (cabinet_messaging.rs).
#[derive(Serialize)]
pub struct MessageItem {
    pub id: Uuid,
    pub body: String,
    pub sender: String,
    pub sender_kind: String,
    pub created_at: String,
    pub read_at: Option<String>,
}

/// Réponse de `GET /v1/pharmacy/conversations/:id/messages`.
#[derive(Serialize)]
pub struct MessagesResponse {
    pub data: Vec<MessageItem>,
}

/// `GET /v1/pharmacy/conversations/:id/messages` — fil chronologique.
/// Conversation hors tenant → 404 (RLS).
pub async fn get_pharmacy_conversation_messages(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
    Path(conversation_id): Path<Uuid>,
) -> Result<Json<MessagesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT 1 FROM conversation WHERE id = $1")
        .bind(conversation_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let rows = sqlx::query(
        "SELECT id, body_ciphertext, sender_kind, created_at, read_at \
         FROM message WHERE conversation_id = $1 \
         ORDER BY created_at ASC LIMIT 500",
    )
    .bind(conversation_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(|row| {
            let ciphertext: Vec<u8> = row
                .try_get("body_ciphertext")
                .map_err(|_| AppError::Internal)?;
            let sender_kind: String = row.try_get("sender_kind").map_err(|_| AppError::Internal)?;
            Ok(MessageItem {
                id: row.try_get("id").map_err(|_| AppError::Internal)?,
                // Chiffrement POC : UTF-8 brut (NUB-T3 pour le réel).
                body: String::from_utf8_lossy(&ciphertext).into_owned(),
                sender: sender_kind.clone(),
                sender_kind,
                created_at: row
                    .try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
                    .map_err(|_| AppError::Internal)?
                    .to_rfc3339(),
                read_at: row
                    .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("read_at")
                    .map_err(|_| AppError::Internal)?
                    .map(|dt| dt.to_rfc3339()),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(MessagesResponse { data }))
}

// ── POST /v1/pharmacy/conversations/:id/messages ──────────────────────────────

/// Corps de `POST /v1/pharmacy/conversations/:id/messages`.
#[derive(Deserialize)]
pub struct SendPharmacyMessageBody {
    pub body: String,
}

/// Réponse de `POST /v1/pharmacy/conversations/:id/messages`.
/// `message_id` (historique) + le message complet : le front parse la réponse
/// comme un MessageDto (`id`/`body`/`sender`/`created_at`) — sans ces champs,
/// l'envoi réussissait côté serveur mais crashait au parse côté pharmacie
/// (mêmes symptômes que le correctif cabinet, cf. `SendCabinetMessageResponse`).
#[derive(Serialize)]
pub struct SendPharmacyMessageResponse {
    pub message_id: Uuid,
    pub id: Uuid,
    pub body: String,
    pub sender: String,
    pub sender_kind: String,
    pub created_at: String,
    pub read_at: Option<String>,
}

/// `POST /v1/pharmacy/conversations/:id/messages` — réponse du pharmacien.
/// Body vide → 422. Hors tenant → 404. `triage_flag` forcé `normal`.
/// Publie `message_created` sur le canal WS `conversation:<id>`.
pub async fn send_pharmacy_message(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn crate::JobDispatcher>>,
    claims: PharmaMemberClaims,
    Path(conversation_id): Path<Uuid>,
    Json(body): Json<SendPharmacyMessageBody>,
) -> Result<(StatusCode, Json<SendPharmacyMessageResponse>), AppError> {
    if body.body.trim().is_empty() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let conv_row = sqlx::query(
        "SELECT patient_account_id FROM conversation WHERE id = $1 AND pharmacy_id = $2",
    )
    .bind(conversation_id)
    .bind(claims.pharmacy_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let patient_account_id: Option<Uuid> = conv_row
        .try_get("patient_account_id")
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO message \
         (pharmacy_id, conversation_id, sender_kind, sender_id, \
          body_ciphertext, body_key_ref, triage_flag) \
         VALUES ($1, $2, 'pharmacist', $3, $4, 'poc-stub', 'normal') \
         RETURNING id, created_at",
    )
    .bind(claims.pharmacy_id)
    .bind(conversation_id)
    .bind(claims.sub)
    .bind(body.body.as_bytes())
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let message_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    // Notifie le patient (#6259). Titre sans contenu du message (anti-PII).
    // Patient sans compte app : notification silencieusement absente, même
    // choix que `cabinet_messaging::send_cabinet_message`.
    let mut push_target: Option<(Uuid, Uuid)> = None;
    if let Some(account_id) = patient_account_id {
        push_target = notify::notify_patient_account(
            &mut tx,
            account_id,
            "message_received",
            "Vous avez reçu un nouveau message",
            serde_json::json!({ "conversation_id": conversation_id, "type": "pharmacy" }),
        )
        .await?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Push temps réel/mobile APRÈS commit (pattern pharmacy/orders.rs) — le
    // retour du notify était jeté, aucun push ne partait (#6259 incomplet).
    if let Some((app_user_id, notification_id)) = push_target {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }

    let channel = format!("conversation:{conversation_id}");
    hub.publish_named(
        &channel,
        serde_json::json!({
            "channel": channel,
            "event": "message_created",
            "data": { "message_id": message_id, "sender_kind": "pharmacist" }
        })
        .to_string(),
    );

    Ok((
        StatusCode::CREATED,
        Json(SendPharmacyMessageResponse {
            message_id,
            id: message_id,
            body: body.body,
            sender: "pharmacist".to_string(),
            sender_kind: "pharmacist".to_string(),
            created_at: created_at.to_rfc3339(),
            read_at: None,
        }),
    ))
}

// ── POST /v1/pharmacy/conversations/:id/read ──────────────────────────────────

/// `POST /v1/pharmacy/conversations/:id/read` — marque les messages patient
/// du fil comme lus. Hors tenant → 404.
pub async fn mark_pharmacy_conversation_read(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    claims: PharmaMemberClaims,
    Path(conversation_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_pharmacy_id', $1, true)")
        .bind(claims.pharmacy_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT 1 FROM conversation WHERE id = $1")
        .bind(conversation_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    sqlx::query(
        "UPDATE message SET read_at = now() \
         WHERE conversation_id = $1 AND sender_kind = 'patient' AND read_at IS NULL",
    )
    .bind(conversation_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let channel = format!("conversation:{conversation_id}");
    hub.publish_named(
        &channel,
        serde_json::json!({
            "channel": channel,
            "event": "read",
            "data": { "conversation_id": conversation_id, "by": "pharmacist" }
        })
        .to_string(),
    );

    Ok(StatusCode::NO_CONTENT)
}
