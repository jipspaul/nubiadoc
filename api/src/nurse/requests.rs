//! Demandes de visite côté PATIENT : créer (+ fan-out géo aux infirmières
//! proches en ligne), lister, détail, annuler.
//!
//! Quoi/Quand : le patient pose une demande géolocalisée (`POST
//! /v1/account/visit-requests`) ; le handler sélectionne les infirmières en
//! ligne dans leur rayon d'intervention (`ST_DWithin`) et fan-out des offres via
//! `offer_visit_to_nurses` (SECURITY DEFINER). La première qui accepte gagne
//! (`claim_visit`, cf. `visits.rs`).
//! Pourquoi cette approche : clone 1:1 du cycle `pharmacy_order` (0124) + du
//! matching de proximité `pharmacy/directory`, sans réinventer de primitive.
//! Modes d'échec : lat/lng manquants ou acte inconnu → 422 ; demande active déjà
//! en cours (index unique partiel 0234) → 409.

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::postgres::PgRow;
use sqlx::Row;
use uuid::Uuid;

use crate::auth::{AppError, PatientAccountClaims};
use crate::{notify, realtime::WsHub, AppState, JobDispatcher};

/// Actes de soin proposables en v1 (liste courte en dur ; un catalogue viendra
/// plus tard). Toute valeur hors liste → 422.
pub(crate) const ALLOWED_ACTS: &[&str] = &[
    "prise_de_sang",
    "pansement",
    "injection",
    "perfusion",
    "toilette",
    "surveillance",
];

/// Nombre max d'infirmières sollicitées par demande (fan-out).
const MAX_OFFER_NURSES: i64 = 10;

// ── DTO commun (patient + infirmière) ──────────────────────────────────────────

/// Colonnes projetées d'une `visit_request` dans les réponses API.
pub(crate) const VISIT_COLUMNS: &str = "id, nurse_id, status, requested_acts, address, \
     patient_display_name, notes, requested_at, offered_at, accepted_at, en_route_at, \
     arrived_at, done_at, cancelled_at";

/// Une demande de visite dans les réponses API.
#[derive(Serialize)]
pub struct VisitDto {
    pub id: Uuid,
    pub nurse_id: Option<Uuid>,
    pub status: String,
    pub requested_acts: Vec<String>,
    pub address: serde_json::Value,
    pub patient_display_name: String,
    pub notes: Option<String>,
    pub requested_at: String,
    pub offered_at: Option<String>,
    pub accepted_at: Option<String>,
    pub en_route_at: Option<String>,
    pub arrived_at: Option<String>,
    pub done_at: Option<String>,
    pub cancelled_at: Option<String>,
}

fn opt_rfc3339(v: Option<chrono::DateTime<chrono::Utc>>) -> Option<String> {
    v.map(|d| d.to_rfc3339())
}

pub(crate) fn visit_from_row(row: &PgRow) -> Result<VisitDto, AppError> {
    Ok(VisitDto {
        id: row.try_get("id").map_err(|_| AppError::Internal)?,
        nurse_id: row.try_get("nurse_id").map_err(|_| AppError::Internal)?,
        status: row.try_get("status").map_err(|_| AppError::Internal)?,
        requested_acts: row
            .try_get("requested_acts")
            .map_err(|_| AppError::Internal)?,
        address: row.try_get("address").map_err(|_| AppError::Internal)?,
        patient_display_name: row
            .try_get("patient_display_name")
            .map_err(|_| AppError::Internal)?,
        notes: row.try_get("notes").map_err(|_| AppError::Internal)?,
        requested_at: row
            .try_get::<chrono::DateTime<chrono::Utc>, _>("requested_at")
            .map_err(|_| AppError::Internal)?
            .to_rfc3339(),
        offered_at: opt_rfc3339(row.try_get("offered_at").map_err(|_| AppError::Internal)?),
        accepted_at: opt_rfc3339(row.try_get("accepted_at").map_err(|_| AppError::Internal)?),
        en_route_at: opt_rfc3339(row.try_get("en_route_at").map_err(|_| AppError::Internal)?),
        arrived_at: opt_rfc3339(row.try_get("arrived_at").map_err(|_| AppError::Internal)?),
        done_at: opt_rfc3339(row.try_get("done_at").map_err(|_| AppError::Internal)?),
        cancelled_at: opt_rfc3339(
            row.try_get("cancelled_at")
                .map_err(|_| AppError::Internal)?,
        ),
    })
}

// ── Créer une demande (+ fan-out) ──────────────────────────────────────────────

/// Corps de `POST /v1/account/visit-requests`.
#[derive(Deserialize)]
pub struct CreateVisitBody {
    pub lat: f64,
    pub lng: f64,
    pub address: serde_json::Value,
    pub requested_acts: Vec<String>,
    /// Nom minimisé « Prénom N. » fourni par l'app (le back n'a que le nom chiffré) — présenté à l'infirmière.
    pub patient_display_name: String,
    pub notes: Option<String>,
}

/// `POST /v1/account/visit-requests` — crée une demande géolocalisée puis
/// fan-out les offres aux infirmières proches en ligne. 201 + la demande.
pub async fn create_visit_request(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: PatientAccountClaims,
    Json(body): Json<CreateVisitBody>,
) -> Result<(StatusCode, Json<VisitDto>), AppError> {
    // Validation : au moins un acte, tous connus.
    if body.requested_acts.is_empty()
        || !body
            .requested_acts
            .iter()
            .all(|a| ALLOWED_ACTS.contains(&a.as_str()))
    {
        return Err(AppError::ValidationError);
    }
    crate::text_validation::reject_nul_byte(&body.patient_display_name)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Insert 'requested' (RLS visit_request_patient_insert). Doublon actif → 409.
    let row = sqlx::query(&format!(
        "INSERT INTO visit_request \
         (patient_account_id, visit_geo, address, requested_acts, patient_display_name, notes) \
         VALUES ($1, ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography, $4, $5, $6, $7) \
         RETURNING {VISIT_COLUMNS}",
    ))
    .bind(claims.account_id) // $1
    .bind(body.lat) // $2
    .bind(body.lng) // $3
    .bind(&body.address) // $4
    .bind(&body.requested_acts) // $5
    .bind(&body.patient_display_name) // $6
    .bind(&body.notes) // $7
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => AppError::Conflict,
        _ => AppError::Internal,
    })?;
    let visit = visit_from_row(&row)?;
    let request_id = visit.id;

    // Matching : infirmières en ligne dont le rayon couvre le point de visite,
    // triées par proximité (annuaire public lisible sous GUC patient).
    let nurse_rows = sqlx::query(
        "SELECT id FROM nurse \
         WHERE is_online AND is_listed AND deleted_at IS NULL AND geo IS NOT NULL \
           AND ST_DWithin(geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography, service_radius_m) \
         ORDER BY ST_Distance(geo, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography) ASC \
         LIMIT $3",
    )
    .bind(body.lat) // $1
    .bind(body.lng) // $2
    .bind(MAX_OFFER_NURSES) // $3
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let nurse_ids: Vec<Uuid> = nurse_rows
        .iter()
        .map(|r| r.try_get("id").map_err(|_| AppError::Internal))
        .collect::<Result<_, _>>()?;

    // Fan-out (SECURITY DEFINER : insère les offres + passe la demande à 'offered').
    let mut nurse_notifs: Vec<(Uuid, Uuid)> = Vec::new();
    if !nurse_ids.is_empty() {
        sqlx::query("SELECT offer_visit_to_nurses($1, $2, interval '5 minutes')")
            .bind(request_id)
            .bind(&nurse_ids)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        for nurse_id in &nurse_ids {
            let staff = notify::notify_nurse_staff(
                &mut tx,
                *nurse_id,
                "visit_offer",
                "Nouvelle demande de visite proche",
                serde_json::json!({ "visit_request_id": request_id }),
            )
            .await?;
            nurse_notifs.extend(staff);
        }
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Push + WS après commit (fire-and-forget).
    for (app_user_id, notification_id) in nurse_notifs {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    for nurse_id in &nurse_ids {
        hub.publish_named(
            &format!("nurse_offers:{nurse_id}"),
            notify::order_event(&format!("nurse_offers:{nurse_id}"), request_id, "offered"),
        );
    }

    // Re-lit le statut réel (offered si des offres ont été posées, sinon requested).
    let status = if nurse_ids.is_empty() {
        "requested"
    } else {
        "offered"
    };
    tracing::info!(visit_request_id = %request_id, offers = nurse_ids.len(), "visit request created");
    let mut out = visit;
    out.status = status.to_string();
    Ok((StatusCode::CREATED, Json(out)))
}

// ── Lister / détail / annuler (patient) ────────────────────────────────────────

/// `GET /v1/account/visit-requests` — demandes du patient courant (récentes d'abord).
pub async fn list_account_visit_requests(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<Vec<VisitDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&format!(
        "SELECT {VISIT_COLUMNS} FROM visit_request \
         WHERE patient_account_id = $1 ORDER BY requested_at DESC LIMIT 50",
    ))
    .bind(claims.account_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(visit_from_row)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Json(data))
}

/// `GET /v1/account/visit-requests/:id` — détail d'une demande du patient.
pub async fn get_account_visit_request(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<VisitDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(&format!(
        "SELECT {VISIT_COLUMNS} FROM visit_request WHERE id = $1",
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(visit_from_row(&row.ok_or(AppError::NotFound)?)?))
}

/// `POST /v1/account/visit-requests/:id/cancel` — le patient annule sa demande
/// (RLS `visit_request_patient_cancel` : interdit d'annuler un état terminal).
pub async fn cancel_account_visit_request(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<WsHub>>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<VisitDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(&format!(
        "UPDATE visit_request \
         SET status = 'cancelled', cancelled_at = now(), updated_at = now() \
         WHERE id = $1 AND status IN ('requested','offered','accepted','en_route','arrived') \
         RETURNING {VISIT_COLUMNS}",
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        let exists = sqlx::query("SELECT 1 FROM visit_request WHERE id = $1")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        tx.rollback().await.ok();
        return Err(if exists.is_none() {
            AppError::NotFound
        } else {
            AppError::InvalidStatus
        });
    };
    let visit = visit_from_row(&row)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Prévient l'infirmière assignée (le cas échéant) via son canal tenant.
    if let Some(nurse_id) = visit.nurse_id {
        hub.publish_named(
            &format!("nurse_visits:{nurse_id}"),
            notify::order_event(&format!("nurse_visits:{nurse_id}"), visit.id, "cancelled"),
        );
    }
    Ok(Json(visit))
}
