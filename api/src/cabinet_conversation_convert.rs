//! Handler `POST /v1/cabinet/conversations/:id/convert-to-appointment` (#4159,
//! doc12 §18 US-S07) — pilier différenciant messagerie → RDV, spec'é E4.4
//! mais jamais implémenté jusqu'ici.
//!
//! Module dédié plutôt qu'une extension de `cabinet_messaging.rs` (596 lignes,
//! déjà proche du seuil de confort CLAUDE.md) ou de `scheduling.rs` (2506
//! lignes, largement au-dessus du plafond absolu — ne pas y toucher). Réutilise
//! le pattern `create_cabinet_appointment` (résolution `slot_id` →
//! `availability_slot`, contrainte d'exclusion DB → `409 slot_taken`).

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::{Extension, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use std::sync::Arc;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Corps de `POST /v1/cabinet/conversations/:id/convert-to-appointment`.
///
/// `patient_id`/`cabinet_id`/`motif` sont déduits du fil (conversation +
/// dernier message) — "1 clic" (US-S07) : seul le créneau reste à choisir,
/// un RDV réel ne peut pas être auto-assigné sans horaire (contrainte DB
/// `appointment_no_overlap`, `starts_at`/`ends_at`/`practitioner_id` NOT NULL).
#[derive(Deserialize)]
pub struct ConvertConversationBody {
    pub slot_id: Uuid,
}

/// Réponse de `POST /v1/cabinet/conversations/:id/convert-to-appointment`.
#[derive(Serialize)]
pub struct ConvertConversationResponse {
    pub appointment_id: Uuid,
    pub status: String,
}

fn is_exclusion_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23P01")
    )
}

/// `POST /v1/cabinet/conversations/:id/convert-to-appointment` — convertit une
/// conversation en RDV.
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`.
/// Conversation hors tenant, ou fil clinique consulté par un secrétaire
/// (§07 §4.1) → `404`. `patient_id` déduit de la conversation, `motif` déduit
/// du dernier message du fil (`null` si aucun message).
/// `slot_id` résolu depuis `availability_slot` (doit être `open`, du cabinet)
/// → `404` sinon ; contrainte d'exclusion DB (double-booking praticien) →
/// `409 slot_taken`.
/// Statut initial `requested`. Insère une entrée `audit_log` (`entity =
/// 'conversation'`, `entity_id = conversation_id`, `metadata.appointment_id`)
/// pour tracer la conversion depuis le fil d'origine.
pub async fn convert_conversation_to_appointment(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<crate::realtime::WsHub>>,
    claims: ProSecretaryPlusClaims,
    Path(conversation_id): Path<Uuid>,
    Json(body): Json<ConvertConversationBody>,
) -> Result<(StatusCode, Json<ConvertConversationResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Conversation du cabinet, hors fils cliniques pour un secrétaire
    // (§07 §4.1) — déduit patient_id du fil.
    let conv_row = sqlx::query(
        "SELECT patient_id FROM conversation WHERE id = $1 AND cabinet_id = $2 \
         AND (scope != 'clinical' OR $3 != 'secretary')",
    )
    .bind(conversation_id)
    .bind(claims.cabinet_id)
    .bind(&claims.role)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let patient_id: Uuid = conv_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

    // Motif pré-rempli depuis le dernier message du fil (POC chiffrement :
    // UTF-8 brut, comme cabinet_messaging::get_cabinet_conversation_messages).
    let last_message_row = sqlx::query(
        "SELECT body_ciphertext FROM message WHERE conversation_id = $1 \
         ORDER BY created_at DESC, id DESC LIMIT 1",
    )
    .bind(conversation_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let motif: Option<String> = last_message_row
        .map(|row| row.try_get::<Vec<u8>, _>("body_ciphertext"))
        .transpose()
        .map_err(|_| AppError::Internal)?
        .map(|bytes| String::from_utf8_lossy(&bytes).into_owned());

    // Résout le créneau pour starts_at / ends_at / practitioner_id (même
    // pattern que scheduling::create_cabinet_appointment).
    // #4399 : 0 ligne signifie "introuvable" (inexistant, supprimé, non-open
    // ou hors tenant) -> 404, pas 409 slot_taken (réservé au vrai
    // double-booking, capté séparément plus bas par la contrainte 23P01).
    let slot_row = sqlx::query(
        "SELECT starts_at, ends_at, practitioner_id \
         FROM availability_slot \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL AND status = 'open'",
    )
    .bind(body.slot_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let starts_at: chrono::DateTime<chrono::Utc> = slot_row
        .try_get("starts_at")
        .map_err(|_| AppError::Internal)?;
    let ends_at: chrono::DateTime<chrono::Utc> = slot_row
        .try_get("ends_at")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = slot_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    // INSERT — 23P01 (appointment_no_overlap) → 409 slot_taken.
    let result = sqlx::query(
        "INSERT INTO appointment \
         (cabinet_id, patient_id, practitioner_id, slot_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, $5, $6, 'requested', $7) \
         RETURNING id, status",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(body.slot_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(motif.as_deref())
    .fetch_one(&mut *tx)
    .await;

    let row = match result {
        Ok(r) => r,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE availability_slot SET status = 'booked', updated_at = now() \
         WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(body.slot_id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // audit_log lié au conversation_id (traçabilité de la conversion depuis
    // le fil d'origine), appointment_id en metadata.
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, $3, 'convert_to_appointment', 'conversation', $4, $5)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(conversation_id)
    .bind(serde_json::json!({ "appointment_id": appointment_id }))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    hub.publish(
        claims.cabinet_id,
        serde_json::json!({
            "channel": "waiting_room",
            "event": "queue_updated",
            "data": { "appointment_id": appointment_id, "status": status }
        })
        .to_string(),
    );

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        role = %claims.role,
        conversation_id = %conversation_id,
        appointment_id = %appointment_id,
        "conversation converted to appointment"
    );

    Ok((
        StatusCode::CREATED,
        Json(ConvertConversationResponse {
            appointment_id,
            status,
        }),
    ))
}
