//! Handlers `/v1/cabinet/messages` — messagerie interne d'équipe (staff↔staff),
//! distincte de la messagerie patient (`cabinet_messaging.rs`, table `conversation`/
//! `message`). Table `cabinet_messages` (migration 0106), jusqu'ici sans route
//! API (#4156, différentiel Desmos [D]).
//!
//! Fil unique par cabinet (pas de conversations/destinataires — tout le
//! staff voit tous les messages), cohérent avec le schéma minimal de la
//! table (`sender_id`, `body`, pas de `recipient_id`/`thread_id`).

use axum::{
    extract::{Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Un message interne d'équipe.
#[derive(Serialize)]
pub struct CabinetTeamMessageItem {
    pub id: Uuid,
    pub sender_id: Uuid,
    /// `provider.display_name` du praticien émetteur, sinon son email si
    /// visible (RLS `app_user` self-only, #4416 — souvent indisponible pour
    /// un collègue), sinon `"Membre du cabinet"` (le secrétariat/admin n'a
    /// pas de fiche `provider`).
    pub sender_name: String,
    pub body: String,
    pub created_at: String,
}

/// Réponse de `GET /v1/cabinet/messages`.
#[derive(Serialize)]
pub struct ListCabinetTeamMessagesResponse {
    pub data: Vec<CabinetTeamMessageItem>,
}

/// Query de `GET /v1/cabinet/messages`.
#[derive(Deserialize)]
pub struct ListCabinetTeamMessagesQuery {
    pub limit: Option<i64>,
}

/// `GET /v1/cabinet/messages` — fil des messages internes du cabinet (#4156).
///
/// Tout membre du staff (`ProSecretaryPlusClaims` : secretary/practitioner/
/// admin/manager) — patient → 403. `cabinet_id` extrait du JWT, jamais du
/// path/query (invariant tenancy). RLS tenant-scoped via
/// `app.current_cabinet_id`. Tri `created_at ASC` (fil chronologique),
/// `limit` 1..=200 (défaut 100).
pub async fn list_cabinet_team_messages(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(query): Query<ListCabinetTeamMessagesQuery>,
) -> Result<Json<ListCabinetTeamMessagesResponse>, AppError> {
    let limit = query.limit.unwrap_or(100).clamp(1, 200);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // #4416 : `app_user` porte une RLS stricte self-only (user_self_select,
    // 0045_platform_rls.sql — `id = app.current_user_id`), donc INVISIBLE
    // pour tout sender autre que le viewer lui-même — un INNER JOIN dessus
    // éliminait TOUTES les lignes (liste toujours vide, messagerie
    // write-only). Positionner le GUC au viewer courant permet au moins de
    // résoudre SON PROPRE email dans le fil (cas fréquent : on relit ce
    // qu'on vient d'envoyer) ; RLS ne peut pas être élargie à "tout le
    // cabinet" sans une policy dédiée (hors périmètre de ce fix).
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // LEFT JOIN (pas INNER) : `au` reste NULL pour les collègues (RLS
    // toujours self-only), d'où le dernier fallback littéral dans le
    // COALESCE pour ne jamais planter sur `sender_name` (colonne NOT NULL).
    let rows = sqlx::query(
        "SELECT cm.id, cm.sender_id, cm.body, cm.created_at, \
                COALESCE(prov.display_name, au.email::text, 'Membre du cabinet') AS sender_name \
         FROM cabinet_messages cm \
         LEFT JOIN app_user au ON au.id = cm.sender_id \
         LEFT JOIN practitioner p ON p.user_id = cm.sender_id AND p.cabinet_id = cm.cabinet_id \
         LEFT JOIN provider prov ON prov.practitioner_id = p.id AND prov.cabinet_id = cm.cabinet_id \
         WHERE cm.cabinet_id = $1 AND cm.deleted_at IS NULL \
         ORDER BY cm.created_at ASC \
         LIMIT $2",
    )
    .bind(claims.cabinet_id)
    .bind(limit)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .into_iter()
        .map(|r| {
            let created_at: chrono::DateTime<chrono::Utc> =
                r.try_get("created_at").map_err(|_| AppError::Internal)?;
            Ok(CabinetTeamMessageItem {
                id: r.try_get("id").map_err(|_| AppError::Internal)?,
                sender_id: r.try_get("sender_id").map_err(|_| AppError::Internal)?,
                sender_name: r.try_get("sender_name").map_err(|_| AppError::Internal)?,
                body: r.try_get("body").map_err(|_| AppError::Internal)?,
                created_at: created_at.to_rfc3339(),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(ListCabinetTeamMessagesResponse { data }))
}

/// Corps de `POST /v1/cabinet/messages`.
#[derive(Deserialize)]
pub struct SendCabinetTeamMessageBody {
    pub body: String,
}

/// Réponse de `POST /v1/cabinet/messages`.
#[derive(Serialize)]
pub struct SendCabinetTeamMessageResponse {
    pub id: Uuid,
}

/// `POST /v1/cabinet/messages` — envoie un message interne d'équipe (#4156).
///
/// Tout membre du staff (`ProSecretaryPlusClaims`) — patient → 403.
/// `body` vide/blanc → 422. `cabinet_id`/`sender_id` extraits du JWT.
/// Réponse `201 { id }`.
pub async fn send_cabinet_team_message(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<SendCabinetTeamMessageBody>,
) -> Result<(StatusCode, Json<SendCabinetTeamMessageResponse>), AppError> {
    let text = body.body.trim().to_string();
    if text.is_empty() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO cabinet_messages (cabinet_id, sender_id, body) \
         VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&text)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        sender_id = %claims.sub,
        message_id = %id,
        "cabinet team message sent"
    );

    Ok((
        StatusCode::CREATED,
        Json(SendCabinetTeamMessageResponse { id }),
    ))
}
