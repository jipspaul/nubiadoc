//! Handler `GET /v1/cabinet/conversations` — file priorisée des conversations back-office.
//!
//! Section 18 — messagerie priorisée cabinet. Tri urgent en tête.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

#[derive(Deserialize)]
pub struct ListCabinetConversationsQuery {
    /// Filtre optionnel : `clinical` (praticien+admin uniquement) ou autre valeur = non-clinique.
    pub scope: Option<String>,
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

/// Un fil de messagerie dans la file priorisée du cabinet.
#[derive(Serialize)]
pub struct CabinetConversationItem {
    pub id: Uuid,
    pub patient_first_name: String,
    pub patient_last_name: String,
    /// ISO 8601 UTC du dernier message, ou `null` si aucun message encore.
    pub last_message_at: Option<String>,
    /// Aperçu (tronqué) du dernier message — POC chiffrement UTF-8 (#3373).
    pub last_message_preview: Option<String>,
    /// `urgent` ou `normal` — `urgent` tant qu'un message patient urgent est non lu dans le fil.
    pub triage_flag: String,
    /// Messages patient non lus (`sender_kind='patient'`, `read_at IS NULL`).
    pub unread_count: i64,
    pub scope: String,
    pub status: String,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

#[derive(Serialize)]
pub struct ListCabinetConversationsResponse {
    pub data: Vec<CabinetConversationItem>,
    pub page: PageInfo,
}

/// Encode un curseur à partir des 3 clés de tri : urgency_int (0=urgent,1=normal),
/// last_message_at (vide si null), id.
fn encode_cursor(
    urgency_int: i32,
    last_message_at: Option<chrono::DateTime<chrono::Utc>>,
    id: Uuid,
) -> String {
    let ts = last_message_at
        .map(|dt| dt.timestamp_micros().to_string())
        .unwrap_or_default();
    format!("{}|{}|{}", urgency_int, ts, id)
}

/// Décode un curseur en `(urgency_int, last_message_at?, id)`. Retourne `None` si malformé.
fn decode_cursor(s: &str) -> Option<(i32, Option<chrono::DateTime<chrono::Utc>>, Uuid)> {
    let mut parts = s.splitn(3, '|');
    let urgency: i32 = parts.next()?.parse().ok()?;
    let ts_str = parts.next()?;
    let ts = if ts_str.is_empty() {
        None
    } else {
        let micros: i64 = ts_str.parse().ok()?;
        Some(chrono::DateTime::from_timestamp_micros(micros)?)
    };
    let id = Uuid::parse_str(parts.next()?).ok()?;
    Some((urgency, ts, id))
}

/// `GET /v1/cabinet/conversations` — file priorisée des conversations du cabinet.
///
/// Token pro requis (secretary, practitioner, admin) — patient → 401/403.
/// RLS via `app.current_cabinet_id` (policy `tenant_isolation`, migration 0011).
/// Tri : `triage_flag` urgent en tête (`urgency_int ASC`), puis `last_message_at DESC NULLS LAST`,
/// puis `id DESC`.
/// Cloisonnement fil clinique : `scope='clinical'` → practitioner/admin uniquement ;
/// secrétaire → 403 si `?scope=clinical`, filtre silencieux sinon.
pub async fn list_cabinet_conversations(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<ListCabinetConversationsQuery>,
) -> Result<Json<ListCabinetConversationsResponse>, AppError> {
    // Cloisonnement fil clinique : secretary interdit sur scope=clinical (§07 §4.1).
    if claims.role == "secretary" && params.scope.as_deref() == Some("clinical") {
        return Err(AppError::Forbidden);
    }

    // R10 : secrétaire sans secrétariat actif → liste vide.
    if claims.role == "secretary" && claims.secretariat_id.is_none() {
        return Ok(Json(ListCabinetConversationsResponse {
            data: vec![],
            page: PageInfo {
                next_cursor: None,
                limit: params.limit.unwrap_or(20).clamp(1, 100),
            },
        }));
    }

    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let fetch_limit = limit + 1;
    let cursor = match params.cursor.as_deref() {
        Some(s) => Some(decode_cursor(s).ok_or(AppError::ValidationError)?),
        None => None,
    };

    // Filtre scope dans la CTE (références à c.scope). Le fil de support
    // admin↔plateforme (#4169) doit rester invisible pour tout rôle non-admin,
    // cohérent avec la garde posée sur les endpoints d'accès direct (#4843).
    let scope_filter = match (claims.role.as_str(), params.scope.as_deref()) {
        ("secretary", _) => " AND c.scope != 'clinical' AND c.scope != 'platform_support'",
        (_, Some("clinical")) => " AND c.scope = 'clinical'",
        ("admin", Some(_)) => " AND c.scope != 'clinical'",
        (_, Some(_)) => " AND c.scope != 'clinical' AND c.scope != 'platform_support'",
        ("admin", None) => "",
        (_, None) => " AND c.scope != 'platform_support'",
    };

    // Clause cursor dans la SELECT externe (pas d'alias de table — colonnes viennent de la CTE).
    // $2/$3/$4 (cursor avec ts) ou $2/$3 (cursor sans ts).
    let cursor_clause = match &cursor {
        None => String::new(),
        Some((_, Some(_), _)) => {
            // cursor_ts non-null : $2=urgency_c, $3=ts_c, $4=id_c
            " AND (urgency_int > $2 \
               OR (urgency_int = $2 AND last_message_at < $3) \
               OR (urgency_int = $2 AND last_message_at = $3 AND id < $4) \
               OR (urgency_int = $2 AND last_message_at IS NULL))"
                .to_string()
        }
        Some((_, None, _)) => {
            // cursor_ts null : $2=urgency_c, $3=id_c
            " AND (urgency_int > $2 \
               OR (urgency_int = $2 AND last_message_at IS NULL AND id < $3))"
                .to_string()
        }
    };

    // R10 : secrétaire scopée au secrétariat actif.
    // Le paramètre secretariat_id est toujours lié EN DERNIER (après les params curseur).
    // Numéro de param : pas de cursor → $2 ; cursor sans ts → $4 ; cursor avec ts → $5.
    let sec_param_n = match &cursor {
        None => 2,
        Some((_, None, _)) => 4,
        Some((_, Some(_), _)) => 5,
    };
    let sec_filter = if claims.role == "secretary" {
        format!(
            " AND EXISTS ( \
                 SELECT 1 FROM appointment a \
                 JOIN provider pr ON pr.practitioner_id = a.practitioner_id \
                 JOIN provider_secretariat ps ON ps.provider_id = pr.id \
                 WHERE a.patient_id = c.patient_id \
                   AND a.deleted_at IS NULL \
                   AND ps.active = true \
                   AND ps.secretariat_id = ${sec_param_n} \
             )"
        )
    } else {
        String::new()
    };

    // `scope_filter`/`cursor_clause`/`sec_filter` multiplient les variantes de texte
    // SQL générées ici (jusqu'à ~36 combinaisons). Exécuté en `persistent(false)`
    // plus bas : évite de saturer/faire tourner le cache de plans préparés par
    // connexion avec autant de textes proches, cause suspectée du 500 intermittent
    // observé sur la branche `(_, None)` (#5551, régression #5446).
    let sql = format!(
        "WITH conv AS ( \
             SELECT \
                 c.id, \
                 COALESCE(p.first_name, pa.first_name, '') AS patient_first_name, \
                 COALESCE(p.last_name,  pa.last_name,  '') AS patient_last_name, \
                 c.scope, \
                 c.status, \
                 (SELECT MAX(m.created_at) \
                  FROM message m WHERE m.conversation_id = c.id) AS last_message_at, \
                 (SELECT m.body_ciphertext FROM message m \
                  WHERE m.conversation_id = c.id \
                  ORDER BY m.created_at DESC, m.id DESC LIMIT 1) AS last_body, \
                 CASE WHEN EXISTS ( \
                     SELECT 1 FROM message m \
                     WHERE m.conversation_id = c.id \
                       AND m.sender_kind = 'patient' \
                       AND m.triage_flag = 'urgent' \
                       AND m.read_at IS NULL \
                 ) THEN 'urgent' ELSE 'normal' END AS triage_flag, \
                 CASE WHEN EXISTS ( \
                     SELECT 1 FROM message m \
                     WHERE m.conversation_id = c.id \
                       AND m.sender_kind = 'patient' \
                       AND m.triage_flag = 'urgent' \
                       AND m.read_at IS NULL \
                 ) THEN 0 ELSE 1 END AS urgency_int, \
                 (SELECT COUNT(*) FROM message m \
                  WHERE m.conversation_id = c.id \
                    AND m.sender_kind = 'patient' \
                    AND m.read_at IS NULL) AS unread_count \
             FROM conversation c \
             LEFT JOIN patient p  ON p.id  = c.patient_id \
             LEFT JOIN patient_account pa ON pa.id = c.patient_account_id \
             WHERE true{scope_filter}{sec_filter} \
         ) \
         SELECT id, patient_first_name, patient_last_name, last_message_at, \
                last_body, triage_flag, urgency_int, unread_count, scope, status \
         FROM conv \
         WHERE true{cursor_clause} \
         ORDER BY urgency_int ASC, last_message_at DESC NULLS LAST, id DESC \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // RLS tenant : toutes les lectures (conversation, message, patient) scopées au cabinet.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Lie les paramètres : $1=fetch_limit, puis curseur ($2...), puis secretariat_id si secretary.
    let sid = claims.secretariat_id;
    let rows = match &cursor {
        None => {
            let q = sqlx::query(&sql).persistent(false).bind(fetch_limit);
            if let Some(s) = sid { q.bind(s) } else { q }
                .fetch_all(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
        }
        Some((urgency_c, Some(ts_c), id_c)) => {
            let q = sqlx::query(&sql)
                .persistent(false)
                .bind(fetch_limit)
                .bind(urgency_c)
                .bind(ts_c)
                .bind(id_c);
            if let Some(s) = sid { q.bind(s) } else { q }
                .fetch_all(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
        }
        Some((urgency_c, None, id_c)) => {
            let q = sqlx::query(&sql)
                .persistent(false)
                .bind(fetch_limit)
                .bind(urgency_c)
                .bind(id_c);
            if let Some(s) = sid { q.bind(s) } else { q }
                .fetch_all(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
        }
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<CabinetConversationItem> = Vec::with_capacity(visible.len());
    let mut last_urgency: Option<i32> = None;
    let mut last_lma: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let patient_first_name: String = row
            .try_get("patient_first_name")
            .map_err(|_| AppError::Internal)?;
        let patient_last_name: String = row
            .try_get("patient_last_name")
            .map_err(|_| AppError::Internal)?;
        let lma: Option<chrono::DateTime<chrono::Utc>> = row
            .try_get("last_message_at")
            .map_err(|_| AppError::Internal)?;
        let triage_flag: String = row.try_get("triage_flag").map_err(|_| AppError::Internal)?;
        let urgency_int: i32 = row.try_get("urgency_int").map_err(|_| AppError::Internal)?;
        let unread_count: i64 = row
            .try_get("unread_count")
            .map_err(|_| AppError::Internal)?;
        let scope: String = row.try_get("scope").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        // POC chiffrement : UTF-8 brut, aperçu tronqué à 120 caractères.
        let last_body: Option<Vec<u8>> =
            row.try_get("last_body").map_err(|_| AppError::Internal)?;
        let last_message_preview = last_body
            .and_then(|b| String::from_utf8(b).ok())
            .map(|t| t.chars().take(120).collect::<String>());

        last_urgency = Some(urgency_int);
        last_lma = lma;
        last_id = Some(id);

        data.push(CabinetConversationItem {
            id,
            patient_first_name,
            patient_last_name,
            last_message_at: lma.map(|dt| dt.to_rfc3339()),
            last_message_preview,
            triage_flag,
            unread_count,
            scope,
            status,
        });
    }

    let next_cursor = if has_more {
        last_urgency
            .zip(last_id)
            .map(|(urgency, id)| encode_cursor(urgency, last_lma, id))
    } else {
        None
    };

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        role = %claims.role,
        count = data.len(),
        has_more,
        "cabinet conversations listed"
    );

    Ok(Json(ListCabinetConversationsResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}

// ── POST /v1/cabinet/conversations/:id/messages ──────────────────────────────

/// Corps de `POST /v1/cabinet/conversations/:id/messages`.
#[derive(Deserialize)]
pub struct SendCabinetMessageBody {
    pub body: String,
}

/// Réponse de `POST /v1/cabinet/conversations/:id/messages`.
/// `message_id` (historique) + le message complet : le front parse la réponse
/// comme un MessageDto (`id`/`body`/`sender`/`created_at`) — sans ces champs,
/// l'envoi réussissait côté serveur mais crashait au parse côté cabinet.
#[derive(Serialize)]
pub struct SendCabinetMessageResponse {
    pub message_id: Uuid,
    pub id: Uuid,
    pub body: String,
    pub sender: String,
    pub sender_kind: String,
    pub created_at: String,
    pub read_at: Option<String>,
}

// ── GET /v1/cabinet/conversations/:id/messages ───────────────────────────────

/// Un message du fil côté cabinet. `sender` reprend `sender_kind`
/// (`patient` | `practitioner` | `secretary`) — le front ne distingue que
/// patient / cabinet.
#[derive(Serialize)]
pub struct CabinetMessageItem {
    pub id: Uuid,
    pub body: String,
    pub sender: String,
    pub sender_kind: String,
    pub created_at: String,
    pub read_at: Option<String>,
}

/// Réponse de `GET /v1/cabinet/conversations/:id/messages`.
#[derive(Serialize)]
pub struct CabinetMessagesResponse {
    pub data: Vec<CabinetMessageItem>,
}

/// `GET /v1/cabinet/conversations/:id/messages` — fil chronologique côté
/// cabinet (#3366 : la route n'existait qu'en POST, ouvrir un fil → 405).
/// Secrétaire et praticien. Conversation hors tenant → 404 (RLS + garde).
/// Chiffrement POC : UTF-8 brut (NUB-T3 pour le réel).
pub async fn get_cabinet_conversation_messages(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(conversation_id): Path<Uuid>,
) -> Result<Json<CabinetMessagesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Conversation du cabinet, hors fils cliniques pour un secrétaire (§07 §4.1)
    // et hors fil de support admin↔plateforme pour tout rôle non-admin (#4843).
    // R10 (#5715) : pour une secrétaire, cloisonnement au secrétariat rattaché
    // au(x) praticien(s) suivant le patient — même EXISTS que list_cabinet_conversations,
    // sinon accès direct par :id contourne le filtre appliqué sur la liste.
    sqlx::query(
        "SELECT 1 FROM conversation WHERE id = $1 AND cabinet_id = $2 \
         AND (scope != 'clinical' OR $3 != 'secretary') \
         AND (scope != 'platform_support' OR $3 = 'admin') \
         AND ($3 != 'secretary' OR EXISTS ( \
             SELECT 1 FROM appointment a \
             JOIN provider pr ON pr.practitioner_id = a.practitioner_id \
             JOIN provider_secretariat ps ON ps.provider_id = pr.id \
             WHERE a.patient_id = conversation.patient_id \
               AND a.deleted_at IS NULL \
               AND ps.active = true \
               AND ps.secretariat_id = $4 \
         ))",
    )
    .bind(conversation_id)
    .bind(claims.cabinet_id)
    .bind(&claims.role)
    .bind(claims.secretariat_id)
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
            Ok(CabinetMessageItem {
                id: row.try_get("id").map_err(|_| AppError::Internal)?,
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

    Ok(Json(CabinetMessagesResponse { data }))
}

/// `POST /v1/cabinet/conversations/:id/messages` — réponse du cabinet dans un
/// fil patient (#3238). Secrétaire et praticien (`sender_kind` dérivé du rôle).
///
/// `cabinet_id` extrait du JWT (invariant tenancy), RLS `tenant_isolation`.
/// Conversation hors tenant → 404. Body vide → 422.
/// Chiffrement POC : `body_ciphertext` = UTF-8 brut (NUB-T3 pour le réel).
/// Publie `message_created` sur le canal WS `conversation:<id>`.
pub async fn send_cabinet_message(
    State(state): State<AppState>,
    axum::Extension(hub): axum::Extension<std::sync::Arc<crate::realtime::WsHub>>,
    claims: ProSecretaryPlusClaims,
    Path(conversation_id): Path<Uuid>,
    Json(body): Json<SendCabinetMessageBody>,
) -> Result<(StatusCode, Json<SendCabinetMessageResponse>), AppError> {
    if body.body.trim().is_empty() {
        return Err(AppError::ValidationError);
    }
    let sender_kind = if claims.role == "secretary" {
        "secretary"
    } else {
        "practitioner"
    };

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Conversation du cabinet uniquement (RLS + garde explicite), hors fils
    // cliniques pour un secrétaire (§07 §4.1) et hors fil de support
    // admin↔plateforme pour tout rôle non-admin (#4843).
    // R10 (#5715) : pour une secrétaire, cloisonnement au secrétariat rattaché
    // au(x) praticien(s) suivant le patient — même EXISTS que list_cabinet_conversations,
    // sinon accès direct par :id contourne le filtre appliqué sur la liste.
    sqlx::query(
        "SELECT 1 FROM conversation WHERE id = $1 AND cabinet_id = $2 \
         AND (scope != 'clinical' OR $3 != 'secretary') \
         AND (scope != 'platform_support' OR $3 = 'admin') \
         AND ($3 != 'secretary' OR EXISTS ( \
             SELECT 1 FROM appointment a \
             JOIN provider pr ON pr.practitioner_id = a.practitioner_id \
             JOIN provider_secretariat ps ON ps.provider_id = pr.id \
             WHERE a.patient_id = conversation.patient_id \
               AND a.deleted_at IS NULL \
               AND ps.active = true \
               AND ps.secretariat_id = $4 \
         ))",
    )
    .bind(conversation_id)
    .bind(claims.cabinet_id)
    .bind(&claims.role)
    .bind(claims.secretariat_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let row = sqlx::query(
        "INSERT INTO message \
         (cabinet_id, conversation_id, sender_kind, sender_id, \
          body_ciphertext, body_key_ref, triage_flag) \
         VALUES ($1, $2, $3, $4, $5, 'poc-stub', 'normal') \
         RETURNING id, created_at",
    )
    .bind(claims.cabinet_id)
    .bind(conversation_id)
    .bind(sender_kind)
    .bind(claims.sub)
    .bind(body.body.as_bytes())
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let message_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Temps réel : notifie le patient abonné au fil — #3238.
    let channel = format!("conversation:{conversation_id}");
    hub.publish_named(
        &channel,
        serde_json::json!({
            "channel": channel,
            "event": "message_created",
            "data": { "message_id": message_id, "sender_kind": sender_kind }
        })
        .to_string(),
    );

    Ok((
        StatusCode::CREATED,
        Json(SendCabinetMessageResponse {
            message_id,
            id: message_id,
            body: body.body,
            sender: sender_kind.to_string(),
            sender_kind: sender_kind.to_string(),
            created_at: created_at.to_rfc3339(),
            read_at: None,
        }),
    ))
}

// ── POST /v1/cabinet/conversations/:id/read ──────────────────────────────────

/// `POST /v1/cabinet/conversations/:id/read` — marque les messages patient du
/// fil comme lus par le cabinet (#3238). Publie `read` sur le canal WS
/// `conversation:<id>` (double coche côté patient). Conversation hors tenant → 404.
pub async fn mark_cabinet_conversation_read(
    State(state): State<AppState>,
    axum::Extension(hub): axum::Extension<std::sync::Arc<crate::realtime::WsHub>>,
    claims: ProSecretaryPlusClaims,
    Path(conversation_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Conversation du cabinet, hors fils cliniques pour un secrétaire (§07 §4.1)
    // et hors fil de support admin↔plateforme pour tout rôle non-admin (#4843).
    // R10 (#5715) : pour une secrétaire, cloisonnement au secrétariat rattaché
    // au(x) praticien(s) suivant le patient — même EXISTS que list_cabinet_conversations,
    // sinon accès direct par :id contourne le filtre appliqué sur la liste.
    sqlx::query(
        "SELECT 1 FROM conversation WHERE id = $1 AND cabinet_id = $2 \
         AND (scope != 'clinical' OR $3 != 'secretary') \
         AND (scope != 'platform_support' OR $3 = 'admin') \
         AND ($3 != 'secretary' OR EXISTS ( \
             SELECT 1 FROM appointment a \
             JOIN provider pr ON pr.practitioner_id = a.practitioner_id \
             JOIN provider_secretariat ps ON ps.provider_id = pr.id \
             WHERE a.patient_id = conversation.patient_id \
               AND a.deleted_at IS NULL \
               AND ps.active = true \
               AND ps.secretariat_id = $4 \
         ))",
    )
    .bind(conversation_id)
    .bind(claims.cabinet_id)
    .bind(&claims.role)
    .bind(claims.secretariat_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    sqlx::query(
        "UPDATE message SET read_at = now() \
         WHERE conversation_id = $1 AND cabinet_id = $2 \
           AND sender_kind = 'patient' AND read_at IS NULL",
    )
    .bind(conversation_id)
    .bind(claims.cabinet_id)
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
            "data": { "conversation_id": conversation_id, "by": "cabinet" }
        })
        .to_string(),
    );

    Ok(StatusCode::NO_CONTENT)
}
