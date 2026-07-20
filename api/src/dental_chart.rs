//! Handlers `GET /v1/cabinet/patients/:id/dental-chart` et
//! `PUT /v1/cabinet/patients/:id/dental-chart` (§14).
//!
//! Accès praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
//! PUT atomique : remplace intégralement `teeth_status` jsonb.
//! `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
//! RLS `tenant_isolation` scoped via `app.current_cabinet_id`.

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

/// Réponse de `GET /v1/cabinet/patients/:id/dental-chart`.
#[derive(Serialize)]
pub struct DentalChartResponse {
    pub teeth: Value,
    pub updated_at: String,
}

/// Corps de `PUT /v1/cabinet/patients/:id/dental-chart`.
#[derive(Deserialize)]
pub struct PutDentalChartBody {
    pub teeth: Value,
}

/// États d'odontogramme connus (référence : valeurs déjà attestées dans le
/// repo avant #3838 — `db/seed/seed.sql` : "sain", "a_extraire", "implant" ;
/// `api/tests/dental_chart.rs::put_dental_chart_persists_teeth_jsonb` :
/// "present", "carie"). Complété par le vocabulaire dentaire FR standard.
/// `status` et `plan` (traitement futur planifié) partagent cet enum.
const TOOTH_STATUSES: &[&str] = &[
    "sain",
    "present",
    "carie",
    "obture",
    "couronne",
    "bridge",
    "implant",
    "absent",
    "a_extraire",
    "devitalise",
    "fracture",
];

/// Valide le contrat `teeth` : objet position→état, clés = codes dent ISO 3950.
///
/// ISO 3950 (notation FDI) : `<quadrant><dent>` où quadrant 1-4 (dentition
/// permanente, dents 1-8) ou quadrant 5-8 (dentition temporaire, dents 1-5).
/// Rejette tout scalaire (chaîne/entier/tableau) ainsi que les clés hors
/// numérotation ISO 3950 — cf. #3680.
///
/// Chaque valeur doit être un objet `{"status": <enum>, "plan"?: <enum>}` —
/// forme de référence `db/seed/seed.sql` (`{"status":"a_extraire","plan":"implant"}`).
/// Avant #3838, seules les CLÉS (codes dent) étaient validées : une valeur
/// scalaire, un statut inconnu ou un objet aux clés arbitraires étaient
/// acceptés et persistés tels quels (round-trip garbage).
fn validate_teeth(teeth: &Value) -> Result<(), AppError> {
    let map = teeth.as_object().ok_or(AppError::ValidationError)?;

    for (key, value) in map {
        let is_valid_tooth_code = key.len() == 2 && key.chars().all(|c| c.is_ascii_digit()) && {
            let quadrant = key.as_bytes()[0] - b'0';
            let tooth = key.as_bytes()[1] - b'0';
            match quadrant {
                1..=4 => (1..=8).contains(&tooth),
                5..=8 => (1..=5).contains(&tooth),
                _ => false,
            }
        };

        if !is_valid_tooth_code {
            return Err(AppError::ValidationError);
        }

        validate_tooth_value(value)?;
    }

    Ok(())
}

/// Valide la valeur d'une dent : objet `{status: <enum>, plan?: <enum>,
/// notes?: <string>}`, sans clé additionnelle. `notes` reste texte libre
/// (annotation clinique), non contraint à l'enum contrairement à `status`/`plan`.
fn validate_tooth_value(value: &Value) -> Result<(), AppError> {
    let obj = value.as_object().ok_or(AppError::ValidationError)?;

    let status = obj
        .get("status")
        .and_then(Value::as_str)
        .ok_or(AppError::ValidationError)?;
    if !TOOTH_STATUSES.contains(&status) {
        return Err(AppError::ValidationError);
    }

    if let Some(plan) = obj.get("plan") {
        let plan_str = plan.as_str().ok_or(AppError::ValidationError)?;
        if !TOOTH_STATUSES.contains(&plan_str) {
            return Err(AppError::ValidationError);
        }
    }

    if let Some(notes) = obj.get("notes") {
        if notes.as_str().is_none() {
            return Err(AppError::ValidationError);
        }
    }

    let allowed_keys = obj
        .keys()
        .all(|k| k == "status" || k == "plan" || k == "notes");
    if !allowed_keys {
        return Err(AppError::ValidationError);
    }

    Ok(())
}

// ── GET /v1/cabinet/patients/:id/dental-chart ─────────────────────────────────

/// `GET /v1/cabinet/patients/:id/dental-chart` — odontogramme du patient.
///
/// Praticien uniquement (R.4127-72) — secrétaire → 403 (via `ProPractitionerClaims`).
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS `tenant_isolation` scoped via `app.current_cabinet_id`.
/// Patient inexistant ou hors tenant → 404.
/// Si aucun enregistrement → retourne `{ teeth: {}, updated_at: <now> }`.
pub async fn get_dental_chart(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<DentalChartResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le cloisonnement).
    let patient_exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // RLS strict E.2.16.c : le praticien doit avoir eu au moins un appointment
    // avec ce patient dans ce cabinet (§14 — accès schéma dentaire).
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
           AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    let row = sqlx::query(
        "SELECT teeth_status, updated_at FROM dental_chart \
         WHERE patient_id = $1 AND cabinet_id = $2 \
         ORDER BY updated_at DESC LIMIT 1",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let response = match row {
        None => DentalChartResponse {
            teeth: serde_json::json!({}),
            updated_at: chrono::Utc::now().to_rfc3339(),
        },
        Some(r) => {
            let teeth: Value = r.try_get("teeth_status").map_err(|_| AppError::Internal)?;
            let updated_at: chrono::DateTime<chrono::Utc> =
                r.try_get("updated_at").map_err(|_| AppError::Internal)?;
            DentalChartResponse {
                teeth,
                updated_at: updated_at.to_rfc3339(),
            }
        }
    };

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        "dental chart read"
    );

    Ok(Json(response))
}

// ── PUT /v1/cabinet/patients/:id/dental-chart ─────────────────────────────────

/// `PUT /v1/cabinet/patients/:id/dental-chart` — remplacement atomique de l'odontogramme.
///
/// Praticien uniquement (R.4127-72) — secrétaire → 403 (via `ProPractitionerClaims`).
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS `tenant_isolation` scoped via `app.current_cabinet_id`.
/// Patient inexistant ou hors tenant → 404.
/// PUT atomique : `teeth_status` est remplacé intégralement.
/// Réponse : `200 { updated_at }`.
pub async fn put_dental_chart(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
    Json(body): Json<PutDentalChartBody>,
) -> Result<Json<DentalChartResponse>, AppError> {
    validate_teeth(&body.teeth)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le cloisonnement).
    let patient_exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // RLS strict E.2.16.c : le praticien doit avoir eu au moins un appointment
    // avec ce patient dans ce cabinet (§14 — accès schéma dentaire).
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
           AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    // UPSERT atomique : remplace intégralement teeth_status.
    let row = sqlx::query(
        "INSERT INTO dental_chart (cabinet_id, patient_id, teeth_status, updated_at) \
         VALUES ($1, $2, $3, now()) \
         ON CONFLICT (patient_id, cabinet_id) \
         DO UPDATE SET teeth_status = EXCLUDED.teeth_status, updated_at = now() \
         RETURNING teeth_status, updated_at",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(&body.teeth)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let teeth: Value = row
        .try_get("teeth_status")
        .map_err(|_| AppError::Internal)?;
    let updated_at: chrono::DateTime<chrono::Utc> =
        row.try_get("updated_at").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        "dental chart updated"
    );

    Ok(Json(DentalChartResponse {
        teeth,
        updated_at: updated_at.to_rfc3339(),
    }))
}
