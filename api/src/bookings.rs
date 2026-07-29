//! Handler `POST /v1/bookings` — consomme un hold_token et crée un appointment.
//!
//! Flux E.3.22.a : le patient a préalablement posé un hold via `POST /v1/slots/:id/hold`.
//! Ce handler valide le hold (non expiré, appartient au caller), crée l'appointment
//! et supprime le hold en une transaction atomique.

use axum::{extract::State, http::HeaderMap, http::StatusCode, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

/// Corps de la requête `POST /v1/bookings`.
#[derive(Deserialize)]
pub struct CreateBookingBody {
    pub slot_id: Uuid,
    pub hold_token: String,
    pub idempotency_key: Option<String>,
    /// Motif de consultation saisi par le patient (facultatif). Stocké sur
    /// l'appointment pour informer le praticien du motif de la venue (#3415).
    pub motif: Option<String>,
}

/// Réponse de `POST /v1/bookings`.
#[derive(Serialize)]
pub struct CreateBookingResponse {
    pub appointment_id: Uuid,
    pub status: String,
}

/// `POST /v1/bookings` — consomme un hold et crée un appointment (E.3.22.a).
///
/// Token `kind:"patient"` requis. Valide que le hold existe, n'est pas expiré
/// et appartient au caller. Crée l'appointment (`status = "requested"`) puis
/// supprime le hold. Contrainte d'exclusion DB (23P01) → `409 slot_taken`.
/// Idempotence optionnelle : si `idempotency_key` fournie et appointment existant
/// pour ce cabinet + clé → retourne le RDV existant si l'empreinte (slot_id + motif)
/// correspond, sinon `409 idempotency_key_conflict` (#3632).
pub async fn create_booking(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    headers: HeaderMap,
    Json(body): Json<CreateBookingBody>,
) -> Result<(StatusCode, Json<CreateBookingResponse>), AppError> {
    // Le front envoie la clé via l'en-tête `Idempotency-Key` (comme
    // create_appointment), jamais dans le corps — `body.idempotency_key`
    // restait donc toujours None en pratique (#3835). Priorité à l'en-tête,
    // repli sur le corps pour compat ascendante.
    let idempotency_key = headers
        .get("idempotency-key")
        .and_then(|v| v.to_str().ok())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_owned())
        .or_else(|| body.idempotency_key.clone());

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Résout le créneau pour obtenir cabinet_id + practitioner_id + starts_at/ends_at.
    // Via resolve_slot_for_booking (SECURITY DEFINER, migration 0128) : les
    // policies SELECT d'availability_slot ne montrent que status='open', or le
    // hold vient de passer le créneau en 'held' → un SELECT direct renvoyait
    // 0 ligne et le booking répondait 404 après chaque hold (#3347). Le hold
    // (token + user + expiration) est validé juste après.
    let slot_row = sqlx::query("SELECT * FROM resolve_slot_for_booking($1)")
        .bind(body.slot_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = slot_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = slot_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let starts_at: chrono::DateTime<chrono::Utc> = slot_row
        .try_get("starts_at")
        .map_err(|_| AppError::Internal)?;
    let ends_at: chrono::DateTime<chrono::Utc> = slot_row
        .try_get("ends_at")
        .map_err(|_| AppError::Internal)?;
    let slot_status: String = slot_row.try_get("status").map_err(|_| AppError::Internal)?;

    // Un créneau révolu (#3750) ne doit jamais donner lieu à un RDV : ce cas
    // ne devrait plus arriver via claim_and_hold_slot (migration 0145), mais
    // on revalide ici en défense en profondeur (créneau déjà held avant le
    // déploiement du correctif, contrairement à la garde `> now()` déjà
    // appliquée par POST /appointments — cf. #3722).
    if starts_at <= chrono::Utc::now() {
        return Err(AppError::StartAtNotFuture);
    }

    // Scope cabinet pour les requêtes soumises à la RLS tenant_isolation.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Idempotence : si un appointment existe déjà pour cette clé, le retourner.
    // Une clé rejouée avec un slot_id/motif différent ne doit jamais renvoyer le
    // RDV d'une autre requête (#3632, jumeau de #3547) -> empreinte comparée,
    // divergence -> 409 au lieu d'absorber silencieusement la 2e réservation.
    if let Some(ref key) = idempotency_key {
        let fingerprint = format!(
            "slot={}|motif={}",
            body.slot_id,
            body.motif.as_deref().unwrap_or("")
        );

        let existing = sqlx::query(
            "SELECT id, status, idempotency_fingerprint FROM appointment \
             WHERE cabinet_id = $1 AND idempotency_key = $2",
        )
        .bind(cabinet_id)
        .bind(key)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        if let Some(row) = existing {
            let cached_fingerprint: Option<String> = row
                .try_get("idempotency_fingerprint")
                .map_err(|_| AppError::Internal)?;
            if cached_fingerprint.as_deref() != Some(fingerprint.as_str()) {
                tx.commit().await.map_err(|_| AppError::Internal)?;
                tracing::warn!(
                    account_id = %claims.account_id,
                    "booking idempotency key replayed with a different fingerprint"
                );
                return Err(AppError::IdempotencyKeyConflict);
            }

            let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            tx.commit().await.map_err(|_| AppError::Internal)?;
            tracing::info!(
                account_id = %claims.account_id,
                appointment_id = %appointment_id,
                "booking create idempotent hit"
            );
            return Ok((
                StatusCode::CREATED,
                Json(CreateBookingResponse {
                    appointment_id,
                    status,
                }),
            ));
        }
    }

    // Jumeau de #3637 (déjà corrigé sur POST /appointments) : le hold passe le
    // créneau en 'held' (claim_and_hold_slot, 0120), mais rien ne ré-attestait
    // que le créneau était TOUJOURS 'held' au moment du booking. Un PATCH
    // secrétariat entre-temps (ex. status='blocked', indisponibilité
    // praticien posée après le hold patient) laissait passer une réservation
    // sur un créneau explicitement bloqué (#3744). Seul 'held' est légitime
    // ici : le hold_token/user_id/expiration est validé juste après.
    // Vérifié APRÈS le court-circuit idempotent ci-dessus : un replay légitime
    // arrive après que le 1er appel a déjà fait passer le créneau à 'booked'.
    if slot_status != "held" {
        return Err(AppError::SlotUnavailable);
    }

    // Valide le hold : appartient au caller, non expiré.
    let hold_row = sqlx::query(
        "SELECT id FROM slot_holds \
         WHERE slot_id = $1 AND hold_token = $2 AND user_id = $3 AND expires_at > now()",
    )
    .bind(body.slot_id)
    .bind(&body.hold_token)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::HoldInvalid)?;

    let hold_id: Uuid = hold_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Scope patient pour résoudre le dossier patient dans ce cabinet.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Récupère-ou-crée le dossier patient de ce cabinet (réservation marketplace
    // chez un nouveau praticien → pas encore de fiche). SECURITY DEFINER, cf.
    // migration 0123. NULL uniquement si le compte n'existe pas → 404 légitime.
    let patient_id: Uuid =
        sqlx::query_scalar::<_, Option<Uuid>>("SELECT ensure_patient_for_cabinet($1, $2)")
            .bind(claims.account_id)
            .bind(cabinet_id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;

    let fingerprint = idempotency_key.as_ref().map(|_| {
        format!(
            "slot={}|motif={}",
            body.slot_id,
            body.motif.as_deref().unwrap_or("")
        )
    });

    // INSERT appointment — 23P01 (appointment_no_overlap) → 409 slot_taken.
    let result = sqlx::query(
        "INSERT INTO appointment \
         (cabinet_id, patient_id, practitioner_id, slot_id, starts_at, ends_at, status, idempotency_key, motif, idempotency_fingerprint) \
         VALUES ($1, $2, $3, $4, $5, $6, 'requested', $7, $8, $9) \
         RETURNING id, status",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(body.slot_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(&idempotency_key)
    .bind(&body.motif)
    .bind(&fingerprint)
    .fetch_one(&mut *tx)
    .await;

    let row = match result {
        Ok(r) => r,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    // Consomme le créneau (status → 'booked').
    sqlx::query(
        "UPDATE availability_slot SET status = 'booked', updated_at = now() \
         WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(body.slot_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Supprime le hold.
    sqlx::query("DELETE FROM slot_holds WHERE id = $1")
        .bind(hold_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // #4406 : idem create_appointment (appointments.rs) — une entrée active
    // de liste d'attente pour ce patient+provider est honorée dès qu'un RDV
    // est effectivement créé. Pas de provider_id direct ici (booking via
    // hold_token/slot_id) : résolu via practitioner_id.
    sqlx::query(
        "UPDATE waiting_list_entry SET status = 'fulfilled' \
         WHERE patient_id = $1 AND status = 'active' \
           AND provider_id = (SELECT id FROM provider WHERE practitioner_id = $2)",
    )
    .bind(patient_id)
    .bind(practitioner_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %appointment_id,
        slot_id = %body.slot_id,
        "booking created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateBookingResponse {
            appointment_id,
            status,
        }),
    ))
}

fn is_exclusion_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23P01")
    )
}
