//! Handlers de lecture auxiliaires sur un RDV — `directions` (deeplink
//! navigation) et `queue` (position en salle d'attente virtuelle) —
//! extrait de `appointments.rs` (refactor pur, aucun changement de
//! comportement, issue #4329) : `appointments.rs` dépassait largement le
//! plafond absolu de 700 lignes fixé par CLAUDE.md.
//!
//! Regroupées ici (plutôt que dans `appointments_read.rs`) uniquement pour
//! rester sous le plafond de taille — cf. docstring de ce dernier.
//! `format_establishment_address` (fallback annuaire, utilisé par
//! `get_appointment_directions`) vit dans `appointments_response.rs`.

use axum::{
    extract::{Path, Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    appointments_response::format_establishment_address,
    auth::{AppError, PatientAccountClaims},
    AppState,
};

// ── Directions ──────────────────────────────────────────────────────────────

/// Query params for `GET /v1/appointments/:id/directions`.
#[derive(Deserialize)]
pub struct DirectionsQuery {
    pub mode: Option<String>,
}

/// Réponse de `GET /v1/appointments/:id/directions`.
#[derive(Serialize)]
pub struct DirectionsResponse {
    pub mode: String,
    pub duration_min: Option<i32>,
    pub distance_m: Option<i32>,
    pub deeplink: String,
}

/// `GET /v1/appointments/:id/directions?mode=car` — deeplink navigation vers le cabinet.
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// MVP stub : `duration_min` et `distance_m` sont toujours null.
pub async fn get_appointment_directions(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
    Query(params): Query<DirectionsQuery>,
) -> Result<Json<DirectionsResponse>, AppError> {
    let mode = params.mode.unwrap_or_else(|| "car".to_string());

    if !matches!(mode.as_str(), "car" | "transit" | "walk") {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

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
        "SELECT cabinet_id, practitioner_id FROM appointment WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(appt_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cab_row = sqlx::query("SELECT settings->>'address' AS address FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::Internal)?;

    let address: Option<String> = cab_row.try_get("address").map_err(|_| AppError::Internal)?;

    // Jointure establishment/geo praticien : fallback quand `cabinet.settings` ne porte
    // pas d'adresse (cas du cabinet seed — cf. #3557), même donnée que celle déjà
    // exposée par `GET /v1/providers/:id`.
    let provider_row = sqlx::query(
        "SELECT e.address AS establishment_address, \
                ST_Y(p.geo::geometry) AS geo_lat, ST_X(p.geo::geometry) AS geo_lng \
         FROM provider p \
         LEFT JOIN establishment e ON e.id = p.establishment_id \
         WHERE p.practitioner_id = $1 \
         LIMIT 1",
    )
    .bind(practitioner_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let establishment_address: Option<serde_json::Value> = provider_row.as_ref().and_then(|r| {
        r.try_get::<Option<serde_json::Value>, _>("establishment_address")
            .ok()
            .flatten()
    });
    let provider_geo_lat: Option<f64> = provider_row
        .as_ref()
        .and_then(|r| r.try_get::<Option<f64>, _>("geo_lat").ok().flatten());
    let provider_geo_lng: Option<f64> = provider_row
        .as_ref()
        .and_then(|r| r.try_get::<Option<f64>, _>("geo_lng").ok().flatten());

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let resolved_address = address.or_else(|| {
        establishment_address
            .as_ref()
            .and_then(format_establishment_address)
    });

    let destination = match resolved_address {
        Some(a) => a.replace(' ', "+"),
        None => match (provider_geo_lat, provider_geo_lng) {
            (Some(lat), Some(lng)) => format!("{lat},{lng}"),
            _ => String::new(),
        },
    };
    let travelmode = match mode.as_str() {
        "walk" => "walking",
        "transit" => "transit",
        _ => "driving",
    };
    let deeplink = format!(
        "https://www.google.com/maps/dir/?api=1&destination={}&travelmode={}",
        destination, travelmode
    );

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %appt_id,
        mode = %mode,
        "appointment directions requested"
    );

    Ok(Json(DirectionsResponse {
        mode,
        duration_min: None,
        distance_m: None,
        deeplink,
    }))
}

// ── Queue ────────────────────────────────────────────────────────────────────

/// Réponse de `GET /v1/appointments/:id/queue`.
#[derive(Serialize)]
pub struct QueueResponse {
    pub position: Option<i64>,
    pub est_wait_min: Option<i64>,
    pub status: String,
}

/// `GET /v1/appointments/:id/queue` — position du patient dans la salle d'attente virtuelle.
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// `position` = nombre de rendez-vous antérieurs (checkin_at < le nôtre) pour le même praticien
/// avec status `checked_in` ou `in_progress`, bornés à la fenêtre GLISSANTE (`now() ± interval
/// '1 day'`), comme la waiting-room (`scheduling::get_waiting_room`) et `call_next_patient` (#4869).
/// `est_wait_min` reste `null` (pas d'estimation de temps d'attente en MVP).
/// Si le patient n'est pas encore checké (`status` ni `checked_in` ni `in_progress`), `position`
/// vaut `null` et `status` vaut `"not_checked_in"` : le patient n'est pas dans la file d'attente.
/// Même si `status` est `checked_in`/`in_progress`, un RDV dont `starts_at` sort de la fenêtre
/// glissante renvoie aussi `"not_checked_in"` (#3869) : cette fenêtre est la seule référence
/// pertinente, cohérente avec la waiting-room cabinet vue par le personnel (#5505).
pub async fn get_appointment_queue(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<QueueResponse>, AppError> {
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
        "SELECT id, status, checkin_at, practitioner_id, cabinet_id, \
                (starts_at >= now() - interval '1 day' \
                 AND starts_at < now() + interval '1 day') AS in_queue_window \
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
    let checkin_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("checkin_at").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let in_queue_window: bool = row
        .try_get("in_queue_window")
        .map_err(|_| AppError::Internal)?;

    // Scope cabinet pour les requêtes soumises à la RLS tenant_isolation.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Compte les rendez-vous antérieurs dans la file du même praticien.
    let position: i64 = if let Some(our_checkin_at) = checkin_at {
        sqlx::query(
            "SELECT COUNT(*) AS cnt \
             FROM appointment \
             WHERE practitioner_id = $1 \
               AND status IN ('checked_in', 'in_progress') \
               AND deleted_at IS NULL \
               AND starts_at >= now() - interval '1 day' \
               AND starts_at < now() + interval '1 day' \
               AND checkin_at < $2 \
               AND id != $3",
        )
        .bind(practitioner_id)
        .bind(our_checkin_at)
        .bind(id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get::<i64, _>("cnt")
        .map_err(|_| AppError::Internal)?
    } else {
        // Patient pas encore checké : retourne la taille totale de la file.
        sqlx::query(
            "SELECT COUNT(*) AS cnt \
             FROM appointment \
             WHERE practitioner_id = $1 \
               AND status IN ('checked_in', 'in_progress') \
               AND deleted_at IS NULL \
               AND starts_at >= now() - interval '1 day' \
               AND starts_at < now() + interval '1 day'",
        )
        .bind(practitioner_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get::<i64, _>("cnt")
        .map_err(|_| AppError::Internal)?
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        position,
        "appointment queue queried"
    );

    // position 1-indexée : le patient en tête de file est en position 1.
    let position_1 = position + 1;

    // Mapping statut DB → statut file spec §7 :
    //   in_progress → "in_progress"   (patient appelé, en consultation)
    //   checked_in  → "waiting"       (en salle d'attente)
    //   sinon       → "not_checked_in" (pas encore en salle d'attente : confirmed/requested/
    //                                   cancelled/no_show/completed, etc.)
    // Garde fenêtre glissante (#3869, alignée #4869/#5505) : un RDV checked_in/
    // in_progress dont `starts_at` sort de `now() ± 1 jour` n'est plus dans la
    // file — même borne que le COUNT de position ci-dessus et que la waiting-room
    // cabinet (scheduling::get_waiting_room / call_next_patient). Sans cette garde,
    // le patient recevait indéfiniment « c'est votre tour » pour un RDV invisible
    // du personnel (waiting-room cabinet déjà vide).
    let queue_status = match status.as_str() {
        "in_progress" if in_queue_window => "in_progress",
        "checked_in" if in_queue_window => "waiting",
        _ => "not_checked_in",
    };

    // Un RDV non checké n'a pas sa place dans la file : pas de position.
    let position_out = if queue_status == "not_checked_in" {
        None
    } else {
        Some(position_1)
    };

    Ok(Json(QueueResponse {
        position: position_out,
        est_wait_min: None,
        status: queue_status.to_string(),
    }))
}
