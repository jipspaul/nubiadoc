//! Handlers du questionnaire médical patient pré-consultation (#4108, table
//! `medical_questionnaire_submission`, migration 0180).
//!
//! Six routes :
//! - `GET /v1/account/medical-questionnaire/active-template?cabinet_id=…`
//!   (patient, #7159) : sert le schéma actif du cabinet donné (son propre
//!   modèle s'il en a un, sinon le standard global) — `resolve_
//!   active_questionnaire_template`, même résolution qu'à la création.
//! - `POST /v1/account/medical-questionnaire` (patient) : crée un brouillon,
//!   contre le modèle actif résolu au moment de la création (`template_id`/
//!   `version` figés sur la ligne, #7159 — un modèle qui évolue ensuite ne
//!   change jamais rétroactivement le schéma d'une soumission en cours).
//! - `GET /v1/account/medical-questionnaire?cabinet_id=…` (patient) : relit
//!   sa dernière soumission pour ce cabinet, quel que soit son statut
//!   (brouillon/soumise/revue) — le patient est auteur ET sujet de la
//!   donnée (RGPD art. 15), contrairement à la lecture cabinet ci-dessous.
//! - `PATCH /v1/account/medical-questionnaire` (patient) : modifie le
//!   brouillon existant, et/ou le soumet (`submit: true`). Validation contre
//!   le schéma du modèle de la soumission (#7159, voir `questionnaire_
//!   templates::validate_submission_against_schema`) : types toujours
//!   vérifiés, complétude (`required` + logique conditionnelle) uniquement
//!   à la soumission finale.
//! - `GET /v1/cabinet/patients/:id/medical-questionnaire` (praticien) : lit
//!   la dernière soumission — RLS (`medical_questionnaire_submission_cabinet_read`,
//!   migration 0180) masque déjà les brouillons, non soumis au cabinet.
//! - `POST /v1/cabinet/patients/:id/medical-questionnaire/review` (#4110,
//!   praticien) : valide ET importe la soumission dans `medical_record` —
//!   passe `status` à `reviewed` dans la même transaction. Revue humaine
//!   obligatoire : cette route n'est déclenchée que par un clic explicite
//!   côté praticien (bouton "Valider et importer"), jamais automatiquement.
//!
//! CRUD des modèles eux-mêmes (`questionnaire_template`, migration 0294,
//! #7160) : voir `questionnaire_templates.rs` (`/v1/cabinet/questionnaire-
//! templates`), pas ce module.
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
//!
//! Garde clinique anticoagulants (#4057, `consultation_act_create.rs`) :
//! INCHANGÉE par #7159 — elle lit `medical_record.treatments`/`medico_legal`
//! après import (`review_medical_questionnaire`/`merge_questionnaire_into_record`
//! ci-dessous, non modifiés), pas le `payload` brut ni le schéma du modèle.

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
    questionnaire_templates::{parse_questionnaire_schema, validate_submission_against_schema},
    AppState,
};

// ── Structures ────────────────────────────────────────────────────────────

/// Réponse commune aux routes de soumission.
#[derive(Serialize)]
pub struct MedicalQuestionnaireResponse {
    pub id: Uuid,
    pub cabinet_id: Uuid,
    pub payload: Value,
    pub status: String,
    pub submitted_at: Option<String>,
    /// Modèle contre lequel cette soumission a été validée (#7159). `None`
    /// uniquement pour d'anciennes lignes antérieures à la migration 0294 —
    /// en pratique toujours `Some` : cette dernière a backfillé le standard
    /// v1 sur toutes les lignes existantes.
    pub template_id: Option<Uuid>,
    pub template_version: Option<i32>,
}

/// Réponse de `GET /v1/account/medical-questionnaire/active-template` (#7159).
#[derive(Serialize)]
pub struct ActiveQuestionnaireTemplateResponse {
    pub template_id: Uuid,
    pub version: i32,
    pub title: String,
    pub schema: Value,
}

/// Corps de `POST /v1/account/medical-questionnaire`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateMedicalQuestionnaireBody {
    pub cabinet_id: Uuid,
    pub payload: Value,
}

/// Corps de `PATCH /v1/account/medical-questionnaire`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
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
    let template_id: Option<Uuid> = row.try_get("template_id").map_err(|_| AppError::Internal)?;
    let template_version: Option<i32> = row.try_get("version").map_err(|_| AppError::Internal)?;

    Ok(MedicalQuestionnaireResponse {
        id,
        cabinet_id,
        payload,
        status,
        submitted_at: submitted_at.map(|d| d.to_rfc3339()),
        template_id,
        template_version,
    })
}

/// Résout le modèle actif pour un cabinet dont `app.current_cabinet_id` est
/// déjà positionné dans `tx` : sa propre variante active si elle existe
/// (`tenant_isolation`), sinon le standard global (`global_template_read`,
/// `cabinet_id IS NULL`) — toujours présent (seedé par la migration 0294).
/// `Internal` si ni l'un ni l'autre n'est trouvé (base incohérente).
async fn resolve_active_questionnaire_template(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
) -> Result<(Uuid, i32, String, Value), AppError> {
    let row = sqlx::query(
        "SELECT id, version, title, schema FROM questionnaire_template \
         WHERE is_active = true \
         ORDER BY (cabinet_id IS NULL) ASC \
         LIMIT 1",
    )
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::Internal)?;

    Ok((
        row.try_get("id").map_err(|_| AppError::Internal)?,
        row.try_get("version").map_err(|_| AppError::Internal)?,
        row.try_get("title").map_err(|_| AppError::Internal)?,
        row.try_get("schema").map_err(|_| AppError::Internal)?,
    ))
}

/// Lit le schéma d'une version FIGÉE d'un modèle (celle référencée par une
/// soumission existante) — pas forcément la version active si le modèle a
/// évolué depuis (#7159 : une soumission garde le schéma tel qu'il était à
/// sa création, cf. doc de module). `Internal` si absent : la FK
/// `medical_questionnaire_submission.template_id` garantit son existence.
async fn fetch_template_schema_by_version(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    template_id: Uuid,
    version: i32,
) -> Result<Value, AppError> {
    let row =
        sqlx::query("SELECT schema FROM questionnaire_template WHERE id = $1 AND version = $2")
            .bind(template_id)
            .bind(version)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::Internal)?;

    row.try_get("schema").map_err(|_| AppError::Internal)
}

// ── POST /v1/account/medical-questionnaire ──────────────────────────────

/// `POST /v1/account/medical-questionnaire` — crée un brouillon pour le
/// cabinet donné, contre le modèle actif de ce cabinet (`resolve_
/// active_questionnaire_template`, #7159 — le patient n'a rien à préciser,
/// même contrat de body qu'avant l'ajout des modèles). `cabinet_id`
/// inexistant → `404` (#4343 — pré-vérifié plutôt que de laisser remonter la
/// FK `medical_questionnaire_submission(cabinet_id)` en `23503`/500, même
/// pattern que `lab_work_orders.rs`). `409` si un brouillon existe déjà pour
/// ce cabinet. `422 questionnaire_schema_violation` si un type de réponse ne
/// correspond pas au schéma du modèle résolu — seuls les TYPES sont
/// vérifiés à la création (brouillon), la complétude (`required`) est
/// vérifiée à la soumission finale (`PATCH … submit: true`).
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

    // Scope cabinet pour la RLS tenant_isolation de questionnaire_template
    // (la variante privée du cabinet, s'il en a une, n'est visible qu'avec
    // ce GUC positionné — cf. doc de module).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(body.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

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

    let (template_id, template_version, _title, schema) =
        resolve_active_questionnaire_template(&mut tx).await?;
    let questions = parse_questionnaire_schema(&schema).map_err(|_| AppError::Internal)?;
    validate_submission_against_schema(&questions, &body.payload, false)?;

    let row = sqlx::query(
        "INSERT INTO medical_questionnaire_submission \
           (cabinet_id, patient_account_id, payload, template_id, version) \
         VALUES ($1, $2, $3, $4, $5) \
         RETURNING id, cabinet_id, payload, status, submitted_at, template_id, version",
    )
    .bind(body.cabinet_id)
    .bind(claims.account_id)
    .bind(&body.payload)
    .bind(template_id)
    .bind(template_version)
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
        "SELECT id, cabinet_id, payload, status, submitted_at, template_id, version \
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

// ── GET /v1/account/medical-questionnaire/active-template ──────────────

/// `GET /v1/account/medical-questionnaire/active-template?cabinet_id=…`
/// (#7159) — sert au patient le schéma actif du cabinet donné, avant qu'il
/// ne remplisse le questionnaire (`resolve_active_questionnaire_template`,
/// même résolution que `create_medical_questionnaire`). `cabinet_id`
/// inexistant → `404`, même garde que `create_medical_questionnaire`.
pub async fn get_active_medical_questionnaire_template(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(query): Query<GetMedicalQuestionnaireQuery>,
) -> Result<Json<ActiveQuestionnaireTemplateResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cabinet_exists = sqlx::query("SELECT 1 FROM cabinet WHERE id = $1")
        .bind(query.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if cabinet_exists.is_none() {
        return Err(AppError::NotFound);
    }

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(query.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let (template_id, version, title, schema) =
        resolve_active_questionnaire_template(&mut tx).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(ActiveQuestionnaireTemplateResponse {
        template_id,
        version,
        title,
        schema,
    }))
}

// ── PATCH /v1/account/medical-questionnaire ─────────────────────────────

/// `PATCH /v1/account/medical-questionnaire` — modifie le brouillon existant
/// et/ou le soumet (`submit: true`). `404` si aucun brouillon n'existe pour
/// ce cabinet. Validation contre le schéma FIGÉ de la soumission (#7159,
/// `fetch_template_schema_by_version`) : si `payload` est fourni, ses types
/// sont vérifiés ; à la soumission (`submit: true`), le payload final
/// (`payload` fourni sinon celui déjà en base) doit satisfaire toutes les
/// questions `required` dont la `condition` est remplie —
/// `422 questionnaire_schema_violation` sinon, avant toute écriture.
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
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(body.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let current = sqlx::query(
        "SELECT payload, template_id, version FROM medical_questionnaire_submission \
         WHERE patient_account_id = $1 AND cabinet_id = $2 AND status = 'draft'",
    )
    .bind(claims.account_id)
    .bind(body.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let current_payload: Value = current.try_get("payload").map_err(|_| AppError::Internal)?;
    let template_id: Option<Uuid> = current
        .try_get("template_id")
        .map_err(|_| AppError::Internal)?;
    let template_version: Option<i32> =
        current.try_get("version").map_err(|_| AppError::Internal)?;

    // `template_id`/`version` sont toujours renseignés depuis la migration
    // 0294 (backfill + POST les fixe désormais systématiquement) — absents
    // uniquement sur une ligne pré-#7160 jamais backfillée, cas défensif où
    // la validation de schéma est simplement sautée (rien à valider contre).
    if let (Some(template_id), Some(template_version)) = (template_id, template_version) {
        let schema =
            fetch_template_schema_by_version(&mut tx, template_id, template_version).await?;
        let questions = parse_questionnaire_schema(&schema).map_err(|_| AppError::Internal)?;

        if body.submit {
            let final_payload = body.payload.clone().unwrap_or(current_payload);
            validate_submission_against_schema(&questions, &final_payload, true)?;
        } else if let Some(ref payload) = body.payload {
            validate_submission_against_schema(&questions, payload, false)?;
        }
    }

    let row = sqlx::query(
        "UPDATE medical_questionnaire_submission \
         SET payload = COALESCE($3, payload), \
             status = CASE WHEN $4 THEN 'submitted' ELSE status END, \
             submitted_at = CASE WHEN $4 THEN now() ELSE submitted_at END, \
             updated_at = now() \
         WHERE patient_account_id = $1 AND cabinet_id = $2 AND status = 'draft' \
         RETURNING id, cabinet_id, payload, status, submitted_at, template_id, version",
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
        "SELECT id, cabinet_id, payload, status, submitted_at, template_id, version \
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

/// `antecedents_chirurgicaux` → ajouté à `history` (préfixé, jamais un
/// remplacement — le texte saisi par le praticien ne doit jamais être écrasé
/// silencieusement).
/// `allergies`/`traitement_en_cours` → ajoutés comme nouvelles entrées aux
/// tableaux `allergies[]`/`treatments[]` (mêmes tableaux libres que
/// `medical_record.rs`, une entrée de plus n'efface rien d'existant). Toutes
/// les formes de saisie sont acceptées (#6917, cf. [questionnaire_entries]) :
/// texte libre, liste de chaînes, objets `{"substance"|"text"|"name"|"label",
/// "severity"?}` — chaque entrée importée porte `text` + `source =
/// "questionnaire_patient"` (+ `severity` si déclarée), forme lue par
/// `consultation_context::allergy_alert` pour les pastilles `medical_alerts`.
/// `ald`/`anticoagulants`/`grossesse`/`maladie_cardiovasculaire` → OR logique
/// avec le flag existant (ne redescend jamais un flag déjà à `true` à
/// `false` sur la foi d'une case non cochée côté patient). Clés alignées sur
/// le standard seedé par la migration 0294 (#7160) —
/// `antecedents_chirurgicaux`/`traitement_en_cours`/`anticoagulants`, pas les
/// anciennes clés du questionnaire fixe pré-#7159 (#7505). `grossesse`/
/// `maladie_cardiovasculaire` (`safety_flag: true`) importés au même titre
/// (#7525).
/// Normalise un champ libre du questionnaire (`allergies`,
/// `traitements_en_cours`) en entrées de dossier `{"text": …, "source":
/// "questionnaire_patient"}` (+ `"severity"` quand l'objet en porte une).
///
/// Formes acceptées (#6917) — le `payload` du questionnaire est un objet
/// libre, aucun vocabulaire fermé n'est imposé au patient :
/// - chaîne : une entrée (texte libre, jamais découpé — un libellé peut
///   contenir des virgules) ;
/// - tableau : une entrée par élément (chaîne ou objet) ;
/// - objet : une entrée, libellé = première clé non vide parmi `substance`,
///   `text`, `name`, `label`.
///
/// Les éléments vides/illisibles sont ignorés — jamais d'entrée inventée.
fn questionnaire_entries(value: &Value) -> Vec<Value> {
    const LABEL_KEYS: [&str; 4] = ["substance", "text", "name", "label"];

    fn one(item: &Value) -> Option<Value> {
        let (text, severity) = if let Some(s) = item.as_str() {
            (s.trim(), None)
        } else if item.is_object() {
            let text = LABEL_KEYS
                .iter()
                .filter_map(|k| item.get(k).and_then(|v| v.as_str()))
                .map(str::trim)
                .find(|s| !s.is_empty())?;
            let severity = item
                .get("severity")
                .and_then(|v| v.as_str())
                .map(|s| s.trim().to_lowercase())
                .filter(|s| !s.is_empty());
            (text, severity)
        } else {
            return None;
        };
        if text.is_empty() {
            return None;
        }
        let mut entry = serde_json::json!({"text": text, "source": "questionnaire_patient"});
        if let (Some(severity), Some(obj)) = (severity, entry.as_object_mut()) {
            obj.insert("severity".to_string(), Value::String(severity));
        }
        Some(entry)
    }

    match value {
        Value::Array(items) => items.iter().filter_map(one).collect(),
        other => one(other).into_iter().collect(),
    }
}

fn merge_questionnaire_into_record(existing: &Value, payload: &Value) -> Value {
    let existing_history = existing["history"].as_str().unwrap_or("").to_string();
    let antecedents = payload["antecedents_chirurgicaux"]
        .as_str()
        .unwrap_or("")
        .trim();
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
    allergies.extend(questionnaire_entries(&payload["allergies"]));

    let mut treatments = existing["treatments"]
        .as_array()
        .cloned()
        .unwrap_or_default();
    treatments.extend(questionnaire_entries(&payload["traitement_en_cours"]));

    let mut medico_legal: MedicoLegalFlags = existing
        .get("medico_legal")
        .and_then(|v| serde_json::from_value(v.clone()).ok())
        .unwrap_or_default();
    medico_legal.ald = medico_legal.ald || payload["ald"].as_bool().unwrap_or(false);
    medico_legal.anticoagulants =
        medico_legal.anticoagulants || payload["anticoagulants"].as_bool().unwrap_or(false);
    medico_legal.grossesse =
        medico_legal.grossesse || payload["grossesse"].as_bool().unwrap_or(false);
    medico_legal.maladie_cardiovasculaire = medico_legal.maladie_cardiovasculaire
        || payload["maladie_cardiovasculaire"]
            .as_bool()
            .unwrap_or(false);

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
         RETURNING id, cabinet_id, payload, status, submitted_at, template_id, version",
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

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn questionnaire_entries_accepts_free_text_list_and_objects() {
        assert_eq!(
            questionnaire_entries(&json!(" Pénicilline, latex ")),
            vec![json!({"text": "Pénicilline, latex", "source": "questionnaire_patient"})]
        );
        assert_eq!(
            questionnaire_entries(&json!([
                "latex",
                { "substance": "pénicilline", "severity": "High" },
                { "text": "iode" },
                { "name": "" },
                { "label": "aspirine" },
                "",
                42,
                null
            ])),
            vec![
                json!({"text": "latex", "source": "questionnaire_patient"}),
                json!({"text": "pénicilline", "source": "questionnaire_patient", "severity": "high"}),
                json!({"text": "iode", "source": "questionnaire_patient"}),
                json!({"text": "aspirine", "source": "questionnaire_patient"}),
            ]
        );
        assert_eq!(
            questionnaire_entries(&json!({"substance": "nickel"})),
            vec![json!({"text": "nickel", "source": "questionnaire_patient"})]
        );
    }

    #[test]
    fn questionnaire_entries_ignores_empty_or_unreadable_input() {
        assert!(questionnaire_entries(&json!("")).is_empty());
        assert!(questionnaire_entries(&json!("   ")).is_empty());
        assert!(questionnaire_entries(&json!(null)).is_empty());
        assert!(questionnaire_entries(&json!(true)).is_empty());
        assert!(questionnaire_entries(&json!([])).is_empty());
        assert!(questionnaire_entries(&json!({"severity": "high"})).is_empty());
    }

    #[test]
    fn merge_questionnaire_keeps_existing_entries_and_appends_allergies() {
        let existing = json!({
            "allergies": [{"severity": "high", "substance": "pénicilline"}],
            "treatments": [],
            "history": "Diabète",
            "medico_legal": {"ald": false, "anticoagulants": false}
        });
        let payload = json!({
            "antecedents_chirurgicaux": "",
            "allergies": ["latex"],
            "traitement_en_cours": "Metformine",
            "ald": true,
            "anticoagulants": true
        });
        let merged = merge_questionnaire_into_record(&existing, &payload);
        assert_eq!(merged["allergies"].as_array().map(Vec::len), Some(2));
        assert_eq!(merged["allergies"][0]["substance"], "pénicilline");
        assert_eq!(merged["allergies"][1]["text"], "latex");
        assert_eq!(merged["treatments"][0]["text"], "Metformine");
        assert_eq!(merged["history"], "Diabète");
        assert_eq!(merged["medico_legal"]["ald"], true);
        assert_eq!(merged["medico_legal"]["anticoagulants"], true);
    }

    #[test]
    fn merge_questionnaire_imports_surgical_history_and_anticoagulants() {
        // Clés du standard seedé par la migration 0294 (#7160) — #7505 :
        // avant ce fix, ces trois clés étaient silencieusement jetées car
        // merge_questionnaire_into_record lisait encore les clés de l'ancien
        // questionnaire fixe pré-#7159 (antecedents/traitements_en_cours/ald).
        let existing = json!({
            "allergies": [],
            "treatments": [],
            "history": "",
            "medico_legal": {"ald": true, "anticoagulants": false}
        });
        let payload = json!({
            "antecedents_chirurgicaux": "Pose de stent 2019",
            "traitement_en_cours": "Kardegic 75mg",
            "anticoagulants": true
        });
        let merged = merge_questionnaire_into_record(&existing, &payload);
        assert_eq!(
            merged["history"],
            "[Questionnaire patient] Pose de stent 2019"
        );
        assert_eq!(merged["treatments"][0]["text"], "Kardegic 75mg");
        assert_eq!(merged["medico_legal"]["anticoagulants"], true);
    }

    #[test]
    fn merge_questionnaire_imports_grossesse_and_maladie_cardiovasculaire() {
        // #7525 : ces deux clés du standard seedé (migration 0294) portent
        // safety_flag: true mais étaient encore silencieusement jetées après
        // #7505 (qui n'avait réaligné que antecedents/traitement/anticoagulants).
        let existing = json!({
            "allergies": [],
            "treatments": [],
            "history": "",
            "medico_legal": {"ald": false, "anticoagulants": false}
        });
        let payload = json!({
            "grossesse": true,
            "maladie_cardiovasculaire": true
        });
        let merged = merge_questionnaire_into_record(&existing, &payload);
        assert_eq!(merged["medico_legal"]["grossesse"], true);
        assert_eq!(merged["medico_legal"]["maladie_cardiovasculaire"], true);
    }

    #[test]
    fn merge_questionnaire_never_downgrades_grossesse_or_cardio_flag() {
        let existing = json!({
            "allergies": [],
            "treatments": [],
            "history": "",
            "medico_legal": {"grossesse": true, "maladie_cardiovasculaire": true}
        });
        let payload = json!({});
        let merged = merge_questionnaire_into_record(&existing, &payload);
        assert_eq!(merged["medico_legal"]["grossesse"], true);
        assert_eq!(merged["medico_legal"]["maladie_cardiovasculaire"], true);
    }
}
