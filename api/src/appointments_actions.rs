//! Handlers d'action patient sur un RDV existant — `patch` (reprogrammation/
//! motif) et `cancel` — extrait de `appointments.rs` (refactor pur, aucun
//! changement de comportement, issue #4329) : `appointments.rs` dépassait
//! largement le plafond absolu de 700 lignes fixé par CLAUDE.md.
//!
//! `checkin`/`callback-request` vivent dans `appointments_checkin.rs`
//! (même famille d'actions patient, séparées uniquement pour rester sous
//! le plafond de taille — regrouper les 4 actions dans un seul fichier
//! comme suggéré par l'issue aurait produit ~724 lignes, au-delà du
//! plafond absolu). Les structs de réponse partagées avec
//! `appointments_read.rs`/`appointments_create.rs` (`AppointmentDetail`,
//! `ProviderDetail`, `CabinetInfo`) et les helpers de fetch/violation
//! vivent dans `appointments_response.rs`.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    appointments_response::{
        fetch_cabinet_for_response, fetch_provider_for_response, is_exclusion_violation,
        AppointmentDetail, CabinetInfo, ProviderDetail,
    },
    auth::{AppError, PatientAccountClaims},
    AppState,
};

// ── Patch ────────────────────────────────────────────────────────────────────

/// Corps de la requête `PATCH /v1/appointments/:id`.
#[derive(Deserialize)]
pub struct PatchAppointmentBody {
    pub starts_at: Option<String>,
    pub motif: Option<String>,
}

/// `PATCH /v1/appointments/:id` — patient modifie son RDV (créneau ou motif),
/// y compris un RDV de dépendant (tutelle, `app.current_account_id` — #4388).
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// Hors délai (≥ 24 h avant starts_at courant) → `409 too_late`.
/// Conflit créneau (contrainte PG `23P01`) → `409 slot_taken`.
/// Audité (`update_appointment`) dans `audit_log`.
pub async fn patch_appointment(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
    Json(body): Json<PatchAppointmentBody>,
) -> Result<Json<AppointmentDetail>, AppError> {
    let new_starts_at: Option<chrono::DateTime<chrono::Utc>> = body
        .starts_at
        .as_deref()
        .map(|s| s.parse::<chrono::DateTime<chrono::Utc>>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Cf. get_appointment/cancel_appointment (#4388) : requis pour la branche
    // tutelle de appointment_patient_read (migration 0196, account_guardianship
    // RLS) — sans lui, un RDV de dépendant renvoie 404 alors que GET/cancel/
    // queue/directions le voient déjà tous.
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, starts_at, status, cabinet_id, slot_id, practitioner_id \
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
    let slot_id: Option<Uuid> = row.try_get("slot_id").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    if status != "requested" && status != "confirmed" {
        return Err(AppError::InvalidStatus);
    }

    // Délai configurable, défaut 24 h avant le starts_at courant.
    if chrono::Utc::now() >= starts_at - chrono::Duration::hours(24) {
        return Err(AppError::TooLate);
    }

    // Reprogrammation : le nouveau créneau doit être validé côté serveur, comme
    // la réservation initiale (POST /v1/bookings exige un availability_slot réel).
    // Sinon un patient pouvait déplacer son RDV vers une date passée ou une heure
    // sans ouverture (03h17…) — RDV fantôme "requested" polluant la liste cabinet
    // (#3558). Le nouveau starts_at doit être (a) dans le futur ET (b) correspondre
    // à un créneau `open` du praticien. Les créneaux ouverts sont publiquement
    // lisibles (policy availability_slot_patient_read, 0117 — aucun GUC requis).
    let mut new_slot_id: Option<Uuid> = None;
    if let Some(new_ts) = new_starts_at {
        if new_ts <= chrono::Utc::now() {
            return Err(AppError::SlotUnavailable);
        }
        // Préavis 24 h évalué sur la DESTINATION, pas seulement la source (:80) :
        // sans ce contrôle, un RDV source >24h pouvait être déplacé vers un créneau
        // <24h (préavis contourné) et se retrouvait ensuite piégé — toute nouvelle
        // reprogrammation lit alors le nouveau starts_at <24h → 409 too_late à vie
        // (#3891, cul-de-sac one-way).
        if chrono::Utc::now() >= new_ts - chrono::Duration::hours(24) {
            return Err(AppError::TooLate);
        }
        new_slot_id = sqlx::query_scalar(
            "SELECT s.id FROM availability_slot s \
               JOIN provider p ON p.id = s.provider_id \
               WHERE p.practitioner_id = $1 \
                 AND s.starts_at = $2 \
                 AND s.status = 'open' \
                 AND s.online_booking = true \
                 AND s.deleted_at IS NULL",
        )
        .bind(practitioner_id)
        .bind(new_ts)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        if new_slot_id.is_none() {
            return Err(AppError::SlotUnavailable);
        }
    }

    // Scope cabinet pour UPDATE (tenant_isolation) + audit.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Préserve la durée si starts_at change. 23P01 → slot_taken.
    // Un starts_at différent délie le RDV de son créneau d'origine et le
    // rattache au nouveau créneau de destination (slot_id = new_slot_id),
    // symétrique de create_appointment. Un changement de créneau repasse
    // aussi le RDV en 'requested' : le cabinet n'a confirmé que l'horaire
    // d'origine, pas le nouveau (symétrique de create_appointment qui naît
    // toujours 'requested') — sinon le patient s'auto-confirme un créneau
    // que le cabinet n'a jamais approuvé.
    let result = sqlx::query(
        "UPDATE appointment \
         SET \
           starts_at  = COALESCE($1, starts_at), \
           ends_at    = CASE WHEN $1 IS NOT NULL \
                             THEN $1 + (ends_at - starts_at) \
                             ELSE ends_at END, \
           motif      = COALESCE($2, motif), \
           slot_id    = CASE WHEN $1 IS NOT NULL THEN $4 ELSE slot_id END, \
           status     = CASE WHEN $1 IS NOT NULL THEN 'requested' ELSE status END, \
           updated_at = now() \
         WHERE id = $3 \
         RETURNING id, starts_at, ends_at, status, motif, practitioner_id",
    )
    .bind(new_starts_at)
    .bind(body.motif.as_deref())
    .bind(id)
    .bind(new_slot_id)
    .fetch_one(&mut *tx)
    .await;

    let updated = match result {
        Ok(row) => row,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    // Libère l'ancien créneau (comme cancel_appointment) puisqu'il n'est plus occupé.
    if new_starts_at.is_some() {
        if let Some(sid) = slot_id {
            sqlx::query("UPDATE availability_slot SET status = 'open' WHERE id = $1")
                .bind(sid)
                .execute(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
        }

        // Consomme le créneau de destination (symétrique de create_appointment,
        // l.1791-1801) : sinon il reste 'open' et apparaît comme réservable
        // dans la recherche publique alors qu'il est déjà occupé (#3707).
        if let Some(sid) = new_slot_id {
            sqlx::query(
                "UPDATE availability_slot SET status = 'booked', updated_at = now() \
                 WHERE id = $1",
            )
            .bind(sid)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        }
    }

    let appointment_id: Uuid = updated.try_get("id").map_err(|_| AppError::Internal)?;
    let new_starts_at: chrono::DateTime<chrono::Utc> = updated
        .try_get("starts_at")
        .map_err(|_| AppError::Internal)?;
    let new_ends_at: chrono::DateTime<chrono::Utc> =
        updated.try_get("ends_at").map_err(|_| AppError::Internal)?;
    let new_status: String = updated.try_get("status").map_err(|_| AppError::Internal)?;
    let new_motif: Option<String> = updated.try_get("motif").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = updated
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'update_appointment', 'appointment', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (provider_id, provider_display_name, provider_specialty) =
        fetch_provider_for_response(&mut tx, practitioner_id).await?;
    let (cabinet_name, cabinet_address) =
        fetch_cabinet_for_response(&mut tx, cabinet_id, practitioner_id).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        "appointment patched"
    );

    Ok(Json(AppointmentDetail {
        id: appointment_id,
        starts_at: new_starts_at.to_rfc3339(),
        ends_at: new_ends_at.to_rfc3339(),
        status: new_status,
        motif: new_motif,
        provider: ProviderDetail {
            id: provider_id,
            display_name: provider_display_name,
            specialty: provider_specialty,
        },
        cabinet: CabinetInfo {
            name: cabinet_name,
            address: cabinet_address,
        },
        // Non lu/reporté ici (retiming ne touche pas callback_requested_at) —
        // GET /appointments/:id reste la source de vérité pour ce champ.
        callback_requested_at: None,
    }))
}

// ── Cancel ──────────────────────────────────────────────────────────────────

/// Corps optionnel de `POST /v1/appointments/:id/cancel`.
#[derive(Deserialize, Default)]
pub struct CancelBody {
    pub reason: Option<String>,
}

/// Réponse de `POST /v1/appointments/:id/cancel`.
#[derive(Serialize)]
pub struct CancelResponse {
    pub appointment_id: Uuid,
    pub status: String,
}

/// `POST /v1/appointments/:id/cancel` — patient annule son RDV, libère le créneau.
/// Si le RDV est `checked_in`, permet de sortir de la file d'attente (→ `no_show`).
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// Vérifie status IN ('requested','confirmed','checked_in') → sinon `409 {"error":"invalid_status"}`.
/// Vérifie starts_at > now() + 2h → sinon `409 {"error":"too_late"}` — sauf si déjà `checked_in`,
/// si starts_at est déjà dans le passé (#3811, évite le cul-de-sac des RDV périmés), ou si le
/// RDV est encore `requested` (#3862, le cabinet n'a rien confirmé/engagé sur un booking <2h).
pub async fn cancel_appointment(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
    body: Option<Json<CancelBody>>,
) -> Result<Json<CancelResponse>, AppError> {
    let reason = body
        .as_ref()
        .and_then(|b| b.reason.as_deref())
        .map(str::to_owned);
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // La branche tutelle de appointment_patient_read (migration 0196) lit
    // account_guardianship, dont la policy `guardianship_owner_select` exige
    // app.current_account_id (pas app.patient_account_id) — même GUC que
    // create_appointment pose déjà pour vérifier la tutelle à la création.
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, starts_at, status, cabinet_id, slot_id \
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
    let slot_id: Option<Uuid> = row.try_get("slot_id").map_err(|_| AppError::Internal)?;

    if status != "requested" && status != "confirmed" && status != "checked_in" {
        return Err(AppError::InvalidStatus);
    }

    // Annulation refusée si le RDV démarre dans moins de 2 heures — sauf pour un
    // patient déjà checked_in, qui doit pouvoir sortir de la file à tout moment,
    // et sauf si starts_at est déjà dans le passé : la fenêtre des 2h est alors
    // déjà révolue et bloquer indéfiniment créerait un cul-de-sac (#3811) pour
    // les RDV résiduels créés avant le déploiement des gardes amont (#3750).
    //
    // Sauf aussi `requested` (#3862) : create_appointment n'applique aucune
    // borne de délai amont quand un slot_id est fourni (booking direct) — un
    // créneau réservable jusqu'à sa dernière minute produit un `requested`
    // immédiatement dans la fenêtre des 2h, donc ni annulable (too_late) ni
    // reprogrammable (garde 24h de patch_appointment) ni check-in (exige
    // confirmed). Le cabinet n'a encore rien confirmé/engagé sur un
    // `requested` : le patient doit pouvoir le retirer à tout moment.
    let now = chrono::Utc::now();
    if status != "checked_in"
        && status != "requested"
        && now < starts_at
        && now >= starts_at - chrono::Duration::hours(2)
    {
        return Err(AppError::TooLate);
    }

    // Un checked_in qui quitte la file est un no_show (il n'a pas été vu) ; sinon annulation classique.
    let new_status = if status == "checked_in" {
        "no_show"
    } else {
        "cancelled"
    };

    // Scope cabinet pour UPDATE (tenant_isolation) + audit.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE appointment \
         SET status = $2, cancelled_at = now(), cancel_reason = $3, updated_at = now() \
         WHERE id = $1",
    )
    .bind(id)
    .bind(new_status)
    .bind(reason.as_deref())
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(sid) = slot_id {
        sqlx::query("UPDATE availability_slot SET status = 'open' WHERE id = $1")
            .bind(sid)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    }

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'cancel_appointment', 'appointment', $3)",
    )
    .bind(cabinet_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        "appointment cancelled"
    );

    Ok(Json(CancelResponse {
        appointment_id: id,
        status: new_status.to_string(),
    }))
}
