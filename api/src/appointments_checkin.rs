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
    notify, AppState, JobDispatcher,
};

/// Rôles cabinet notifiés à une demande de rappel (#6261) : secrétariat
/// uniquement, cf. `APPOINTMENT_REQUESTED_NOTIFY_ROLES` (appointments_create.rs).
const CALLBACK_REQUESTED_NOTIFY_ROLES: [&str; 1] = ["secretary"];

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
    Extension(dispatcher): Extension<std::sync::Arc<dyn JobDispatcher>>,
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
        "SELECT id, starts_at, status, cabinet_id, practitioner_id \
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
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

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

    // Notifie le praticien de l'arrivée de son patient (#6260) : sans ça, il
    // ne l'apprend qu'en regardant la salle d'attente. Titre sans donnée de
    // santé (cf. notify.rs) — le détail (patient, motif) reste dans l'app.
    let pract_row =
        sqlx::query("SELECT user_id FROM practitioner WHERE id = $1 AND cabinet_id = $2")
            .bind(practitioner_id)
            .bind(cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    let mut push_target: Option<(Uuid, Uuid)> = None;
    if let Some(pract_row) = pract_row {
        let practitioner_user_id: Uuid = pract_row
            .try_get("user_id")
            .map_err(|_| AppError::Internal)?;
        if let Some(notification_id) = notify::notify_user(
            &mut tx,
            practitioner_user_id,
            "patient_checked_in",
            "Un patient est arrivé",
            serde_json::json!({ "appointment_id": id }),
        )
        .await?
        {
            push_target = Some((practitioner_user_id, notification_id));
        }
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Push temps réel/mobile APRÈS commit (pattern pharmacy/orders.rs) — le
    // retour du notify était jeté, aucun push ne partait (#6329).
    if let Some((app_user_id, notification_id)) = push_target {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }

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

// ── Cabinet check-in ─────────────────────────────────────────────────────────

/// `POST /v1/cabinet/appointments/:id/checkin` — secrétariat marque un patient
/// arrivé au comptoir (#6411) : jusqu'ici seul `checkin_appointment` ci-dessus
/// existait, réservé au patient (`kind:"patient"`) — aucun chemin n'ouvrait le
/// check-in à un rôle cabinet, malgré le bouton « Marquer arrivé » du volet
/// agenda (design-v2).
///
/// Token pro requis (secretary+). `cabinet_id` extrait du JWT — jamais du body.
/// RLS scopé via `app.current_cabinet_id` : 404 si le RDV n'appartient pas au
/// cabinet. R10 : secrétaire scopée au secrétariat actif — même garde que
/// `confirm_appointment`/`no_show_appointment`.
/// Statut source attendu : `confirmed` → sinon `409 invalid_status` (pas de
/// fenêtre horaire ±60 min ici, contrairement au check-in patient : le
/// secrétariat constate une présence physique, pas une déclaration à distance).
/// Auditée (`checkin_appointment`) dans `audit_log`, avec le rôle réel de
/// l'acteur (secretary/practitioner/admin).
pub async fn cabinet_checkin_appointment(
    State(state): State<AppState>,
    Extension(hub): Extension<std::sync::Arc<crate::realtime::WsHub>>,
    Extension(dispatcher): Extension<std::sync::Arc<dyn JobDispatcher>>,
    claims: crate::auth::ProSecretaryPlusClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<CheckinResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let secretariat_scope = if claims.role == "secretary" {
        Some(claims.secretariat_id.ok_or(AppError::NotFound)?)
    } else {
        None
    };

    let row = sqlx::query(
        "SELECT id, status, practitioner_id FROM appointment a \
         WHERE a.id = $1 AND a.cabinet_id = $2 AND a.deleted_at IS NULL \
           AND ($3::uuid IS NULL OR EXISTS ( \
               SELECT 1 FROM provider pr \
               JOIN provider_secretariat ps ON ps.provider_id = pr.id \
               WHERE pr.practitioner_id = a.practitioner_id \
                 AND ps.secretariat_id = $3 \
                 AND ps.active = true \
           ))",
    )
    .bind(appt_id)
    .bind(claims.cabinet_id)
    .bind(secretariat_scope)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    if status != "confirmed" {
        return Err(AppError::InvalidStatus);
    }

    let updated = sqlx::query(
        "UPDATE appointment \
         SET status = 'checked_in', checkin_at = now(), checkin_method = 'manual', updated_at = now() \
         WHERE id = $1 \
         RETURNING checkin_at",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let checkin_at: chrono::DateTime<chrono::Utc> = updated
        .try_get("checkin_at")
        .map_err(|_| AppError::Internal)?;

    // Insérer l'événement check-in (UNIQUE sur appointment_id → 409 si double check-in concurrent).
    let ce_result = sqlx::query(
        "INSERT INTO checkin_event (cabinet_id, appointment_id, mode) VALUES ($1, $2, 'manual')",
    )
    .bind(claims.cabinet_id)
    .bind(id)
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
         VALUES ($1, $2, $3, 'checkin_appointment', 'appointment', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Notifie le praticien de l'arrivée de son patient (même besoin que le
    // check-in patient ci-dessus — cf. #6260) : sans ça, il ne l'apprend
    // qu'en regardant la salle d'attente.
    let pract_row =
        sqlx::query("SELECT user_id FROM practitioner WHERE id = $1 AND cabinet_id = $2")
            .bind(practitioner_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    let mut push_target: Option<(Uuid, Uuid)> = None;
    if let Some(pract_row) = pract_row {
        let practitioner_user_id: Uuid = pract_row
            .try_get("user_id")
            .map_err(|_| AppError::Internal)?;
        if let Some(notification_id) = notify::notify_user(
            &mut tx,
            practitioner_user_id,
            "patient_checked_in",
            "Un patient est arrivé",
            serde_json::json!({ "appointment_id": id }),
        )
        .await?
        {
            push_target = Some((practitioner_user_id, notification_id));
        }
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Push temps réel/mobile APRÈS commit (pattern pharmacy/orders.rs).
    if let Some((app_user_id, notification_id)) = push_target {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }

    // Temps réel : le patient apparaît dans la salle d'attente du cabinet — #3238.
    hub.publish(
        claims.cabinet_id,
        serde_json::json!({
            "channel": "waiting_room",
            "event": "checked_in",
            "data": { "appointment_id": id, "checkin_at": checkin_at.to_rfc3339() }
        })
        .to_string(),
    );

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        appointment_id = %id,
        "appointment checked in by cabinet staff"
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

    // Notifie le secrétariat du cabinet (#6261) : sans ça, la demande de
    // rappel n'apparaît que si quelqu'un rafraîchit l'agenda manuellement.
    let push_targets = notify::notify_cabinet_staff(
        &mut tx,
        cabinet_id,
        &CALLBACK_REQUESTED_NOTIFY_ROLES,
        "callback_requested",
        "Demande de rappel",
        serde_json::json!({ "appointment_id": id }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    dispatcher.enqueue_notify_callback(id, cabinet_id);

    // Push temps réel/mobile APRÈS commit (pattern pharmacy/orders.rs) — le
    // retour du notify était jeté, aucun push ne partait (#6329).
    for (app_user_id, notification_id) in push_targets {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }

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
