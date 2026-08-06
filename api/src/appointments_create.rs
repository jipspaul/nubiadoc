//! Handler `POST /v1/appointments` — création d'un RDV par le patient
//! (le plus volumineux à lui seul : vérification tutelle, résolution/claim
//! de créneau, idempotency) — extrait de `appointments.rs` (refactor pur,
//! aucun changement de comportement, issue #4329) : `appointments.rs`
//! dépassait largement le plafond absolu de 700 lignes fixé par CLAUDE.md.
//!
//! Les structs de réponse partagées avec `appointments_actions.rs`/
//! `appointments_read.rs` (`AppointmentDetail`, `ProviderDetail`,
//! `CabinetInfo`) et les helpers de fetch/violation vivent dans
//! `appointments_response.rs`.

use axum::{
    extract::{Extension, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use serde::Deserialize;
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

/// Corps de la requête `POST /v1/appointments`.
#[derive(Deserialize)]
pub struct CreateAppointmentBody {
    pub provider_id: Uuid,
    pub slot_id: Option<Uuid>,
    /// ISO 8601 UTC (ex. "2026-06-10T09:00:00Z"). Ignoré si `slot_id` est fourni.
    pub starts_at: Option<String>,
    pub motif: Option<String>,
    pub on_behalf_of: Option<Uuid>,
}

fn validate_appointment_payload(starts_at: chrono::DateTime<chrono::Utc>) -> Result<(), AppError> {
    if starts_at <= chrono::Utc::now() + chrono::Duration::minutes(5) {
        return Err(AppError::StartAtNotFuture);
    }
    Ok(())
}

/// `POST /v1/appointments` — création d'un RDV par le patient.
///
/// Token `kind:"patient"` requis. Le `cabinet_id` est déduit du praticien (jamais du body).
/// La contrainte d'exclusion DB `appointment_no_overlap` (erreur PG `23P01`) est mappée en
/// `409 slot_taken`. Si `on_behalf_of` est fourni, la tutelle active est vérifiée contre
/// `account_guardianship` — sinon `422 guardianship_required`.
/// `Idempotency-Key` optionnel : si fourni, un second appel avec la même clé retourne le RDV
/// existant (`201`) sans insérer de doublon.
/// Le statut initial est toujours `"requested"` (confirmation asynchrone par le cabinet).
/// Réponse : même shape que `GET /v1/appointments/:id`.
pub async fn create_appointment(
    State(state): State<AppState>,
    Extension(hub): Extension<std::sync::Arc<crate::realtime::WsHub>>,
    claims: PatientAccountClaims,
    headers: HeaderMap,
    Json(body): Json<CreateAppointmentBody>,
) -> Result<(StatusCode, Json<AppointmentDetail>), AppError> {
    if body.slot_id.is_none() && body.starts_at.is_none() {
        return Err(AppError::ValidationError);
    }

    // Validate starts_at when provided directly (not via slot_id).
    if body.slot_id.is_none() {
        if let Some(s) = body.starts_at.as_deref() {
            let sa = s
                .parse::<chrono::DateTime<chrono::Utc>>()
                .map_err(|_| AppError::ValidationError)?;
            validate_appointment_payload(sa)?;
        }
    }

    let idempotency_key: Option<String> = headers
        .get("idempotency-key")
        .and_then(|v| v.to_str().ok())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_owned());

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Vérifie la tutelle si on agit pour un proche.
    if let Some(dependent_id) = body.on_behalf_of {
        sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
            .bind(claims.account_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let guardianship = sqlx::query(
            "SELECT id FROM account_guardianship \
             WHERE guardian_account_id = $1 AND dependent_account_id = $2 AND active = true",
        )
        .bind(claims.account_id)
        .bind(dependent_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        if guardianship.is_none() {
            return Err(AppError::GuardianshipRequired);
        }
    }

    let effective_account_id = body.on_behalf_of.unwrap_or(claims.account_id);

    // Le praticien est récupéré via la policy `provider_public_read` (is_listed = true).
    let provider_row = sqlx::query(
        "SELECT cabinet_id, practitioner_id, display_name, specialite FROM provider WHERE id = $1",
    )
    .bind(body.provider_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = provider_row
        .try_get("cabinet_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id_opt: Option<Uuid> = provider_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id = practitioner_id_opt.ok_or(AppError::NotFound)?;
    let _provider_display_name: Option<String> = provider_row.try_get("display_name").ok();
    let _provider_specialty: Option<String> = provider_row.try_get("specialite").ok();

    // Scope cabinet pour les INSERTs soumis à la RLS tenant_isolation.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Fetch cabinet name + address for the response body.
    let cab_row = sqlx::query(
        "SELECT raison_sociale, settings->>'address' AS address FROM cabinet WHERE id = $1",
    )
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::Internal)?;

    let _cabinet_name: String = cab_row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;
    let _cabinet_address: Option<String> =
        cab_row.try_get("address").map_err(|_| AppError::Internal)?;

    // Idempotence : si une Idempotency-Key est fournie et qu'un RDV existe déjà pour ce
    // cabinet + clé, on retourne le RDV existant sans insérer de doublon. Une clé rejouée
    // avec une charge utile différente ne doit jamais renvoyer le RDV d'une autre requête
    // (#3632, jumeau de #3547/#3620 côté bookings.rs) -> empreinte comparée, divergence ->
    // 409 au lieu d'absorber silencieusement la 2e réservation.
    if let Some(ref key) = idempotency_key {
        let fingerprint = format!(
            "provider={}|slot={}|starts_at={}|motif={}|on_behalf_of={}",
            body.provider_id,
            body.slot_id.map(|s| s.to_string()).unwrap_or_default(),
            body.starts_at.as_deref().unwrap_or(""),
            body.motif.as_deref().unwrap_or(""),
            body.on_behalf_of.map(|s| s.to_string()).unwrap_or_default(),
        );

        let existing = sqlx::query(
            "SELECT id, status, starts_at, ends_at, motif, idempotency_fingerprint FROM appointment \
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
                    "appointment idempotency key replayed with a different fingerprint"
                );
                return Err(AppError::IdempotencyKeyConflict);
            }

            let appointment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            let idem_starts_at: chrono::DateTime<chrono::Utc> =
                row.try_get("starts_at").map_err(|_| AppError::Internal)?;
            let idem_ends_at: chrono::DateTime<chrono::Utc> =
                row.try_get("ends_at").map_err(|_| AppError::Internal)?;
            let idem_motif: Option<String> =
                row.try_get("motif").map_err(|_| AppError::Internal)?;

            let (prov_id, prov_name, prov_spec) =
                fetch_provider_for_response(&mut tx, practitioner_id).await?;
            let (cab_name, cab_addr) =
                fetch_cabinet_for_response(&mut tx, cabinet_id, practitioner_id).await?;

            tx.commit().await.map_err(|_| AppError::Internal)?;
            tracing::info!(
                account_id = %claims.account_id,
                appointment_id = %appointment_id,
                "appointment create idempotent hit"
            );
            return Ok((
                StatusCode::CREATED,
                Json(AppointmentDetail {
                    id: appointment_id,
                    starts_at: idem_starts_at.to_rfc3339(),
                    ends_at: idem_ends_at.to_rfc3339(),
                    status,
                    motif: idem_motif,
                    provider: ProviderDetail {
                        id: prov_id,
                        display_name: prov_name,
                        specialty: prov_spec,
                    },
                    cabinet: CabinetInfo {
                        name: cab_name,
                        address: cab_addr,
                    },
                    // Création (idempotent hit inclus) : jamais de rappel demandé.
                    callback_requested_at: None,
                }),
            ));
        }
    }

    // Récupère-ou-crée le dossier patient de ce cabinet (SECURITY DEFINER,
    // migration 0123 — même fonction que create_booking). Un simple SELECT
    // 404 sur un dossier absent : cas NORMAL pour un dépendant (compte géré
    // sans fiche patient tant qu'il n'a jamais consulté dans ce cabinet),
    // rendant `on_behalf_of` totalement inutilisable (#3739/#3836). NULL
    // uniquement si le compte lui-même n'existe pas → 404 légitime.
    let patient_id: Uuid =
        sqlx::query_scalar::<_, Option<Uuid>>("SELECT ensure_patient_for_cabinet($1, $2)")
            .bind(effective_account_id)
            .bind(cabinet_id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;

    // Résout starts_at / ends_at selon slot_id ou starts_at fourni.
    // status = 'open' : un créneau blocked (indispo praticien) ou held (hold
    // patient actif) ne doit pas être réservable, au même titre que le
    // chemin cabinet (create_cabinet_appointment).
    let (starts_at, ends_at, resolved_slot_id) = if let Some(slot_id) = body.slot_id {
        // #4405 : AND online_booking = true — sinon un patient qui connaît un
        // slot_id interne (jamais publié) le réserve directement, contournant
        // la même garde déjà posée sur le funnel hold (claim_and_hold_slot,
        // migration 0142/#3608) et les recherches publiques (marketplace.rs).
        let slot_row = sqlx::query(
            "SELECT starts_at, ends_at FROM availability_slot \
             WHERE id = $1 AND cabinet_id = $2 AND practitioner_id = $3 \
             AND deleted_at IS NULL AND status = 'open' AND online_booking = true \
             AND NOT EXISTS ( \
                 SELECT 1 FROM provider_unavailability pu \
                 JOIN provider prov ON prov.id = pu.provider_id \
                 WHERE prov.practitioner_id = $3 \
                   AND pu.starts_at < availability_slot.ends_at \
                   AND pu.ends_at > availability_slot.starts_at \
             )",
        )
        .bind(slot_id)
        .bind(cabinet_id)
        .bind(practitioner_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::SlotTaken)?;

        let sa: chrono::DateTime<chrono::Utc> = slot_row
            .try_get("starts_at")
            .map_err(|_| AppError::Internal)?;
        let ea: chrono::DateTime<chrono::Utc> = slot_row
            .try_get("ends_at")
            .map_err(|_| AppError::Internal)?;
        (sa, ea, Some(slot_id))
    } else {
        let sa = body
            .starts_at
            .as_deref()
            .and_then(|s| s.parse::<chrono::DateTime<chrono::Utc>>().ok())
            .ok_or(AppError::ValidationError)?;

        // La branche starts_at doit résoudre/exiger un availability_slot 'open'
        // du praticien, comme la branche slot_id ci-dessus et comme la
        // reprogrammation (patch_appointment) — sinon starts_at est accepté
        // sans aucun créneau réel (heure hors-agenda) et l'exclusion GiST ne
        // bloque que les chevauchements, pas les horaires impossibles (#3722).
        // #4405 : même garde que la branche slot_id ci-dessus — sans elle,
        // un patient qui devine l'heure exacte d'un créneau interne (heures
        // rondes) le réserve sans même connaître son slot_id.
        let slot_row = sqlx::query(
            "SELECT id, ends_at FROM availability_slot \
             WHERE cabinet_id = $1 AND practitioner_id = $2 AND starts_at = $3 \
             AND deleted_at IS NULL AND status = 'open' AND online_booking = true \
             AND NOT EXISTS ( \
                 SELECT 1 FROM provider_unavailability pu \
                 JOIN provider prov ON prov.id = pu.provider_id \
                 WHERE prov.practitioner_id = $2 \
                   AND pu.starts_at < availability_slot.ends_at \
                   AND pu.ends_at > availability_slot.starts_at \
             )",
        )
        .bind(cabinet_id)
        .bind(practitioner_id)
        .bind(sa)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::SlotTaken)?;

        let resolved_id: Uuid = slot_row.try_get("id").map_err(|_| AppError::Internal)?;
        let ea: chrono::DateTime<chrono::Utc> = slot_row
            .try_get("ends_at")
            .map_err(|_| AppError::Internal)?;
        (sa, ea, Some(resolved_id))
    };

    let fingerprint = idempotency_key.as_ref().map(|_| {
        format!(
            "provider={}|slot={}|starts_at={}|motif={}|on_behalf_of={}",
            body.provider_id,
            body.slot_id.map(|s| s.to_string()).unwrap_or_default(),
            body.starts_at.as_deref().unwrap_or(""),
            body.motif.as_deref().unwrap_or(""),
            body.on_behalf_of.map(|s| s.to_string()).unwrap_or_default(),
        )
    });

    // INSERT — 23P01 (appointment_no_overlap) → 409 slot_taken.
    let result = sqlx::query(
        "INSERT INTO appointment \
         (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif, slot_id, idempotency_key, idempotency_fingerprint) \
         VALUES ($1, $2, $3, $4, $5, 'requested', $6, $7, $8, $9) \
         RETURNING id, status",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(body.motif.as_deref())
    .bind(resolved_slot_id)
    .bind(&idempotency_key)
    .bind(&fingerprint)
    .fetch_one(&mut *tx)
    .await;

    let inserted_row = match result {
        Ok(row) => row,
        Err(e) if is_exclusion_violation(&e) => return Err(AppError::SlotTaken),
        Err(_) => return Err(AppError::Internal),
    };

    let appointment_id: Uuid = inserted_row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = inserted_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;

    // Consomme le créneau : il ne doit plus apparaître dans la recherche de
    // disponibilités (`/v1/search/slots` filtre `status = 'open'`). Symétrique de
    // l'annulation qui le repasse à 'open'. Scopé cabinet (slot_cabinet_write).
    // Les deux branches ci-dessus résolvent désormais un availability_slot réel
    // (#3722), resolved_slot_id est toujours Some ici.
    if let Some(slot_id) = resolved_slot_id {
        sqlx::query(
            "UPDATE availability_slot SET status = 'booked', updated_at = now() \
             WHERE id = $1 AND cabinet_id = $2",
        )
        .bind(slot_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    // #4406 : une entrée active de liste d'attente pour ce patient+provider
    // est honorée dès qu'un RDV est effectivement créé (docstring
    // offer_waiting_list_slot, scheduling.rs — #3759). Sans cette transition,
    // fulfilled est inatteignable : le patient reste "en attente" côté
    // cabinet et ne peut plus se réinscrire (index unique partiel
    // WHERE status='active', migration 0096).
    sqlx::query(
        "UPDATE waiting_list_entry SET status = 'fulfilled' \
         WHERE patient_id = $1 AND provider_id = $2 AND status = 'active'",
    )
    .bind(patient_id)
    .bind(body.provider_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Fetch provider + cabinet pour la réponse (même shape que GET /:id).
    let (provider_id, provider_display_name, provider_specialty) =
        fetch_provider_for_response(&mut tx, practitioner_id).await?;
    let (cabinet_name, cabinet_address) =
        fetch_cabinet_for_response(&mut tx, cabinet_id, practitioner_id).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    hub.publish(
        cabinet_id,
        serde_json::json!({
            "channel": "waiting_room",
            "event": "queue_updated",
            "data": { "appointment_id": appointment_id, "status": status }
        })
        .to_string(),
    );

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %appointment_id,
        "appointment created"
    );

    Ok((
        StatusCode::CREATED,
        Json(AppointmentDetail {
            id: appointment_id,
            starts_at: starts_at.to_rfc3339(),
            ends_at: ends_at.to_rfc3339(),
            status,
            motif: body.motif,
            provider: ProviderDetail {
                id: provider_id,
                display_name: provider_display_name,
                specialty: provider_specialty,
            },
            cabinet: CabinetInfo {
                name: cabinet_name,
                address: cabinet_address,
            },
            // Nouvel appointment : jamais de rappel demandé.
            callback_requested_at: None,
        }),
    ))
}
