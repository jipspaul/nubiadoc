//! Handlers `/v1/cabinet/messages` — messagerie interne d'équipe (staff↔staff),
//! distincte de la messagerie patient (`cabinet_messaging.rs`, table `conversation`/
//! `message`). Table `cabinet_messages` (migration 0106), jusqu'ici sans route
//! API (#4156, différentiel Desmos [D]).
//!
//! Fil unique par cabinet (pas de conversations/destinataires — tout le
//! staff voit tous les messages), cohérent avec le schéma minimal de la
//! table (`sender_id`, `body`, pas de `recipient_id`/`thread_id`).

use std::collections::HashMap;

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

/// Libellé humain (design-v2) pour un `cabinet_membership.role` (#6543).
/// `None` pour un rôle inconnu/absent (sender ayant quitté le cabinet) :
/// le front n'affiche alors pas de pastille.
fn role_label(role: &str) -> &'static str {
    match role {
        "practitioner" | "doctor" => "Praticien",
        "secretary" => "Secrétaire",
        "manager" => "Manager",
        "admin" => "Administrateur",
        _ => "Membre du cabinet",
    }
}

/// Un message interne d'équipe.
#[derive(Serialize)]
pub struct CabinetTeamMessageItem {
    pub id: Uuid,
    pub sender_id: Uuid,
    /// `provider.display_name` du praticien émetteur, sinon prénom/nom
    /// (`app_user`, #6543 — RLS self-only contournée via `current_user_id`
    /// positionné par sender comme dans `get_cabinet_members`), sinon
    /// `"Membre du cabinet"`.
    pub sender_name: String,
    /// Libellé de rôle (#6543, pastille design-v2) — `None` si le sender n'a
    /// plus de `cabinet_membership` actif dans ce cabinet.
    pub sender_role: Option<String>,
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

    // `provider.display_name` couvre les praticiens ; `cabinet_membership`
    // donne le rôle pour la pastille (#6543). Le nom des non-praticiens
    // (secrétariat/admin) est résolu ensuite via `app_user`, ligne par ligne
    // (cf. boucle ci-dessous).
    let rows = sqlx::query(
        "SELECT cm.id, cm.sender_id, cm.body, cm.created_at, \
                prov.display_name AS provider_display_name, \
                cmb.role AS sender_role \
         FROM cabinet_messages cm \
         LEFT JOIN practitioner p ON p.user_id = cm.sender_id AND p.cabinet_id = cm.cabinet_id \
         LEFT JOIN provider prov ON prov.practitioner_id = p.id AND prov.cabinet_id = cm.cabinet_id \
         LEFT JOIN cabinet_membership cmb ON cmb.user_id = cm.sender_id AND cmb.cabinet_id = cm.cabinet_id \
         WHERE cm.cabinet_id = $1 AND cm.deleted_at IS NULL \
         ORDER BY cm.created_at ASC \
         LIMIT $2",
    )
    .bind(claims.cabinet_id)
    .bind(limit)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // #4416/#6543 : `app_user` porte une RLS stricte self-only
    // (user_self_select, 0045_platform_rls.sql — `id = app.current_user_id`),
    // donc invisible pour tout sender autre que le viewer courant. Même
    // contournement que `get_cabinet_members` : on repositionne le GUC par
    // sender avant de lire son nom, avec un cache pour ne le faire qu'une
    // fois par auteur distinct du fil.
    let mut resolved_names: HashMap<Uuid, String> = HashMap::new();
    for sender_id in rows
        .iter()
        .map(|r| r.try_get::<Uuid, _>("sender_id"))
        .collect::<Result<Vec<_>, _>>()
        .map_err(|_| AppError::Internal)?
    {
        if resolved_names.contains_key(&sender_id) {
            continue;
        }

        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(sender_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let user_row = sqlx::query(
            "SELECT first_name, last_name, email FROM app_user WHERE id = $1",
        )
        .bind(sender_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        if let Some(row) = user_row {
            let first_name: Option<String> =
                row.try_get("first_name").map_err(|_| AppError::Internal)?;
            let last_name: Option<String> =
                row.try_get("last_name").map_err(|_| AppError::Internal)?;
            let email: String = row.try_get("email").map_err(|_| AppError::Internal)?;

            let full_name = [first_name, last_name]
                .into_iter()
                .flatten()
                .collect::<Vec<_>>()
                .join(" ");
            let name = if full_name.trim().is_empty() {
                email
            } else {
                full_name
            };
            resolved_names.insert(sender_id, name);
        }
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .into_iter()
        .map(|r| {
            let created_at: chrono::DateTime<chrono::Utc> =
                r.try_get("created_at").map_err(|_| AppError::Internal)?;
            let sender_id: Uuid = r.try_get("sender_id").map_err(|_| AppError::Internal)?;
            let provider_display_name: Option<String> = r
                .try_get("provider_display_name")
                .map_err(|_| AppError::Internal)?;
            let role: Option<String> =
                r.try_get("sender_role").map_err(|_| AppError::Internal)?;

            let sender_name = provider_display_name
                .or_else(|| resolved_names.get(&sender_id).cloned())
                .unwrap_or_else(|| "Membre du cabinet".to_string());

            Ok(CabinetTeamMessageItem {
                id: r.try_get("id").map_err(|_| AppError::Internal)?,
                sender_id,
                sender_name,
                sender_role: role.map(|role| role_label(&role).to_string()),
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
    // #4410 : NUL byte non filtré → bind Postgres échoue, masqué en 500.
    crate::text_validation::reject_nul_byte(&text)?;

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
