//! Handlers du questionnaire médical patient pré-consultation (#4108, table
//! `medical_questionnaire_submission`, migration 0180).
//!
//! Cinq routes :
//! - `POST /v1/account/medical-questionnaire` (patient) : crée un brouillon.
//! - `GET /v1/account/medical-questionnaire?cabinet_id=…` (patient) : relit
//!   sa dernière soumission pour ce cabinet, quel que soit son statut
//!   (brouillon/soumise/revue) — le patient est auteur ET sujet de la
//!   donnée (RGPD art. 15), contrairement à la lecture cabinet ci-dessous.
//! - `PATCH /v1/account/medical-questionnaire` (patient) : modifie le
//!   brouillon existant, et/ou le soumet (`submit: true`).
//! - `GET /v1/cabinet/patients/:id/medical-questionnaire` (praticien) : lit
//!   la dernière soumission — RLS (`medical_questionnaire_submission_cabinet_read`,
//!   migration 0180) masque déjà les brouillons, non soumis au cabinet.
//! - `POST /v1/cabinet/patients/:id/medical-questionnaire/review` (#4110,
//!   praticien) : valide ET importe la soumission dans `medical_record` —
//!   passe `status` à `reviewed` dans la même transaction. Revue humaine
//!   obligatoire : cette route n'est déclenchée que par un clic explicite
//!   côté praticien (bouton "Valider et importer"), jamais automatiquement.
//!
//! Un seul brouillon actif par (patient_account_id, cabinet_id) — appliqué
//! par l'index unique partiel `medical_questionnaire_submission_one_draft_uidx`
//! (migration 0235, #5732) : `POST` fait un SELECT applicatif pour renvoyer
//! un 409 rapide dans le cas courant, mais c'est l'index qui garantit
//! l'invariant sous concurrence (23505 catché → même 409). `PATCH` renvoie
//! 404 si aucun brouillon n'existe (ou qu'il a déjà été soumis — pas de
//! modification après soumission, non demandée par l'issue).
//!
//! Garde praticien identique à `dental_chart.rs`/`periodontal_chart.rs`
//! (R.4127-72) : un `appointment` (passé ou à venir) avec ce patient est
//! requis — un rendez-vous réservé suffit à autoriser la lecture du
//! questionnaire avant la consultation, cas d'usage central de cette issue.

use axum::{
    extract::{Path, Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, ProPractitionerClaims},
    medical_record::{decrypt_stub, encrypt_stub, MedicoLegalFlags},
    AppState,
};

// ── Structures ────────────────────────────────────────────────────────────

/// Réponse commune aux trois routes.
#[derive(Serialize)]
pub struct MedicalQuestionnaireResponse {
    pub id: Uuid,
    pub cabinet_id: Uuid,
    pub payload: Value,
    pub status: String,
    pub submitted_at: Option<String>,
}

/// Corps de `POST /v1/account/medical-questionnaire`.
#[derive(Deserialize)]
pub struct CreateMedicalQuestionnaireBody {
    pub cabinet_id: Uuid,
    pub payload: Value,
}

/// Corps de `PATCH /v1/account/medical-questionnaire`.
#[derive(Deserialize)]
pub struct PatchMedicalQuestionnaireBody {
    pub cabinet_id: Uuid,
    pub payload: Option<Value>,
    #[serde(default)]
    pub submit: bool,
}

/// `payload` : objet libre (questionnaire libre, aucun vocabulaire fermé
/// n'est demandé par l'issue) — seule contrainte : un objet, pas un
/// scalaire/tableau (même garde minimale que `periodontal_chart`), et
/// aucune chaîne imbriquée ne contient d'octet NUL (Postgres jsonb le
/// refuse nativement, sinon 500 masqué en écriture, #4809).
fn validate_payload(value: &Value) -> Result<(), AppError> {
    if !value.is_object() {
        return Err(AppError::ValidationError);
    }
    crate::text_validation::reject_nul_byte_in_json(value)?;
    Ok(())
}

fn row_to_response(row: sqlx::postgres::PgRow) -> Result<MedicalQuestionnaireResponse, AppError> {
    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let payload: Value = row.try_get("payload").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let submitted_at: Option<chrono::DateTime<chrono::Utc>> = row
        .try_get("submitted_at")
        .map_err(|_| AppError::Internal)?;

    Ok(MedicalQuestionnaireResponse {
        id,
        cabinet_id,
        payload,
        status,
        submitted_at: submitted_at.map(|d| d.to_rfc3339()),
    })
}

// ── POST /v1/account/medical-questionnaire ──────────────────────────────

/// `POST /v1/account/medical-questionnaire` — crée un brouillon pour le
/// cabinet donné. `cabinet_id` inexistant → `404` (#4343 — pré-vérifié
/// plutôt que de laisser remonter la FK `medical_questionnaire_submission
/// (cabinet_id)` en `23503`/500, même pattern que `lab_work_orders.rs`).
/// `409` si un brouillon existe déjà pour ce cabinet.
pub async fn create_medical_questionnaire(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<CreateMedicalQuestionnaireBody>,
) -> Result<Json<MedicalQuestionnaireResponse>, AppError> {
    validate_payload(&body.payload)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cabinet_exists = sqlx::query("SELECT 1 FROM cabinet WHERE id = $1")
        .bind(body.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if cabinet_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let existing_draft = sqlx::query(
        "SELECT 1 FROM medical_questionnaire_submission \
         WHERE patient_account_id = $1 AND cabinet_id = $2 AND status = 'draft'",
    )
    .bind(claims.account_id)
    .bind(body.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if existing_draft.is_some() {
        return Err(AppError::MedicalQuestionnaireDraftExists);
    }

    let row = sqlx::query(
        "INSERT INTO medical_questionnaire_submission \
           (cabinet_id, patient_account_id, payload) \
         VALUES ($1, $2, $3) \
         RETURNING id, cabinet_id, payload, status, submitted_at",
    )
    .bind(body.cabinet_id)
    .bind(claims.account_id)
    .bind(&body.payload)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        // #5732 : le SELECT ci-dessus est une race TOCTOU sous requêtes
        // concurrentes (double-tap/retry) — l'index unique partiel
        // medical_questionnaire_submission_one_draft_uidx (migration 0235)
        // est le garde-fou réel ; ce catch mappe sa violation (23505) sur le
        // même 409 métier que le SELECT, au lieu d'un 500.
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            AppError::MedicalQuestionnaireDraftExists
        }
        _ => AppError::Internal,
    })?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        cabinet_id = %body.cabinet_id,
        "medical questionnaire draft created"
    );

    Ok(Json(row_to_response(row)?))
}

// ── GET /v1/account/medical-questionnaire ───────────────────────────────

/// Query de `GET /v1/account/medical-questionnaire`.
#[derive(Deserialize)]
pub struct GetMedicalQuestionnaireQuery {
    pub cabinet_id: Uuid,
}

/// `GET /v1/account/medical-questionnaire` — dernière soumission du patient
/// pour ce cabinet, quel que soit son statut (`draft`/`submitted`/`reviewed`)
/// : le patient, auteur ET sujet de la donnée, doit pouvoir la relire même
/// une fois soumise — `RLS medical_questionnaire_submission_patient_owner`
/// (migration 0180) l'autorise déjà sur tous les statuts, contrairement à
/// `medical_questionnaire_submission_cabinet_read` qui masque les brouillons
/// au cabinet. `404` si aucune soumission n'existe pour ce cabinet.
pub async fn get_medical_questionnaire(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(query): Query<GetMedicalQuestionnaireQuery>,
) -> Result<Json<MedicalQuestionnaireResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, cabinet_id, payload, status, submitted_at \
         FROM medical_questionnaire_submission \
         WHERE patient_account_id = $1 AND cabinet_id = $2 \
         ORDER BY updated_at DESC LIMIT 1",
    )
    .bind(claims.account_id)
    .bind(query.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        return Err(AppError::NotFound);
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(row_to_response(row)?))
}

// ── PATCH /v1/account/medical-questionnaire ─────────────────────────────

/// `PATCH /v1/account/medical-questionnaire` — modifie le brouillon existant
/// et/ou le soumet (`submit: true`). `404` si aucun brouillon n'existe pour
/// ce cabinet.
pub async fn patch_medical_questionnaire(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<PatchMedicalQuestionnaireBody>,
) -> Result<Json<MedicalQuestionnaireResponse>, AppError> {
    if let Some(ref payload) = body.payload {
        validate_payload(payload)?;
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "UPDATE medical_questionnaire_submission \
         SET payload = COALESCE($3, payload), \
             status = CASE WHEN $4 THEN 'submitted' ELSE status END, \
             submitted_at = CASE WHEN $4 THEN now() ELSE submitted_at END, \
             updated_at = now() \
         WHERE patient_account_id = $1 AND cabinet_id = $2 AND status = 'draft' \
         RETURNING id, cabinet_id, payload, status, submitted_at",
    )
    .bind(claims.account_id)
    .bind(body.cabinet_id)
    .bind(&body.payload)
    .bind(body.submit)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        return Err(AppError::NotFound);
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        cabinet_id = %body.cabinet_id,
        submitted = body.submit,
        "medical questionnaire draft updated"
    );

    Ok(Json(row_to_response(row)?))
}

// ── GET /v1/cabinet/patients/:id/medical-questionnaire ──────────────────

async fn ensure_practitioner_care_relationship(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    patient_id: Uuid,
    cabinet_id: Uuid,
    user_id: Uuid,
) -> Result<Uuid, AppError> {
    let patient = sqlx::query(
        "SELECT patient_account_id FROM patient \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(patient) = patient else {
        return Err(AppError::NotFound);
    };

    let patient_account_id: Option<Uuid> = patient
        .try_get("patient_account_id")
        .map_err(|_| AppError::Internal)?;
    let Some(patient_account_id) = patient_account_id else {
        return Err(AppError::NotFound);
    };

    // Même garde R.4127-72 que dental_chart.rs/periodontal_chart.rs : un
    // appointment (passé OU à venir) avec ce patient dans ce cabinet suffit —
    // un RDV réservé autorise la lecture du questionnaire avant qu'il n'ait
    // lieu, cas d'usage central de cette issue (pré-consultation).
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

    Ok(patient_account_id)
}

/// `GET /v1/cabinet/patients/:id/medical-questionnaire` — dernière
/// soumission visible du patient (RLS masque déjà les brouillons).
/// `404` si le patient n'existe pas dans ce cabinet, n'a pas de compte
/// plateforme lié, ou n'a aucune soumission visible.
pub async fn get_cabinet_medical_questionnaire(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<MedicalQuestionnaireResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let patient_account_id =
        ensure_practitioner_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub)
            .await?;

    let row = sqlx::query(
        "SELECT id, cabinet_id, payload, status, submitted_at \
         FROM medical_questionnaire_submission \
         WHERE patient_account_id = $1 AND cabinet_id = $2 \
         ORDER BY submitted_at DESC LIMIT 1",
    )
    .bind(patient_account_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        return Err(AppError::NotFound);
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        "medical questionnaire read"
    );

    Ok(Json(row_to_response(row)?))
}

// ── POST /v1/cabinet/patients/:id/medical-questionnaire/review ──────────

/// `antecedents` → ajouté à `history` (préfixé, jamais un remplacement — le
/// texte saisi par le praticien ne doit jamais être écrasé silencieusement).
/// `allergies`/`traitements_en_cours` → ajoutés comme nouvelle entrée aux
/// tableaux `allergies[]`/`treatments[]` (mêmes tableaux libres que
/// `medical_record.rs`, une entrée de plus n'efface rien d'existant).
/// `ald` → OR logique avec le flag existant (ne redescend jamais un flag
/// déjà à `true` à `false` sur la foi d'une case non cochée côté patient).
fn merge_questionnaire_into_record(existing: &Value, payload: &Value) -> Value {
    let existing_history = existing["history"].as_str().unwrap_or("").to_string();
    let antecedents = payload["antecedents"].as_str().unwrap_or("").trim();
    let merged_history = if antecedents.is_empty() {
        if existing_history.is_empty() {
            None
        } else {
            Some(existing_history)
        }
    } else {
        let addition = format!("[Questionnaire patient] {antecedents}");
        Some(if existing_history.is_empty() {
            addition
        } else {
            format!("{existing_history}\n\n{addition}")
        })
    };

    let mut allergies = existing["allergies"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    let allergies_text = payload["allergies"].as_str().unwrap_or("").trim();
    if !allergies_text.is_empty() {
        allergies
            .push(serde_json::json!({"text": allergies_text, "source": "questionnaire_patient"}));
    }

    let mut treatments = existing["treatments"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    let traitements_text = payload["traitements_en_cours"]
        .as_str()
        .unwrap_or("")
        .trim();
    if !traitements_text.is_empty() {
        treatments
            .push(serde_json::json!({"text": traitements_text, "source": "questionnaire_patient"}));
    }

    let mut medico_legal: MedicoLegalFlags = existing
        .get("medico_legal")
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();
    medico_legal.ald = medico_legal.ald || payload["ald"].as_bool().unwrap_or(false);

    serde_json::json!({
        "allergies": allergies,
        "treatments": treatments,
        "history": merged_history,
        "medico_legal": medico_legal,
    })
}

/// `POST /v1/cabinet/patients/:id/medical-questionnaire/review` (#4110) —
/// valide et importe la dernière soumission dans `medical_record`, dans la
/// même transaction que le passage de `status` à `reviewed`.
///
/// `409` si la dernière soumission visible est déjà `reviewed` (rien à
/// valider). `404` si aucune soumission visible n'existe pour ce patient.
pub async fn review_medical_questionnaire(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<MedicalQuestionnaireResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let patient_account_id =
        ensure_practitioner_care_relationship(&mut tx, patient_id, claims.cabinet_id, claims.sub)
            .await?;

    let submission_row = sqlx::query(
        "SELECT id, payload, status FROM medical_questionnaire_submission \
         WHERE patient_account_id = $1 AND cabinet_id = $2 \
         ORDER BY submitted_at DESC LIMIT 1",
    )
    .bind(patient_account_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(submission_row) = submission_row else {
        return Err(AppError::NotFound);
    };

    let submission_id: Uuid = submission_row
        .try_get("id")
        .map_err(|_| AppError::Internal)?;
    let status: String = submission_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let payload: Value = submission_row
        .try_get("payload")
        .map_err(|_| AppError::Internal)?;

    if status != "submitted" {
        return Err(AppError::InvalidStatus);
    }

    let existing_record_row = sqlx::query(
        "SELECT id, data_ciphertext FROM medical_record \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         ORDER BY updated_at DESC LIMIT 1",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (existing_record_id, existing_data) = match existing_record_row {
        None => (None, serde_json::json!({})),
        Some(row) => {
            let record_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let ciphertext: Vec<u8> = row
                .try_get("data_ciphertext")
                .map_err(|_| AppError::Internal)?;
            let data = decrypt_stub(&ciphertext).unwrap_or_else(|| serde_json::json!({}));
            (Some(record_id), data)
        }
    };

    let merged = merge_questionnaire_into_record(&existing_data, &payload);
    let ciphertext = encrypt_stub(&merged);

    if let Some(record_id) = existing_record_id {
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

    let reviewed_row = sqlx::query(
        "UPDATE medical_questionnaire_submission \
         SET status = 'reviewed', updated_at = now() \
         WHERE id = $1 \
         RETURNING id, cabinet_id, payload, status, submitted_at",
    )
    .bind(submission_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, 'practitioner', 'import_medical_questionnaire', 'medical_record', $3, $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(patient_id)
    .bind(serde_json::json!({"submission_id": submission_id}))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        submission_id = %submission_id,
        "medical questionnaire reviewed and imported"
    );

    Ok(Json(row_to_response(reviewed_row)?))
}
