//! Handlers `/v1/notifications` — centre de notifications in-app.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
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
    /// Métadonnées d'action non-PII (type, deeplink, ids) — cf. migration 0053.
    /// Toujours renvoyées : contrairement à `body`, `data` n'est jamais chiffrée.
    pub data: serde_json::Value,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deep_link: Option<String>,
    pub is_read: bool,
    pub created_at: String,
}

/// Dérive le deep-link relatif d'une notification à partir de son `kind` et
/// de son `data`, pour les kinds dont le front a déjà une route établie
/// (cf. `NotificationDeepLinkHandler._resolveRoute`,
/// front/apps/app_patient/lib/features/notifications). `None` pour les
/// autres kinds plutôt que d'inventer une route qui n'existe pas encore
/// (ex. `waiting_list_slot_offered` : pas de page de détail patient, #3863).
fn derive_deep_link(kind: &str, data: &serde_json::Value) -> Option<String> {
    match kind {
        "order_received"
        | "order_status_changed"
        | "pharmacy_order_preparing"
        | "pharmacy_order_ready"
        | "pharmacy_order_picked_up" => {
            let id = data.get("order_id")?.as_str()?;
            Some(format!("/pharmacy/orders/{id}"))
        }
        "waiting_room_called"
        | "appointment_confirmed"
        | "appointment_rescheduled"
        | "appointment_motif_changed" => {
            let id = data.get("appointment_id")?.as_str()?;
            Some(format!("/appointments/{id}"))
        }
        _ => None,
    }
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
/// `data` (JSONB non-PII) et `deep_link` dérivé sont eux toujours restitués (#3863) —
/// `data` n'a jamais été chiffrée, aucune raison de la filtrer en attendant NUB-T3.
/// Pas de PII dans les logs.
pub async fn list_notifications(
    State(state): State<AppState>,
    claims: MeClaims,
    Query(params): Query<ListNotificationsQuery>,
) -> Result<Json<NotificationsResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    // `cursor` absent → pas de pagination (None). `cursor` présent mais
    // indécodable → 422, pas silencieusement ignoré (#3874) : avant ce fix,
    // .and_then() confondait les deux cas et retombait sur la page 1, un
    // client paginant jusqu'à next_cursor==null bouclait indéfiniment sur un
    // curseur corrompu/expiré.
    let cursor = match params.cursor.as_deref() {
        Some(s) => Some(decode_cursor(s).ok_or(AppError::ValidationError)?),
        None => None,
    };
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
        "SELECT id, kind, title, data, is_read, created_at \
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
        let item_data: serde_json::Value = row.try_get("data").map_err(|_| AppError::Internal)?;
        let is_read: bool = row.try_get("is_read").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        // Déchiffrement KMS (core/crypto NUB-T3) — non implémenté → body null.
        let body: Option<String> = None;
        let deep_link = derive_deep_link(&kind, &item_data);

        last_created_at = Some(created_at);
        last_id = Some(id);

        data.push(NotificationItem {
            id,
            kind,
            title,
            body,
            data: item_data,
            deep_link,
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

/// Réponse de `POST /v1/notifications/:id/read`.
#[derive(Serialize)]
pub struct NotificationDto {
    pub id: Uuid,
    pub kind: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub body: Option<String>,
    pub is_read: bool,
    pub created_at: String,
    pub read_at: Option<String>,
}

/// Réponse de `POST /v1/notifications/read-all`.
#[derive(Serialize)]
pub struct MarkAllReadResponse {
    pub updated: u64,
}

/// `POST /v1/notifications/:id/read` — marque une notification comme lue.
///
/// RLS `notification_owner_update` : seule la notification du porteur du token est accessible.
/// Retourne 404 si la notification n'appartient pas à l'utilisateur courant.
pub async fn mark_notification_read(
    State(state): State<AppState>,
    claims: MeClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<NotificationDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // read_at = COALESCE(read_at, now()) : relire une notification déjà lue ne
    // doit pas réécrire l'horodatage de première lecture (#3884, non idempotent
    // avant ce fix — même classe que #3876 sur consent.granted_at).
    let row = sqlx::query(
        "UPDATE notification \
         SET is_read = true, read_at = COALESCE(read_at, now()) \
         WHERE id = $1 AND app_user_id = $2 \
         RETURNING id, kind, title, is_read, created_at, read_at",
    )
    .bind(id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let notification_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let kind: String = row.try_get("kind").map_err(|_| AppError::Internal)?;
    let title: String = row.try_get("title").map_err(|_| AppError::Internal)?;
    let is_read: bool = row.try_get("is_read").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    let read_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("read_at").map_err(|_| AppError::Internal)?;

    Ok(Json(NotificationDto {
        id: notification_id,
        kind,
        title,
        body: None,
        is_read,
        created_at: created_at.to_rfc3339(),
        read_at: read_at.map(|dt| dt.to_rfc3339()),
    }))
}

/// `POST /v1/notifications/read-all` — marque toutes les notifications non-lues comme lues.
///
/// RLS `notification_owner_update` : scope sur `app.current_user_id`.
/// Retourne `{ updated: <count> }`.
pub async fn mark_all_notifications_read(
    State(state): State<AppState>,
    claims: MeClaims,
) -> Result<(StatusCode, Json<MarkAllReadResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let result = sqlx::query(
        "UPDATE notification \
         SET is_read = true, read_at = now() \
         WHERE app_user_id = $1 AND is_read = false",
    )
    .bind(claims.sub)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let updated = result.rows_affected();

    tracing::info!(user_id = %claims.sub, updated, "notifications marked all read");

    Ok((StatusCode::OK, Json(MarkAllReadResponse { updated })))
}

/// Corps de la requête `PATCH /v1/me/notification-preferences`.
///
/// `deny_unknown_fields` : même garde-fou que
/// `PatchNotificationPreferencesBody` (auth/mod.rs) — une clé inconnue ne
/// doit jamais être acceptée silencieusement (opt-out perdu sans le savoir).
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchMeNotificationPreferencesBody {
    inapp_rdv: Option<bool>,
    inapp_messagerie: Option<bool>,
    inapp_devis: Option<bool>,
    inapp_stock: Option<bool>,
    inapp_labo: Option<bool>,
    inapp_visites: Option<bool>,
    email_rdv: Option<bool>,
    email_messagerie: Option<bool>,
    email_devis: Option<bool>,
}

/// Réponse de `GET/PATCH /v1/me/notification-preferences`.
#[derive(Serialize)]
pub struct MeNotificationPreferencesResponse {
    inapp_rdv: bool,
    inapp_messagerie: bool,
    inapp_devis: bool,
    inapp_stock: bool,
    inapp_labo: bool,
    inapp_visites: bool,
    email_rdv: bool,
    email_messagerie: bool,
    email_devis: bool,
}

impl MeNotificationPreferencesResponse {
    /// Défauts avant la première ligne en base : in-app ON, email OFF (#6257).
    const fn defaults() -> Self {
        Self {
            inapp_rdv: true,
            inapp_messagerie: true,
            inapp_devis: true,
            inapp_stock: true,
            inapp_labo: true,
            inapp_visites: true,
            email_rdv: false,
            email_messagerie: false,
            email_devis: false,
        }
    }

    fn from_row(row: &sqlx::postgres::PgRow) -> Result<Self, AppError> {
        Ok(Self {
            inapp_rdv: row.try_get("inapp_rdv").map_err(|_| AppError::Internal)?,
            inapp_messagerie: row
                .try_get("inapp_messagerie")
                .map_err(|_| AppError::Internal)?,
            inapp_devis: row.try_get("inapp_devis").map_err(|_| AppError::Internal)?,
            inapp_stock: row.try_get("inapp_stock").map_err(|_| AppError::Internal)?,
            inapp_labo: row.try_get("inapp_labo").map_err(|_| AppError::Internal)?,
            inapp_visites: row
                .try_get("inapp_visites")
                .map_err(|_| AppError::Internal)?,
            email_rdv: row.try_get("email_rdv").map_err(|_| AppError::Internal)?,
            email_messagerie: row
                .try_get("email_messagerie")
                .map_err(|_| AppError::Internal)?,
            email_devis: row.try_get("email_devis").map_err(|_| AppError::Internal)?,
        })
    }
}

/// `GET /v1/me/notification-preferences` — retourne les préférences de notification
/// du porteur du token (patient, pro, pharma ou nurse).
///
/// Si aucune ligne dans `user_notification_preference` → défauts (in-app `true`, email `false`).
/// RLS scoped par `app.current_user_id` (migration 0246).
pub async fn get_me_notification_preferences(
    State(state): State<AppState>,
    claims: MeClaims,
) -> Result<Json<MeNotificationPreferencesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT inapp_rdv, inapp_messagerie, inapp_devis, inapp_stock, inapp_labo, inapp_visites, \
                email_rdv, email_messagerie, email_devis \
         FROM user_notification_preference \
         WHERE app_user_id = $1",
    )
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let prefs = match &row {
        None => MeNotificationPreferencesResponse::defaults(),
        Some(r) => MeNotificationPreferencesResponse::from_row(r)?,
    };

    tracing::info!(user_id = %claims.sub, "me notification preferences queried");

    Ok(Json(prefs))
}

/// `PATCH /v1/me/notification-preferences` — met à jour partiellement les opt-in.
///
/// Upsert idempotent : seuls les champs présents dans le body sont modifiés,
/// les autres conservent leur valeur existante (ou le défaut à la création).
/// RLS scoped par `app.current_user_id` (migration 0246).
pub async fn patch_me_notification_preferences(
    State(state): State<AppState>,
    claims: MeClaims,
    Json(body): Json<PatchMeNotificationPreferencesBody>,
) -> Result<Json<MeNotificationPreferencesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO user_notification_preference \
           (app_user_id, inapp_rdv, inapp_messagerie, inapp_devis, inapp_stock, inapp_labo, inapp_visites, \
            email_rdv, email_messagerie, email_devis) \
         VALUES ($1, \
           COALESCE($2, true), COALESCE($3, true), COALESCE($4, true), COALESCE($5, true), \
           COALESCE($6, true), COALESCE($7, true), \
           COALESCE($8, false), COALESCE($9, false), COALESCE($10, false)) \
         ON CONFLICT (app_user_id) \
         DO UPDATE SET \
           inapp_rdv        = CASE WHEN $2 IS NOT NULL THEN $2 \
                                   ELSE user_notification_preference.inapp_rdv END, \
           inapp_messagerie = CASE WHEN $3 IS NOT NULL THEN $3 \
                                   ELSE user_notification_preference.inapp_messagerie END, \
           inapp_devis      = CASE WHEN $4 IS NOT NULL THEN $4 \
                                   ELSE user_notification_preference.inapp_devis END, \
           inapp_stock      = CASE WHEN $5 IS NOT NULL THEN $5 \
                                   ELSE user_notification_preference.inapp_stock END, \
           inapp_labo       = CASE WHEN $6 IS NOT NULL THEN $6 \
                                   ELSE user_notification_preference.inapp_labo END, \
           inapp_visites    = CASE WHEN $7 IS NOT NULL THEN $7 \
                                   ELSE user_notification_preference.inapp_visites END, \
           email_rdv        = CASE WHEN $8 IS NOT NULL THEN $8 \
                                   ELSE user_notification_preference.email_rdv END, \
           email_messagerie = CASE WHEN $9 IS NOT NULL THEN $9 \
                                   ELSE user_notification_preference.email_messagerie END, \
           email_devis      = CASE WHEN $10 IS NOT NULL THEN $10 \
                                   ELSE user_notification_preference.email_devis END, \
           updated_at       = now() \
         RETURNING inapp_rdv, inapp_messagerie, inapp_devis, inapp_stock, inapp_labo, inapp_visites, \
                   email_rdv, email_messagerie, email_devis",
    )
    .bind(claims.sub)
    .bind(body.inapp_rdv)
    .bind(body.inapp_messagerie)
    .bind(body.inapp_devis)
    .bind(body.inapp_stock)
    .bind(body.inapp_labo)
    .bind(body.inapp_visites)
    .bind(body.email_rdv)
    .bind(body.email_messagerie)
    .bind(body.email_devis)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let prefs = MeNotificationPreferencesResponse::from_row(&row)?;

    tracing::info!(user_id = %claims.sub, "me notification preferences updated");

    Ok(Json(prefs))
}
