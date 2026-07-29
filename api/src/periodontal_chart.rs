//! Handlers `GET /v1/cabinet/patients/:id/periodontal-chart` et
//! `PUT /v1/cabinet/patients/:id/periodontal-chart` (#4105, table
//! `periodontal_chart`, migration 0179).
//!
//! Garde identique à `dental_chart.rs`/`medical_record.rs` (praticien
//! uniquement, R.4127-72, §07 §4.1) — secrétaire → 403.
//!
//! Contrairement à `dental_chart` (état courant unique par patient, upsert
//! sur `UNIQUE patient_id+cabinet_id`), `periodontal_chart` est une SÉRIE
//! de mesures ponctuelles (aucune contrainte d'unicité, chaque bilan est
//! daté via `measured_at`) : `GET` retourne le bilan le plus récent, `PUT`
//! insère un NOUVEAU bilan plutôt que de remplacer le précédent en place —
//! chaque bilan est une capture immuable dans le temps, pas un document
//! mutable comme l'odontogramme.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

// ── Structures ────────────────────────────────────────────────────────────────

/// Réponse de `GET`/`PUT /v1/cabinet/patients/:id/periodontal-chart`.
///
/// `measured_at` est un horodatage clinique (date de mesure réelle) —
/// `None` (`null` en JSON) quand aucun bilan n'existe encore pour ce
/// patient (#4413 : auparavant fabriqué à `now()` sur `GET`, changeant à
/// chaque appel et rendant l'état "aucun bilan" indistinguable d'un bilan
/// "mesuré à l'instant").
#[derive(Serialize)]
pub struct PeriodontalChartResponse {
    pub sites: Value,
    pub indices: Value,
    pub measured_at: Option<String>,
}

/// Corps de `PUT /v1/cabinet/patients/:id/periodontal-chart`.
#[derive(Deserialize)]
pub struct PutPeriodontalChartBody {
    pub sites: Value,
    pub indices: Value,
}

/// `sites`/`indices` : objet libre (aucun référentiel unique ne s'impose
/// pour les indices parodontaux, cf. migration 0179) — seule contrainte :
/// un objet, pas un scalaire/tableau (même garde minimale que `dental_chart`
/// avant validation stricte des clés, qui elle repose sur un référentiel
/// ISO 3950 qui n'a pas d'équivalent ici).
fn validate_object(value: &Value) -> Result<(), AppError> {
    if !value.is_object() {
        return Err(AppError::ValidationError);
    }
    Ok(())
}

async fn ensure_practitioner_care_relationship(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    patient_id: Uuid,
    cabinet_id: Uuid,
    user_id: Uuid,
) -> Result<(), AppError> {
    let patient_exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // RLS strict E.2.16.c : le praticien doit avoir eu au moins un appointment
    // avec ce patient dans ce cabinet (§14 — accès dossier clinique, même
    // garde que dental_chart.rs/medical_record.rs).
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
           AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(user_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    Ok(())
}

// ── GET /v1/cabinet/patients/:id/periodontal-chart ────────────────────────────

/// `GET /v1/cabinet/patients/:id/periodontal-chart` — bilan parodontal le
/// plus récent du patient.
///
/// Praticien uniquement (R.4127-72) — secrétaire → 403.
/// Patient inexistant ou hors tenant → 404.
/// Si aucun bilan → `{ sites: {}, indices: {}, measured_at: null }` (#4413 :
/// stable entre deux lectures, jamais fabriqué).
pub async fn get_periodontal_chart(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<PeriodontalChartResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    ensure_practitioner_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub)
        .await?;

    let row = sqlx::query(
        "SELECT sites, indices, measured_at FROM periodontal_chart \
         WHERE patient_id = $1 AND cabinet_id = $2 \
         ORDER BY measured_at DESC LIMIT 1",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let response = match row {
        None => PeriodontalChartResponse {
            sites: serde_json::json!({}),
            indices: serde_json::json!({}),
            measured_at: None,
        },
        Some(r) => {
            let sites: Value = r.try_get("sites").map_err(|_| AppError::Internal)?;
            let indices: Value = r.try_get("indices").map_err(|_| AppError::Internal)?;
            let measured_at: chrono::DateTime<chrono::Utc> =
                r.try_get("measured_at").map_err(|_| AppError::Internal)?;
            PeriodontalChartResponse {
                sites,
                indices,
                measured_at: Some(measured_at.to_rfc3339()),
            }
        }
    };

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        "periodontal chart read"
    );

    Ok(Json(response))
}

// ── PUT /v1/cabinet/patients/:id/periodontal-chart ────────────────────────────

/// `PUT /v1/cabinet/patients/:id/periodontal-chart` — enregistre un NOUVEAU
/// bilan parodontal (`measured_at = now()`), sans toucher aux bilans
/// précédents (série de mesures, cf. docstring de module).
///
/// Praticien uniquement (R.4127-72) — secrétaire → 403.
/// Patient inexistant ou hors tenant → 404.
/// `sites`/`indices` doivent être des objets JSON → 422 sinon.
/// Réponse : `200` avec le bilan créé.
pub async fn put_periodontal_chart(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
    Json(body): Json<PutPeriodontalChartBody>,
) -> Result<Json<PeriodontalChartResponse>, AppError> {
    validate_object(&body.sites)?;
    validate_object(&body.indices)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    ensure_practitioner_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub)
        .await?;

    let row = sqlx::query(
        "INSERT INTO periodontal_chart (cabinet_id, patient_id, sites, indices, measured_at) \
         VALUES ($1, $2, $3, $4, now()) \
         RETURNING sites, indices, measured_at",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(&body.sites)
    .bind(&body.indices)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let sites: Value = row.try_get("sites").map_err(|_| AppError::Internal)?;
    let indices: Value = row.try_get("indices").map_err(|_| AppError::Internal)?;
    let measured_at: chrono::DateTime<chrono::Utc> =
        row.try_get("measured_at").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        "periodontal chart bilan created"
    );

    Ok(Json(PeriodontalChartResponse {
        sites,
        indices,
        measured_at: Some(measured_at.to_rfc3339()),
    }))
}
