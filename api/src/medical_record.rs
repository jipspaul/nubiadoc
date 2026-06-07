//! Handlers `GET /v1/cabinet/patients/:id/medical-record` et
//! `PATCH /v1/cabinet/patients/:id/medical-record` (§14).
//!
//! Accès praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
//! Chiffrement applicatif : `STUB_ENC:` en dev ; AES-256-GCM KMS Scaleway à NUB-T3.
//! Chaque lecture (`GET`) est auditée dans `audit_log(action='read_record')`.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

// ── Structures ────────────────────────────────────────────────────────────────

/// Réponse de `GET /v1/cabinet/patients/:id/medical-record`.
#[derive(Serialize)]
pub struct MedicalRecordResponse {
    pub allergies: Vec<serde_json::Value>,
    pub treatments: Vec<serde_json::Value>,
    pub history: Option<String>,
}

/// Corps de `PATCH /v1/cabinet/patients/:id/medical-record`.
#[derive(Deserialize)]
pub struct PatchMedicalRecordBody {
    pub allergies: Option<Vec<serde_json::Value>>,
    pub treatments: Option<Vec<serde_json::Value>>,
    pub history: Option<String>,
}

// ── Helpers chiffrement (stub dev) ────────────────────────────────────────────

/// Stub : `STUB_ENC:` + JSON sérialisé.
/// À NUB-T3 : remplacé par AES-256-GCM + envelope KMS Scaleway (`core/crypto`).
fn encrypt_stub(data: &serde_json::Value) -> Vec<u8> {
    let mut out = b"STUB_ENC:".to_vec();
    out.extend_from_slice(data.to_string().as_bytes());
    out
}

/// Stub : vérifie le préfixe `STUB_ENC:` et désérialise.
/// Retourne `None` si le ciphertext est malformé ou vide.
fn decrypt_stub(ciphertext: &[u8]) -> Option<serde_json::Value> {
    let s = std::str::from_utf8(ciphertext).ok()?;
    let json_str = s.strip_prefix("STUB_ENC:")?;
    serde_json::from_str(json_str).ok()
}

// ── GET /v1/cabinet/patients/:id/medical-record ───────────────────────────────

/// `GET /v1/cabinet/patients/:id/medical-record` — dossier médical déchiffré.
///
/// Praticien uniquement (R.4127-72) — secrétaire → 403 (via `ProPractitionerClaims`).
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS `tenant_isolation` scoped via `app.current_cabinet_id`.
/// Patient inexistant ou hors tenant → 404.
/// Si aucun enregistrement `medical_record` → retourne des valeurs vides.
/// Chaque appel insère une entrée `audit_log(action='read_record')`.
pub async fn get_medical_record(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<MedicalRecordResponse>, AppError> {
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

    // Charge le dossier médical (peut ne pas exister encore).
    let record_row = sqlx::query(
        "SELECT data_ciphertext FROM medical_record \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         ORDER BY updated_at DESC LIMIT 1",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let response = match record_row {
        None => MedicalRecordResponse {
            allergies: vec![],
            treatments: vec![],
            history: None,
        },
        Some(row) => {
            let ciphertext: Vec<u8> = row
                .try_get("data_ciphertext")
                .map_err(|_| AppError::Internal)?;
            // Déchiffrement stub → JSON object attendu :
            // { "allergies": [...], "treatments": [...], "history": "..." }
            let data = decrypt_stub(&ciphertext)
                .unwrap_or_else(|| json!({"allergies": [], "treatments": [], "history": null}));

            let allergies = data["allergies"].as_array().cloned().unwrap_or_default();
            let treatments = data["treatments"].as_array().cloned().unwrap_or_default();
            let history = data["history"].as_str().map(|s| s.to_string());

            MedicalRecordResponse {
                allergies,
                treatments,
                history,
            }
        }
    };

    // Audit : chaque lecture clinique est tracée (§07 §4.1).
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, 'practitioner', 'read_record', 'medical_record', $3, $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(patient_id)
    .bind(json!({}))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        "medical record read"
    );

    Ok(Json(response))
}

// ── PATCH /v1/cabinet/patients/:id/medical-record ─────────────────────────────

/// `PATCH /v1/cabinet/patients/:id/medical-record` — mise à jour partielle.
///
/// Praticien uniquement (R.4127-72) — secrétaire → 403 (via `ProPractitionerClaims`).
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS `tenant_isolation` scoped via `app.current_cabinet_id`.
/// Patient inexistant ou hors tenant → 404.
/// Merge partiel : seuls les champs présents dans le body écrasent l'existant.
/// Chiffrement applicatif : stub `STUB_ENC:` (AES-256-GCM KMS à NUB-T3).
/// Réponse : `200` avec le dossier mis à jour déchiffré.
pub async fn patch_medical_record(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
    Json(body): Json<PatchMedicalRecordBody>,
) -> Result<Json<MedicalRecordResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet.
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

    // Charge l'état actuel (si existant) pour le merge partiel.
    let existing_row = sqlx::query(
        "SELECT id, data_ciphertext FROM medical_record \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         ORDER BY updated_at DESC LIMIT 1",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (existing_id, existing_data) = match existing_row {
        None => (
            None,
            json!({"allergies": [], "treatments": [], "history": null}),
        ),
        Some(row) => {
            let record_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let ct: Vec<u8> = row
                .try_get("data_ciphertext")
                .map_err(|_| AppError::Internal)?;
            let data = decrypt_stub(&ct)
                .unwrap_or_else(|| json!({"allergies": [], "treatments": [], "history": null}));
            (Some(record_id), data)
        }
    };

    // Merge partiel : un champ absent du body conserve sa valeur courante.
    let merged = json!({
        "allergies": body.allergies
            .map(|v| json!(v))
            .unwrap_or_else(|| existing_data["allergies"].clone()),
        "treatments": body.treatments
            .map(|v| json!(v))
            .unwrap_or_else(|| existing_data["treatments"].clone()),
        "history": body.history
            .map(|s| json!(s))
            .unwrap_or_else(|| existing_data["history"].clone()),
    });

    let ciphertext = encrypt_stub(&merged);

    if let Some(record_id) = existing_id {
        // Mise à jour de l'enregistrement existant.
        sqlx::query(
            "UPDATE medical_record \
             SET data_ciphertext = $1, data_key_ref = 'stub-key-ref', updated_at = now() \
             WHERE id = $2",
        )
        .bind(&ciphertext)
        .bind(record_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    } else {
        // Création du premier enregistrement.
        sqlx::query(
            "INSERT INTO medical_record \
             (cabinet_id, patient_id, data_ciphertext, data_key_ref) \
             VALUES ($1, $2, $3, 'stub-key-ref')",
        )
        .bind(claims.cabinet_id)
        .bind(patient_id)
        .bind(&ciphertext)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Reconstruit la réponse depuis les données mergées (déjà en clair ici).
    let allergies = merged["allergies"].as_array().cloned().unwrap_or_default();
    let treatments = merged["treatments"].as_array().cloned().unwrap_or_default();
    let history = merged["history"].as_str().map(|s| s.to_string());

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        "medical record updated"
    );

    Ok(Json(MedicalRecordResponse {
        allergies,
        treatments,
        history,
    }))
}
