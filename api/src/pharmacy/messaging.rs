//! Messagerie patient ↔ pharmacie (lot B6) — espace `/v1/pharmacy`.
//!
//! Mêmes formes JSON que `/v1/cabinet/conversations*` (le front réutilise ses
//! DTOs avec `basePath: '/pharmacy'`). `triage_flag` reflète la classification
//! posée par `messaging::triage` sur les messages patient (#6942) : la
//! facette « Urgentes » de la maquette officine en dépend.

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, Query, State},
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
    /// `patient_account.id` (#8211) — seule clé non ambiguë pour relier cette
    /// conversation aux commandes du MÊME patient : `patient_name` est un
    /// libellé minimisé (« Prénom N. ») à plusieurs antécédents possibles,
    /// impropre à une jointure. `null` si la conversation n'est pas (encore)
    /// rattachée à un compte patient.
    pub patient_id: Option<Uuid>,
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
    /// Référence courte (`CMD-0363`) de la commande la plus récente du
    /// patient dans cette officine (#7249) — même format que
    /// `OrderDto.order_ref` (`orders.rs`). `null` si le patient n'a aucune
    /// commande dans cette pharmacie.
    pub order_ref: Option<String>,
    /// Libellé court du statut de cette commande (« Prête », « En prépa »,
    /// #7249) — distinct des libellés longs de la file commandes
    /// (`orderStatusLabel` front, `order_status_pill.dart`) : la maquette
    /// messagerie utilise un format compact pour le chip. `null` quand
    /// [order_ref] est `null`.
    pub order_status_label: Option<String>,
    /// `urgent` ou `normal` — même contrat que `CabinetConversationItem.triage_flag`
    /// (#6942) : `urgent` tant qu'un message patient urgent est non lu dans le fil,
    /// seul moyen d'alimenter la facette « Urgentes » de la maquette v2.
    pub triage_flag: String,
}

/// Réponse de `GET /v1/pharmacy/conversations`.
#[derive(Serialize)]
pub struct ConversationsResponse {
    pub data: Vec<ConversationItem>,
}

/// `GET /v1/pharmacy/conversations` — fils patient ↔ pharmacie du tenant.
/// Tri : dernier message d'abord. RLS `conversation_pharmacy_all`.
/// `patient_name` : `c.patient_display_name` est gelé à la création du fil
/// (#6635 non résolu en prod, #6891) — avant le repli littéral `'Patient'`,
/// on recalcule le nom minimisé à la lecture via `patient_account_minimized_name()`
/// (SECURITY DEFINER, migration 0310), qui contourne la RLS `patient_account`
/// comme `minimized_patient_name()` le fait déjà pour les commandes.
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
        "SELECT c.id, c.patient_account_id AS patient_id, \
                COALESCE( \
                    c.patient_display_name, \
                    (SELECT po.patient_display_name FROM pharmacy_order po \
                     WHERE po.patient_account_id = c.patient_account_id \
                       AND po.pharmacy_id = c.pharmacy_id \
                     ORDER BY po.received_at DESC, po.id DESC LIMIT 1), \
                    patient_account_minimized_name(c.patient_account_id), \
                    'Patient' \
                ) AS patient_name, \
                c.scope, c.status, \
                (SELECT MAX(m.created_at) FROM message m \
                 WHERE m.conversation_id = c.id) AS last_message_at, \
                (SELECT m.body_ciphertext FROM message m \
                 WHERE m.conversation_id = c.id \
                 ORDER BY m.created_at DESC, m.id DESC LIMIT 1) AS last_body, \
                (SELECT COUNT(*) FROM message m \
                 WHERE m.conversation_id = c.id \
                   AND m.sender_kind = 'patient' AND m.read_at IS NULL) AS unread_count, \
                (SELECT ('CMD-' || lpad(po.order_seq::text, 4, '0')) FROM pharmacy_order po \
                 WHERE po.patient_account_id = c.patient_account_id \
                   AND po.pharmacy_id = c.pharmacy_id \
                 ORDER BY po.received_at DESC, po.id DESC LIMIT 1) AS order_ref, \
                (SELECT CASE po.status \
                           WHEN 'received' THEN 'Reçue' \
                           WHEN 'preparing' THEN 'En prépa' \
                           WHEN 'ready' THEN 'Prête' \
                           WHEN 'picked_up' THEN 'Retirée' \
                           WHEN 'rejected' THEN 'Refusée' \
                           WHEN 'cancelled' THEN 'Annulée' \
                         END \
                 FROM pharmacy_order po \
                 WHERE po.patient_account_id = c.patient_account_id \
                   AND po.pharmacy_id = c.pharmacy_id \
                 ORDER BY po.received_at DESC, po.id DESC LIMIT 1) AS order_status_label, \
                (CASE WHEN EXISTS ( \
                     SELECT 1 FROM message m \
                     WHERE m.conversation_id = c.id \
                       AND m.sender_kind = 'patient' \
                       AND m.triage_flag = 'urgent' \
                       AND m.read_at IS NULL \
                 ) THEN 'urgent' ELSE 'normal' END) AS triage_flag \
         FROM conversation c \
         WHERE c.deleted_at IS NULL \
           AND EXISTS (SELECT 1 FROM message m WHERE m.conversation_id = c.id) \
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
                patient_id: row.try_get("patient_id").map_err(|_| AppError::Internal)?,
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
                order_ref: row.try_get("order_ref").map_err(|_| AppError::Internal)?,
                order_status_label: row
                    .try_get("order_status_label")
                    .map_err(|_| AppError::Internal)?,
                triage_flag: row.try_get("triage_flag").map_err(|_| AppError::Internal)?,
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
    /// `urgent` ou `normal` (#6942) — classification déjà posée en base à
    /// l'écriture (`messaging::triage`), jamais exposée côté officine.
    pub triage_flag: String,
}

/// Pagination de la réponse de `GET /v1/pharmacy/conversations/:id/messages`
/// (#8391) — même forme que `cabinet_messaging::PageInfo`.
#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

/// Réponse de `GET /v1/pharmacy/conversations/:id/messages`.
#[derive(Serialize)]
pub struct MessagesResponse {
    pub data: Vec<MessageItem>,
    pub page: PageInfo,
}

/// Paramètres de `GET /v1/pharmacy/conversations/:id/messages`.
#[derive(Deserialize)]
pub struct ListMessagesQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

/// Encode un curseur de fil de messages : `created_at` (jamais null), `id`.
/// Même schéma que `cabinet_messaging::encode_message_cursor`.
fn encode_message_cursor(created_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", created_at.timestamp_micros(), id)
}

/// Décode un curseur de fil de messages. Retourne `None` si malformé.
fn decode_message_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (ts_str, id_str) = s.split_once('|')?;
    let micros: i64 = ts_str.parse().ok()?;
    let ts = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((ts, id))
}

/// `GET /v1/pharmacy/conversations/:id/messages` — fil chronologique.
/// Conversation hors tenant → 404 (RLS). Paginé par curseur (#8391), même
/// schéma que `cabinet_messaging::get_cabinet_conversation_messages`.
pub async fn get_pharmacy_conversation_messages(
    State(state): State<AppState>,
    claims: PharmaMemberClaims,
    Path(conversation_id): Path<Uuid>,
    Query(params): Query<ListMessagesQuery>,
) -> Result<Json<MessagesResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let cursor = match params.cursor.as_deref() {
        Some(s) => Some(decode_message_cursor(s).ok_or(AppError::ValidationError)?),
        None => None,
    };

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

    let cursor_clause = if cursor.is_some() {
        " AND (created_at > $3 OR (created_at = $3 AND id > $4))"
    } else {
        ""
    };

    let fetch_limit = limit + 1;
    let sql = format!(
        "SELECT id, body_ciphertext, sender_kind, created_at, read_at, triage_flag \
         FROM message WHERE conversation_id = $1 \
         {cursor_clause} \
         ORDER BY created_at ASC, id ASC LIMIT $2"
    );

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

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    let data = visible
        .iter()
        .map(|row| {
            let ciphertext: Vec<u8> = row
                .try_get("body_ciphertext")
                .map_err(|_| AppError::Internal)?;
            let sender_kind: String = row.try_get("sender_kind").map_err(|_| AppError::Internal)?;
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let created_at: chrono::DateTime<chrono::Utc> =
                row.try_get("created_at").map_err(|_| AppError::Internal)?;
            last_created_at = Some(created_at);
            last_id = Some(id);
            Ok(MessageItem {
                id,
                // Chiffrement POC : UTF-8 brut (NUB-T3 pour le réel).
                body: String::from_utf8_lossy(&ciphertext).into_owned(),
                sender: sender_kind.clone(),
                sender_kind,
                triage_flag: row.try_get("triage_flag").map_err(|_| AppError::Internal)?,
                created_at: created_at.to_rfc3339(),
                read_at: row
                    .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("read_at")
                    .map_err(|_| AppError::Internal)?
                    .map(|dt| dt.to_rfc3339()),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| encode_message_cursor(dt, id))
    } else {
        None
    };

    Ok(Json(MessagesResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}

// ── POST /v1/pharmacy/conversations/:id/messages ──────────────────────────────

/// Corps de `POST /v1/pharmacy/conversations/:id/messages`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
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
/// Body vide, contenant un octet NUL, ou dépassant `MAX_MESSAGE_BODY_CHARS`
/// (même borne que les deux composeurs frères, `send_message` et
/// `send_cabinet_message`, #8209/#8229) → 422. Hors tenant → 404.
/// `triage_flag` forcé `normal`.
/// Publie `message_created` sur le canal WS `conversation:<id>`.
pub async fn send_pharmacy_message(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn crate::JobDispatcher>>,
    claims: PharmaMemberClaims,
    Path(conversation_id): Path<Uuid>,
    Json(body): Json<SendPharmacyMessageBody>,
) -> Result<(StatusCode, Json<SendPharmacyMessageResponse>), AppError> {
    if body.body.trim().is_empty()
        || body.body.chars().count() > crate::messaging::MAX_MESSAGE_BODY_CHARS
    {
        return Err(AppError::ValidationError);
    }
    crate::text_validation::reject_nul_byte(&body.body)?;

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
