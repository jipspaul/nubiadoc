//! Handlers de signal patient pendant le cycle de vie du RDV — `checkin`
//! (arrivée au cabinet) et `callback-request` (demande de rappel) — extrait
//! de `appointments.rs` (refactor pur, aucun changement de comportement,
//! issue #4329) : `appointments.rs` dépassait largement le plafond absolu
//! de 700 lignes fixé par CLAUDE.md.
//!
//! Séparé de `appointments_actions.rs` (patch/cancel) uniquement pour
//! rester sous le plafond de taille — cf. docstring de ce dernier.

use axum::{
    extract::{Extension, Path, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState, JobDispatcher,
};

// ── Check-in ────────────────────────────────────────────────────────────────

/// Corps optionnel de `POST /v1/appointments/:id/checkin`.
#[derive(Deserialize, Default)]
pub struct CheckinBody {
    pub qr_code: Option<String>,
}

/// Réponse de `POST /v1/appointments/:id/checkin`.
#[derive(Serialize)]
pub struct CheckinResponse {
    pub appointment_id: Uuid,
    pub status: String,
    pub checkin_at: String,
}

/// `POST /v1/appointments/:id/checkin` — patient signale son arrivée.
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// Vérifie status = 'confirmed' → sinon `409 {"code":"invalid_status"}`.
/// Vérifie la fenêtre starts_at ± 60 min → sinon `409 {"code":"too_early"}`
/// (trop tôt) ou `409 {"code":"out_of_window"}` (trop tard) — #3844 : les
/// deux bords de la même garde renvoient désormais le même statut HTTP.
pub async fn checkin_appointment(
    State(state): State<AppState>,
    Extension(hub): Extension<std::sync::Arc<crate::realtime::WsHub>>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
    body: Option<Json<CheckinBody>>,
) -> Result<Json<CheckinResponse>, AppError> {
    let qr_code = body.as_ref().and_then(|b| b.qr_code.clone());
    let method = if qr_code.is_some() {
        "qr_app"
    } else {
        "manual"
    }
    .to_string();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Cf. cancel_appointment : requis pour la branche tutelle de
    // appointment_patient_read (migration 0196, account_guardianship RLS).
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, starts_at, status, cabinet_id \
         FROM appointment \
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(appt_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let starts_at: chrono::DateTime<chrono::Utc> =
        row.try_get("starts_at").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;

    if status != "confirmed" {
        return Err(AppError::InvalidStatus);
    }

    let now = chrono::Utc::now();
    if now < starts_at - chrono::Duration::minutes(60) {
        return Err(AppError::TooEarly);
    }
    if now > starts_at + chrono::Duration::minutes(60) {
        return Err(AppError::OutOfWindow);
    }

    // Scope cabinet pour UPDATE (tenant_isolation) + audit.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let updated = sqlx::query(
        "UPDATE appointment \
         SET status = 'checked_in', checkin_at = now(), checkin_method = $2, updated_at = now() \
         WHERE id = $1 \
         RETURNING checkin_at",
    )
    .bind(id)
    .bind(&method)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let checkin_at: chrono::DateTime<chrono::Utc> = updated
        .try_get("checkin_at")
        .map_err(|_| AppError::Internal)?;

    // Insérer l'événement check-in (UNIQUE sur appointment_id → 409 si double check-in concurrent).
    let ce_result = sqlx::query(
        "INSERT INTO checkin_event (cabinet_id, appointment_id, mode) VALUES ($1, $2, $3)",
    )
    .bind(cabinet_id)
    .bind(id)
    .bind(&method)
    .execute(&mut *tx)
    .await;
    match ce_result {
        Ok(_) => {}
        Err(e) if is_unique_violation(&e) => return Err(AppError::InvalidStatus),
        Err(_) => return Err(AppError::Internal),
    }

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'checkin', 'appointment', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Temps réel : le patient apparaît dans la salle d'attente du cabinet — #3238.
    hub.publish(
        cabinet_id,
        serde_json::json!({
            "channel": "waiting_room",
            "event": "checked_in",
            "data": { "appointment_id": id, "checkin_at": checkin_at.to_rfc3339() }
        })
        .to_string(),
    );

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        method = %method,
        "appointment checked in"
    );

    Ok(Json(CheckinResponse {
        appointment_id: id,
        status: "checked_in".to_string(),
        checkin_at: checkin_at.to_rfc3339(),
    }))
}

// ── Callback request ────────────────────────────────────────────────────────

/// Réponse de `POST /v1/appointments/:id/callback-request`.
#[derive(Serialize)]
pub struct CallbackRequestResponse {
    pub appointment_id: Uuid,
    pub callback_requested_at: String,
    pub status: String,
}

/// `POST /v1/appointments/:id/callback-request` — patient demande un rappel téléphonique.
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// Vérifie status IN ('requested','confirmed') → sinon `409 {"error":"invalid_status"}`.
/// `callback_requested_at` ne change PAS `appointment.status` — la réponse renvoie
/// le statut réel de l'entité (#3845 : "callback_requested" n'a jamais été un
/// statut du modèle RDV, sa présence dans cette réponse contredisait tout GET
/// ultérieur). `callback_requested_at` est désormais aussi restitué par
/// `GET /appointments/:id` et la liste, pour rester visible au rafraîchissement.
/// Idempotent : si une demande existe déjà, renvoie l'horodatage existant.
/// Audité (`callback_request`) dans `audit_log`.
/// Notifie le cabinet via job apalis (stub pour MVP).
pub async fn callback_appointment(
    State(state): State<AppState>,
    Extension(dispatcher): Extension<std::sync::Arc<dyn JobDispatcher>>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<CallbackRequestResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // #4363 : requis pour la branche tutelle de appointment_patient_read
    // (migration 0196, account_guardianship RLS) — cf. get_appointment.
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, status, cabinet_id, callback_requested_at \
         FROM appointment \
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(appt_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let existing: Option<chrono::DateTime<chrono::Utc>> = row
        .try_get("callback_requested_at")
        .map_err(|_| AppError::Internal)?;

    if status != "requested" && status != "confirmed" {
        return Err(AppError::InvalidStatus);
    }

    // Idempotent : si déjà demandé, renvoie l'horodatage existant sans ré-écrire.
    if let Some(ts) = existing {
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(CallbackRequestResponse {
            appointment_id: id,
            callback_requested_at: ts.to_rfc3339(),
            status,
        }));
    }

    // Scope cabinet pour UPDATE (tenant_isolation) + audit.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE appointment \
         SET callback_requested_at = now(), updated_at = now() \
         WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let ts_row = sqlx::query("SELECT callback_requested_at FROM appointment WHERE id = $1")
        .bind(id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let callback_requested_at: chrono::DateTime<chrono::Utc> = ts_row
        .try_get("callback_requested_at")
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'request_callback', 'appointment', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    dispatcher.enqueue_notify_callback(id, cabinet_id);

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        "appointment callback requested"
    );

    Ok(Json(CallbackRequestResponse {
        appointment_id: id,
        callback_requested_at: callback_requested_at.to_rfc3339(),
        status,
    }))
}

fn is_unique_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23505")
    )
}
