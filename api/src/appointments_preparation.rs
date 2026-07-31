//! Handler `GET /v1/appointments/:id/preparation` — infos pratiques du RDV
//! pour le patient (adresse, accès, liste "à apporter") — extrait de
//! `appointments.rs` (refactor pur, aucun changement de comportement,
//! issue #4329) : `appointments.rs` dépassait largement le plafond absolu
//! de 700 lignes fixé par CLAUDE.md. Isolé dans son propre fichier (plutôt
//! que regroupé avec les autres lectures) car déjà volumineux à lui seul.
//!
//! `format_establishment_address` (fallback annuaire) est partagé avec
//! `appointments_read_extras.rs` et `appointments_response.rs::fetch_cabinet_for_response`
//! — il vit dans `appointments_response.rs`.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    appointments_response::format_establishment_address,
    auth::{AppError, PatientAccountClaims},
    AppState,
};

// ── Preparation ─────────────────────────────────────────────────────────────

/// Provider summary for `GET /v1/appointments/:id/preparation`.
#[derive(Serialize)]
pub struct PreparationProvider {
    pub name: Option<String>,
}

/// Geo coordinates from cabinet settings.
#[derive(Serialize)]
pub struct GeoCoord {
    pub lat: f64,
    pub lon: f64,
}

/// Physical access info from cabinet settings.
#[derive(Serialize)]
pub struct AccessInfo {
    pub door_code: Option<String>,
    pub parking: bool,
    pub pmr: bool,
}

/// Establishment info for preparation response.
#[derive(Serialize)]
pub struct PreparationEstablishment {
    pub address: Option<String>,
    pub geo: Option<GeoCoord>,
    pub access: AccessInfo,
}

/// Item in the bring list.
#[derive(Serialize)]
pub struct BringItem {
    pub label: String,
    pub required: bool,
}

/// Réponse de `GET /v1/appointments/:id/preparation`.
#[derive(Serialize)]
pub struct PreparationResponse {
    pub provider: PreparationProvider,
    pub establishment: PreparationEstablishment,
    pub bring: Vec<BringItem>,
    pub reminder_at: String,
}

/// `GET /v1/appointments/:id/preparation` — infos pratiques du RDV pour le patient.
///
/// Token `kind:"patient"` requis. RLS ownership via `app.patient_account_id` (policy 0029) → 404.
/// Dérive `bring` : Carte Vitale (toujours), mutuelle si `tiers_payant`, documents si
/// `documents_hint` non null. `reminder_at = starts_at - 1 h`.
pub async fn get_appointment_preparation(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(appt_id): Path<Uuid>,
) -> Result<Json<PreparationResponse>, AppError> {
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
        "SELECT id, starts_at, cabinet_id, practitioner_id, patient_id, documents_hint \
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
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
    let documents_hint: Option<String> = row
        .try_get("documents_hint")
        .map_err(|_| AppError::Internal)?;

    // Patient réel du RDV (le DÉPENDANT pour un RDV on_behalf_of, pas le tuteur en
    // session) : la couverture/tiers-payant ci-dessous doit être lue sur ce compte,
    // pas sur claims.account_id (#4446).
    let patient_account_id: Uuid =
        sqlx::query_scalar("SELECT patient_account_id FROM patient WHERE id = $1")
            .bind(patient_id)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    // Scope cabinet pour accès provider + cabinet.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Jointure establishment/geo praticien : fallback quand `cabinet.settings` ne porte
    // pas d'adresse (cas du cabinet seed — cf. #3557).
    let provider_row = sqlx::query(
        "SELECT p.display_name, e.address AS establishment_address, \
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

    let provider_name: Option<String> = provider_row
        .as_ref()
        .and_then(|r| r.try_get::<String, _>("display_name").ok());
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

    let cab_row = sqlx::query(
        "SELECT settings->>'address'   AS address, \
                settings->>'door_code' AS door_code, \
                settings->>'parking'   AS parking, \
                settings->>'pmr'       AS pmr, \
                settings->'geo'        AS geo \
         FROM cabinet WHERE id = $1",
    )
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::Internal)?;

    let address: Option<String> = cab_row.try_get("address").map_err(|_| AppError::Internal)?;
    let door_code: Option<String> = cab_row
        .try_get("door_code")
        .map_err(|_| AppError::Internal)?;
    let parking_str: Option<String> = cab_row.try_get("parking").map_err(|_| AppError::Internal)?;
    let pmr_str: Option<String> = cab_row.try_get("pmr").map_err(|_| AppError::Internal)?;
    let geo_val: Option<serde_json::Value> =
        cab_row.try_get("geo").map_err(|_| AppError::Internal)?;

    // patient_coverage_owner (migration 0023) n'a pas de branche tutelle : elle exige
    // une égalité stricte GUC == patient_account_id. Le GUC est repositionné sur le
    // patient RÉEL du RDV (déjà authentifié via appointment_patient_read ci-dessus)
    // pour cette lecture, au lieu de rester sur claims.account_id (#4446).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(patient_account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Tiers-payant depuis patient_coverage du patient RÉEL du RDV (le dépendant pour
    // un on_behalf_of), pas depuis celle du compte de session (#4446).
    let coverage_row = sqlx::query(
        "SELECT tiers_payant FROM patient_coverage WHERE patient_account_id = $1 LIMIT 1",
    )
    .bind(patient_account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let tiers_payant: bool = coverage_row
        .and_then(|r| r.try_get::<bool, _>("tiers_payant").ok())
        .unwrap_or(false);

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let pmr = pmr_str.as_deref() == Some("true");
    // Même parsing que pmr : settings->>'parking' est du texte JSON ("true"/
    // "false"), pas un bool natif. Non converti auparavant, AccessInfo.parking
    // exposait la chaîne brute au lieu d'un bool (#3741).
    let parking = parking_str.as_deref() == Some("true");

    // Fallback annuaire quand `cabinet.settings` n'a pas d'adresse (#3557) : même donnée
    // que celle déjà exposée par `GET /v1/providers/:id`.
    let address = address.or_else(|| {
        establishment_address
            .as_ref()
            .and_then(format_establishment_address)
    });

    let geo = geo_val
        .and_then(|v| {
            let lat = v["lat"].as_f64()?;
            let lon = v["lon"].as_f64()?;
            Some(GeoCoord { lat, lon })
        })
        .or(match (provider_geo_lat, provider_geo_lng) {
            (Some(lat), Some(lng)) => Some(GeoCoord { lat, lon: lng }),
            _ => None,
        });

    let mut bring = vec![BringItem {
        label: "Carte Vitale".to_string(),
        required: true,
    }];
    if tiers_payant {
        bring.push(BringItem {
            label: "Carte mutuelle".to_string(),
            required: true,
        });
    }
    if documents_hint.is_some() {
        bring.push(BringItem {
            label: "Ordonnances et radios".to_string(),
            required: false,
        });
    }

    let reminder_at = (starts_at - chrono::Duration::hours(1)).to_rfc3339();

    tracing::info!(
        account_id = %claims.account_id,
        appointment_id = %id,
        "appointment preparation queried"
    );

    Ok(Json(PreparationResponse {
        provider: PreparationProvider {
            name: provider_name,
        },
        establishment: PreparationEstablishment {
            address,
            geo,
            access: AccessInfo {
                door_code,
                parking,
                pmr,
            },
        },
        bring,
        reminder_at,
    }))
}
