//! `PATCH /v1/cabinet/conversations/:id` — qualification d'une conversation
//! (#7151, doc12 §18 : inbox secrétariat) : origine, motif, priorité,
//! assignation, statut, synthèse (colonnes ajoutées par la migration 0298,
//! #7152).
//!
//! Module dédié plutôt qu'une extension de `cabinet_messaging.rs` (proche du
//! plafond de confort CLAUDE.md, ~700 lignes — même doctrine que
//! `cabinet_quotes_patch.rs` extrait de `cabinet_quotes.rs`).

use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    cabinet_messaging::{
        VALID_CONVERSATION_ORIGINS, VALID_CONVERSATION_PRIORITIES, VALID_CONVERSATION_STATUSES,
    },
    AppState,
};

/// Corps de `PATCH /v1/cabinet/conversations/:id`. Champ absent = inchangé —
/// pas de moyen de remettre `assignee_user_id`/`motif`/`summary` à `null` par
/// ce biais (même limite documentée que `cabinet_tasks.rs::PatchCabinetTaskBody`).
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchConversationQualificationBody {
    pub origin: Option<String>,
    pub motif: Option<String>,
    pub priority: Option<String>,
    pub assignee_user_id: Option<Uuid>,
    pub status: Option<String>,
    pub summary: Option<String>,
}

/// Réponse de `PATCH /v1/cabinet/conversations/:id`.
#[derive(Serialize)]
pub struct PatchConversationQualificationResponse {
    pub id: Uuid,
    pub origin: Option<String>,
    pub motif: Option<String>,
    pub priority: Option<String>,
    pub assignee_user_id: Option<Uuid>,
    pub status: String,
    pub summary: Option<String>,
}

/// `PATCH /v1/cabinet/conversations/:id` — qualifie une conversation cabinet.
///
/// Token pro requis (secretary, practitioner, admin). `cabinet_id` extrait du
/// JWT, RLS scopée via `app.current_cabinet_id`. Conversation hors tenant, ou
/// fil clinique consulté par un secrétaire (§07 §4.1), ou fil de support
/// admin↔plateforme pour un non-admin (#4843) → `404` — même garde que
/// `cabinet_messaging::{get,send,read}_cabinet_conversation*`.
/// R10 (#5715) : pour une secrétaire, cloisonnement au secrétariat rattaché
/// au(x) praticien(s) suivant le patient.
/// `status`/`priority`/`origin` hors énum → `422`. `assignee_user_id` fourni
/// mais absent du cabinet (`cabinet_membership`) → `404` (même doctrine que
/// `cabinet_tasks::validate_task_refs`).
/// Insère une entrée `audit_log` (`entity = 'conversation'`).
pub async fn patch_cabinet_conversation(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(conversation_id): Path<Uuid>,
    Json(body): Json<PatchConversationQualificationBody>,
) -> Result<Json<PatchConversationQualificationResponse>, AppError> {
    if let Some(ref origin) = body.origin {
        if !VALID_CONVERSATION_ORIGINS.contains(&origin.as_str()) {
            return Err(AppError::ValidationError);
        }
    }
    if let Some(ref priority) = body.priority {
        if !VALID_CONVERSATION_PRIORITIES.contains(&priority.as_str()) {
            return Err(AppError::ValidationError);
        }
    }
    if let Some(ref status) = body.status {
        if !VALID_CONVERSATION_STATUSES.contains(&status.as_str()) {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if let Some(user_id) = body.assignee_user_id {
        let exists =
            sqlx::query("SELECT 1 FROM cabinet_membership WHERE cabinet_id = $1 AND user_id = $2")
                .bind(claims.cabinet_id)
                .bind(user_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    // Conversation du cabinet, hors fils cliniques pour un secrétaire (§07 §4.1)
    // et hors fil de support admin↔plateforme pour tout rôle non-admin (#4843).
    // R10 (#5715) : pour une secrétaire, cloisonnement au secrétariat rattaché
    // au(x) praticien(s) suivant le patient — même EXISTS que
    // `cabinet_messaging::list_cabinet_conversations`.
    let current = sqlx::query(
        "SELECT origin, motif, priority, assignee_user_id, status, summary \
         FROM conversation WHERE id = $1 AND cabinet_id = $2 \
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

    let existing_origin: Option<String> =
        current.try_get("origin").map_err(|_| AppError::Internal)?;
    let existing_motif: Option<String> =
        current.try_get("motif").map_err(|_| AppError::Internal)?;
    let existing_priority: Option<String> = current
        .try_get("priority")
        .map_err(|_| AppError::Internal)?;
    let existing_assignee: Option<Uuid> = current
        .try_get("assignee_user_id")
        .map_err(|_| AppError::Internal)?;
    let existing_status: String = current.try_get("status").map_err(|_| AppError::Internal)?;
    let existing_summary: Option<String> =
        current.try_get("summary").map_err(|_| AppError::Internal)?;

    let new_origin = body.origin.or(existing_origin);
    let new_motif = body.motif.or(existing_motif);
    let new_priority = body.priority.or(existing_priority);
    let new_assignee = body.assignee_user_id.or(existing_assignee);
    let new_status = body.status.unwrap_or(existing_status);
    let new_summary = body.summary.or(existing_summary);

    sqlx::query(
        "UPDATE conversation \
         SET origin = $1, motif = $2, priority = $3, assignee_user_id = $4, \
             status = $5, summary = $6 \
         WHERE id = $7 AND cabinet_id = $8",
    )
    .bind(&new_origin)
    .bind(&new_motif)
    .bind(&new_priority)
    .bind(new_assignee)
    .bind(&new_status)
    .bind(&new_summary)
    .bind(conversation_id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'update_conversation_qualification', 'conversation', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(conversation_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        role = %claims.role,
        conversation_id = %conversation_id,
        "cabinet conversation qualification updated"
    );

    Ok(Json(PatchConversationQualificationResponse {
        id: conversation_id,
        origin: new_origin,
        motif: new_motif,
        priority: new_priority,
        assignee_user_id: new_assignee,
        status: new_status,
        summary: new_summary,
    }))
}
