//! Handlers `GET /v1/cabinet/patients`, `POST /v1/cabinet/patients`,
//! `POST /v1/cabinet/patients/:id/notes`,
//! `GET /v1/cabinet/patients/:id`,
//! `GET /v1/cabinet/patients/:id/documents`,
//! `POST /v1/cabinet/patients/:id/documents`.

use std::sync::Arc;

use axum::{
    extract::{Extension, Multipart, Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims, ProSecretaryPlusClaims},
    AppState, StorageClient,
};

#[derive(Deserialize)]
pub struct ListPatientsQuery {
    /// Filtre textuel sur nom/prénom (ILIKE).
    pub q: Option<String>,
    /// `in_treatment` ou `to_review`.
    pub filter: Option<String>,
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

#[derive(Serialize)]
pub struct PatientItem {
    pub id: Uuid,
    pub first_name: String,
    pub last_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub birth_date: Option<String>,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

#[derive(Serialize)]
pub struct ListPatientsResponse {
    pub data: Vec<PatientItem>,
    pub page: PageInfo,
}

fn encode_cursor(created_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", created_at.timestamp_micros(), id)
}

fn decode_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/cabinet/patients` — liste paginée des dossiers patients du cabinet.
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT, jamais du query string (invariant tenancy).
/// RLS scopé via `app.current_cabinet_id`. Cloisonnement R.4127-72 : fiche admin uniquement
/// (données cliniques chiffrées non exposées ici).
/// Query : `q` (ILIKE nom/prénom), `filter=in_treatment|to_review`, `limit`, `cursor`.
pub async fn list_cabinet_patients(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<ListPatientsQuery>,
) -> Result<Json<ListPatientsResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let fetch_limit = limit + 1;

    let cursor = params.cursor.as_deref().and_then(decode_cursor);
    let (cursor_at, cursor_id) = cursor
        .map(|(at, id)| (Some(at), Some(id)))
        .unwrap_or((None, None));

    // %q% search — ILIKE wildcards on user input are acceptable (parameterised query).
    let search_pattern = params.q.as_deref().map(|q| format!("%{}%", q));

    // Filtre statut : in_treatment = plan de traitement en cours ;
    // to_review = note clinique non validée (R.4127-72, praticien uniquement en pratique).
    let filter_clause = match params.filter.as_deref() {
        Some("in_treatment") => {
            " AND EXISTS (\
              SELECT 1 FROM treatment_plan tp2 \
              WHERE tp2.patient_id = p.id \
                AND tp2.status = 'in_progress' \
                AND tp2.deleted_at IS NULL\
            )"
        }
        Some("to_review") => {
            " AND EXISTS (\
              SELECT 1 FROM clinical_note cn \
              WHERE cn.patient_id = p.id \
                AND cn.validated_at IS NULL \
                AND cn.deleted_at IS NULL\
            )"
        }
        _ => "",
    };

    // $1 = fetch_limit, $2 = search_pattern (NULL → no filter), $3/$4 = cursor (NULL → no cursor).
    let sql = format!(
        "SELECT p.id, p.first_name, p.last_name, p.birth_date, p.created_at \
         FROM patient p \
         WHERE p.deleted_at IS NULL\
         {filter_clause} \
         AND ($2::text IS NULL OR p.first_name ILIKE $2 OR p.last_name ILIKE $2) \
         AND ($3::timestamptz IS NULL \
              OR p.created_at < $3 \
              OR (p.created_at = $3 AND p.id < $4)) \
         ORDER BY p.created_at DESC, p.id DESC \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&sql)
        .bind(fetch_limit)
        .bind(search_pattern.as_deref())
        .bind(cursor_at)
        .bind(cursor_id)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<PatientItem> = Vec::with_capacity(visible.len());
    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
        let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
        let birth_date: Option<chrono::NaiveDate> =
            row.try_get("birth_date").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        last_created_at = Some(created_at);
        last_id = Some(id);

        data.push(PatientItem {
            id,
            first_name,
            last_name,
            birth_date: birth_date.map(|d| d.to_string()),
            created_at: created_at.to_rfc3339(),
        });
    }

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        role = %claims.role,
        count = data.len(),
        has_more,
        "cabinet patients listed"
    );

    Ok(Json(ListPatientsResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}

// ── POST /v1/cabinet/patients ─────────────────────────────────────────────────

/// Corps de la requête `POST /v1/cabinet/patients`.
#[derive(Deserialize)]
pub struct AttachPatientBody {
    /// Identifiant du compte patient plateforme à rattacher au cabinet.
    pub patient_account_id: Uuid,
    /// Note administrative optionnelle stockée dans `contact->>'note'`.
    pub note: Option<String>,
}

/// Réponse de `POST /v1/cabinet/patients`.
#[derive(Serialize)]
pub struct AttachPatientResponse {
    pub patient_id: Uuid,
}

/// `POST /v1/cabinet/patients` — crée ou rattache un dossier patient au cabinet.
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT, `patient_account_id` depuis le body.
/// Idempotent : si un dossier existe déjà pour ce `patient_account_id` dans ce cabinet,
/// retourne le `patient_id` existant avec `201`.
/// `first_name`/`last_name` copiés depuis `patient_account` (accessible via
/// `app.current_account_id` temporaire dans la transaction).
/// `patient_account_id` inexistant ou inaccessible → `404`.
pub async fn create_cabinet_patient(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<AttachPatientBody>,
) -> Result<(StatusCode, Json<AttachPatientResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope cabinet pour la RLS tenant_isolation sur patient.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Idempotence : si un dossier existe déjà pour ce patient_account dans ce cabinet,
    // on retourne l'id existant sans insérer de doublon.
    let existing = sqlx::query(
        "SELECT id FROM patient \
         WHERE patient_account_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(body.patient_account_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(row) = existing {
        let patient_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        tracing::info!(
            cabinet_id = %claims.cabinet_id,
            patient_account_id = %body.patient_account_id,
            patient_id = %patient_id,
            "cabinet patient already attached (idempotent)"
        );
        return Ok((
            StatusCode::CREATED,
            Json(AttachPatientResponse { patient_id }),
        ));
    }

    // Lecture de patient_account via app.current_account_id (policy account_self_select).
    // On pose temporairement le GUC au patient_account_id fourni pour lire first/last name.
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(body.patient_account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let account_row =
        sqlx::query("SELECT first_name, last_name FROM patient_account WHERE id = $1")
            .bind(body.patient_account_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;

    let first_name: String = account_row
        .try_get("first_name")
        .map_err(|_| AppError::Internal)?;
    let last_name: String = account_row
        .try_get("last_name")
        .map_err(|_| AppError::Internal)?;

    // contact JSONB : { note? }
    let contact: serde_json::Value = match body.note.as_deref() {
        Some(n) => serde_json::json!({ "note": n }),
        None => serde_json::json!({}),
    };

    // INSERT patient — RLS tenant_isolation (current_cabinet_id déjà positionné).
    let row = sqlx::query(
        "INSERT INTO patient (cabinet_id, patient_account_id, first_name, last_name, contact) \
         VALUES ($1, $2, $3, $4, $5) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.patient_account_id)
    .bind(&first_name)
    .bind(&last_name)
    .bind(&contact)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let patient_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_account_id = %body.patient_account_id,
        patient_id = %patient_id,
        "cabinet patient created"
    );

    Ok((
        StatusCode::CREATED,
        Json(AttachPatientResponse { patient_id }),
    ))
}

// ── GET /v1/cabinet/patients/:id/notes ───────────────────────────────────────

#[derive(Deserialize)]
pub struct ListNotesQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

#[derive(Serialize)]
pub struct ClinicalNoteItem {
    pub note_id: Uuid,
    pub note_kind: String,
    pub text: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tooth: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub act_ref: Option<Value>,
    pub author_id: Uuid,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct ListNotesResponse {
    pub data: Vec<ClinicalNoteItem>,
    pub page: PageInfo,
}

/// Inverse du stub chiffrement : supprime le préfixe `STUB_ENC:` et XOR 0xFF.
/// Retourne `None` si le ciphertext ne commence pas par le préfixe attendu.
fn stub_decrypt(ciphertext: &[u8]) -> Option<String> {
    let prefix = b"STUB_ENC:";
    let payload = ciphertext.strip_prefix(prefix.as_ref())?;
    let plain: Vec<u8> = payload.iter().map(|b| b ^ 0xFF).collect();
    String::from_utf8(plain).ok()
}

/// `GET /v1/cabinet/patients/:id/notes` — liste paginée (cursor) des notes cliniques.
///
/// Praticien uniquement (R.4127-72) — secrétaire → 403.
/// Exclut les notes soft-deleted (`deleted_at IS NOT NULL`).
/// Déchiffre `content_ciphertext` → `text` via stub (KMS à NUB-T3).
/// Patient inexistant ou hors tenant → 404.
pub async fn list_patient_notes(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
    Query(params): Query<ListNotesQuery>,
) -> Result<Json<ListNotesResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let fetch_limit = limit + 1;

    let cursor = params.cursor.as_deref().and_then(decode_cursor);
    let (cursor_at, cursor_id) = cursor
        .map(|(at, id)| (Some(at), Some(id)))
        .unwrap_or((None, None));

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le tenant).
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

    let rows = sqlx::query(
        "SELECT id, note_kind, content_ciphertext, tooth, act_ref, author_id, created_at \
         FROM clinical_note \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         AND ($3::timestamptz IS NULL \
              OR created_at < $3 \
              OR (created_at = $3 AND id < $4)) \
         ORDER BY created_at DESC, id DESC \
         LIMIT $5",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .bind(cursor_at)
    .bind(cursor_id)
    .bind(fetch_limit)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<ClinicalNoteItem> = Vec::with_capacity(visible.len());
    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let note_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let note_kind: String = row.try_get("note_kind").map_err(|_| AppError::Internal)?;
        let ciphertext: Vec<u8> = row
            .try_get("content_ciphertext")
            .map_err(|_| AppError::Internal)?;
        let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
        let act_ref: Option<Value> = row.try_get("act_ref").map_err(|_| AppError::Internal)?;
        let author_id: Uuid = row.try_get("author_id").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        let text = stub_decrypt(&ciphertext).unwrap_or_default();

        last_created_at = Some(created_at);
        last_id = Some(note_id);

        data.push(ClinicalNoteItem {
            note_id,
            note_kind,
            text,
            tooth,
            act_ref,
            author_id,
            created_at: created_at.to_rfc3339(),
        });
    }

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        count = data.len(),
        has_more,
        "clinical notes listed"
    );

    Ok(Json(ListNotesResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}

// ── POST /v1/cabinet/patients/:id/notes ──────────────────────────────────────

/// Corps de la requête `POST /v1/cabinet/patients/:id/notes`.
#[derive(Deserialize)]
pub struct AddClinicalNoteBody {
    /// Type de note : `"observation"` ou `"act"`.
    pub note_kind: String,
    /// Texte libre de la note (chiffré avant stockage).
    pub text: String,
    /// Numérotation ISO 3950, optionnelle (notes de type `"act"`).
    pub tooth: Option<String>,
    /// Référence d'acte JSONB : `{ label, ccam?, quote_item_id? }` — optionnel.
    pub act_ref: Option<Value>,
}

/// Réponse de `POST /v1/cabinet/patients/:id/notes`.
#[derive(Serialize)]
pub struct AddClinicalNoteResponse {
    pub note_id: Uuid,
    pub created_at: String,
}

/// `POST /v1/cabinet/patients/:id/notes` — ajoute une note clinique chiffrée.
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
/// Chiffrement colonne : stub `"STUB_ENC:" + UTF-8` en dev — AES-256-GCM KMS à NUB-T3 (ADR-009).
/// Patient inexistant ou hors tenant → 404. `note_kind` invalide → 422.
pub async fn add_patient_note(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
    Json(body): Json<AddClinicalNoteBody>,
) -> Result<(StatusCode, Json<AddClinicalNoteResponse>), AppError> {
    if body.note_kind != "observation" && body.note_kind != "act" {
        return Err(AppError::ValidationError);
    }
    if body.text.trim().is_empty() {
        return Err(AppError::ValidationError);
    }

    // Stub chiffrement : préfixe "STUB_ENC:" + XOR 0xFF octet à octet.
    // Garantit que le ciphertext ne contient pas le texte clair comme fenêtre contigüe.
    // Remplacé par AES-256-GCM + KMS Scaleway à NUB-T3 (ADR-009).
    let mut ciphertext: Vec<u8> = b"STUB_ENC:".to_vec();
    ciphertext.extend(body.text.as_bytes().iter().map(|b| b ^ 0xFF));

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le tenant).
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

    let act_ref = body.act_ref.unwrap_or_else(|| serde_json::json!({}));

    let row = sqlx::query(
        "INSERT INTO clinical_note \
         (cabinet_id, patient_id, author_id, content_ciphertext, content_key_ref, \
          note_kind, tooth, act_ref) \
         VALUES ($1, $2, $3, $4, 'stub-key-ref', $5, $6, $7) \
         RETURNING id, created_at",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(claims.sub)
    .bind(&ciphertext)
    .bind(&body.note_kind)
    .bind(body.tooth.as_deref())
    .bind(&act_ref)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let note_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        note_id = %note_id,
        note_kind = %body.note_kind,
        "clinical note added"
    );

    Ok((
        StatusCode::CREATED,
        Json(AddClinicalNoteResponse {
            note_id,
            created_at: created_at.to_rfc3339(),
        }),
    ))
}

// ── GET /v1/cabinet/patients/:id ─────────────────────────────────────────────

/// Partie administrative de la fiche patient (visible par tous les rôles pro).
#[derive(Serialize)]
pub struct PatientAdminSection {
    pub id: Uuid,
    pub first_name: String,
    pub last_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub birth_date: Option<String>,
    pub contact: Value,
    pub mutuelle: Value,
    pub created_at: String,
}

/// Réponse complète praticien (admin + données cliniques).
#[derive(Serialize)]
pub struct PatientDetailPractitioner {
    #[serde(flatten)]
    pub admin: PatientAdminSection,
    /// Antécédents / allergies / traitements — ciphertext décodé stub en dev.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub medical_record: Option<MedicalRecordSection>,
    /// Dernières notes cliniques (max 10, déchiffrées stub).
    pub notes: Vec<ClinicalNoteSummary>,
}

/// Réponse réduite secrétaire : sections cliniques absentes (R.4127-72).
#[derive(Serialize)]
pub struct PatientDetailSecretary {
    #[serde(flatten)]
    pub admin: PatientAdminSection,
}

#[derive(Serialize)]
pub struct MedicalRecordSection {
    pub id: Uuid,
    /// Contenu déchiffré stub (`"STUB_DEC:<base64>"` en dev — AES-256-GCM KMS à NUB-T3).
    pub data: String,
    pub updated_at: String,
}

#[derive(Serialize)]
pub struct ClinicalNoteSummary {
    pub id: Uuid,
    pub note_kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tooth: Option<String>,
    /// Contenu déchiffré stub en dev.
    pub text: String,
    pub created_at: String,
}

/// Réponse unifiée : `medical_record` et `notes` présents ↔ rôle praticien.
#[derive(Serialize)]
#[serde(untagged)]
pub enum PatientDetailResponse {
    Practitioner(PatientDetailPractitioner),
    Secretary(PatientDetailSecretary),
}

/// `GET /v1/cabinet/patients/:id` — fiche patient, vue selon rôle.
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT, jamais du path (invariant tenancy).
/// RLS via `app.current_cabinet_id`. Patient hors cabinet → 404.
///
/// - `secretary` : retourne uniquement la partie administrative (R.4127-72, §07 §4.1).
///   Pas de 403 : les champs cliniques sont *omis*, pas interdits.
/// - `practitioner` / `admin` : retourne la fiche complète + audite `read_record`.
pub async fn get_cabinet_patient(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<PatientDetailResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, first_name, last_name, birth_date, contact, mutuelle, created_at \
         FROM patient \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
    let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
    let birth_date: Option<chrono::NaiveDate> =
        row.try_get("birth_date").map_err(|_| AppError::Internal)?;
    let contact: Value = row.try_get("contact").map_err(|_| AppError::Internal)?;
    let mutuelle: Value = row.try_get("mutuelle").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    let admin = PatientAdminSection {
        id,
        first_name,
        last_name,
        birth_date: birth_date.map(|d| d.to_string()),
        contact,
        mutuelle,
        created_at: created_at.to_rfc3339(),
    };

    // Secrétaire : retourne uniquement la partie administrative (R.4127-72).
    if claims.role == "secretary" {
        tx.commit().await.map_err(|_| AppError::Internal)?;
        tracing::info!(
            cabinet_id = %claims.cabinet_id,
            user_id = %claims.sub,
            patient_id = %patient_id,
            role = "secretary",
            "patient detail fetched (secretary — clinical sections omitted)"
        );
        return Ok(Json(PatientDetailResponse::Secretary(
            PatientDetailSecretary { admin },
        )));
    }

    // Praticien / admin : charge les données cliniques.

    // medical_record (une seule ligne par patient, si elle existe).
    let mr_row = sqlx::query(
        "SELECT id, data_ciphertext, updated_at \
         FROM medical_record \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         ORDER BY updated_at DESC LIMIT 1",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let medical_record = if let Some(mr) = mr_row {
        let mr_id: Uuid = mr.try_get("id").map_err(|_| AppError::Internal)?;
        let ciphertext: Option<Vec<u8>> = mr
            .try_get("data_ciphertext")
            .map_err(|_| AppError::Internal)?;
        let updated_at: chrono::DateTime<chrono::Utc> =
            mr.try_get("updated_at").map_err(|_| AppError::Internal)?;
        // Stub déchiffrement : préfixe "STUB_DEC:" — AES-256-GCM KMS à NUB-T3 (ADR-009).
        let data = ciphertext
            .map(|b| format!("STUB_DEC:{}", base64_encode(&b)))
            .unwrap_or_default();
        Some(MedicalRecordSection {
            id: mr_id,
            data,
            updated_at: updated_at.to_rfc3339(),
        })
    } else {
        None
    };

    // Notes cliniques — 10 plus récentes, déchiffrées stub.
    let note_rows = sqlx::query(
        "SELECT id, note_kind, tooth, content_ciphertext, created_at \
         FROM clinical_note \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         ORDER BY created_at DESC LIMIT 10",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut notes: Vec<ClinicalNoteSummary> = Vec::with_capacity(note_rows.len());
    for nr in note_rows {
        let nid: Uuid = nr.try_get("id").map_err(|_| AppError::Internal)?;
        let note_kind: String = nr.try_get("note_kind").map_err(|_| AppError::Internal)?;
        let tooth: Option<String> = nr.try_get("tooth").map_err(|_| AppError::Internal)?;
        let ciphertext: Vec<u8> = nr
            .try_get("content_ciphertext")
            .map_err(|_| AppError::Internal)?;
        let note_created_at: chrono::DateTime<chrono::Utc> =
            nr.try_get("created_at").map_err(|_| AppError::Internal)?;
        // Stub déchiffrement.
        let text = format!("STUB_DEC:{}", base64_encode(&ciphertext));
        notes.push(ClinicalNoteSummary {
            id: nid,
            note_kind,
            tooth,
            text,
            created_at: note_created_at.to_rfc3339(),
        });
    }

    // Audit — praticien/admin accède au dossier clinique.
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'read_record', 'patient', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        role = %claims.role,
        "patient detail fetched (practitioner — full record)"
    );

    Ok(Json(PatientDetailResponse::Practitioner(
        PatientDetailPractitioner {
            admin,
            medical_record,
            notes,
        },
    )))
}

/// Encodage base64 minimal pour le stub de déchiffrement.
fn base64_encode(bytes: &[u8]) -> String {
    const TABLE: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0] as usize;
        let b1 = chunk.get(1).copied().unwrap_or(0) as usize;
        let b2 = chunk.get(2).copied().unwrap_or(0) as usize;
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(TABLE[(n >> 18) & 63] as char);
        out.push(TABLE[(n >> 12) & 63] as char);
        if chunk.len() > 1 {
            out.push(TABLE[(n >> 6) & 63] as char);
        } else {
            out.push('=');
        }
        if chunk.len() > 2 {
            out.push(TABLE[n & 63] as char);
        } else {
            out.push('=');
        }
    }
    out
}

// ── GET /v1/cabinet/patients/:id/documents ───────────────────────────────────

const VALID_CATEGORIES: &[&str] = &[
    "devis",
    "facture",
    "ordonnance",
    "radio",
    "cbct",
    "photo",
    "cr",
    "consigne",
    "attestation",
    "carte_mutuelle",
    "passeport_implantaire",
    "consentement",
];

#[derive(Deserialize)]
pub struct ListPatientDocumentsQuery {
    pub category: Option<String>,
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

#[derive(Serialize)]
pub struct PatientDocumentItem {
    pub id: Uuid,
    pub category: String,
    pub filename: String,
    pub mime_type: String,
    pub size_bytes: i64,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct ListPatientDocumentsResponse {
    pub data: Vec<PatientDocumentItem>,
    pub page: PageInfo,
}

fn doc_encode_cursor(created_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", created_at.timestamp_micros(), id)
}

fn doc_decode_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/cabinet/patients/:id/documents` — liste paginée des documents du dossier.
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT. RLS via `app.current_cabinet_id`.
/// Patient hors cabinet → 404. `?category=` filtre par catégorie (catégorie inconnue → liste vide).
pub async fn list_patient_documents(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(patient_id): Path<Uuid>,
    Query(params): Query<ListPatientDocumentsQuery>,
) -> Result<Json<ListPatientDocumentsResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);

    // Catégorie inconnue → liste vide immédiate, sans requête DB.
    if let Some(ref cat) = params.category {
        if !VALID_CATEGORIES.contains(&cat.as_str()) {
            return Ok(Json(ListPatientDocumentsResponse {
                data: vec![],
                page: PageInfo {
                    next_cursor: None,
                    limit,
                },
            }));
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le tenant).
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

    let cursor = params.cursor.as_deref().and_then(doc_decode_cursor);
    let fetch_limit = limit + 1;

    let (cursor_at, cursor_id) = cursor
        .map(|(at, id)| (Some(at), Some(id)))
        .unwrap_or((None, None));

    let rows = sqlx::query(
        "SELECT d.id, d.category, d.filename, d.mime_type, d.size_bytes, d.created_at \
         FROM document d \
         WHERE d.patient_id = $1 AND d.cabinet_id = $2 AND d.deleted_at IS NULL \
         AND ($3::text IS NULL OR d.category = $3) \
         AND ($4::timestamptz IS NULL \
              OR d.created_at < $4 \
              OR (d.created_at = $4 AND d.id < $5)) \
         ORDER BY d.created_at DESC, d.id DESC \
         LIMIT $6",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .bind(params.category.as_deref())
    .bind(cursor_at)
    .bind(cursor_id)
    .bind(fetch_limit)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<PatientDocumentItem> = Vec::with_capacity(visible.len());
    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let did: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let category: String = row.try_get("category").map_err(|_| AppError::Internal)?;
        let filename: String = row.try_get("filename").map_err(|_| AppError::Internal)?;
        let mime_type: String = row.try_get("mime_type").map_err(|_| AppError::Internal)?;
        let size_bytes: i64 = row.try_get("size_bytes").map_err(|_| AppError::Internal)?;
        let doc_created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        last_created_at = Some(doc_created_at);
        last_id = Some(did);

        data.push(PatientDocumentItem {
            id: did,
            category,
            filename,
            mime_type,
            size_bytes,
            created_at: doc_created_at.to_rfc3339(),
        });
    }

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| doc_encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        count = data.len(),
        "patient documents listed"
    );

    Ok(Json(ListPatientDocumentsResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}

// ── POST /v1/cabinet/patients/:id/documents ───────────────────────────────────

const MAX_CABINET_DOC_SIZE: usize = 20 * 1024 * 1024;
const ALLOWED_CABINET_DOC_MIMES: &[&str] = &["application/pdf", "image/jpeg", "image/png"];

/// Réponse de `POST /v1/cabinet/patients/:id/documents`.
#[derive(Serialize)]
pub struct UploadPatientDocumentResponse {
    pub document_id: Uuid,
}

/// `POST /v1/cabinet/patients/:id/documents` — upload d'un document dans le dossier cabinet.
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT. Patient hors cabinet → 404.
///
/// Champs multipart :
/// - `file` : binaire requis (PDF / JPEG / PNG ≤ 20 Mo). MIME déclaré vérifié → 422 sinon.
/// - `category` : enum strict requis → 422 si absent ou invalide.
/// - `filename` : optionnel.
///
/// Antivirus : stub, `scan_status = 'pending'`.
/// Chiffrement colonne : stub `storage_key = UUID` — AES-256-GCM KMS à NUB-T3 (ADR-009).
/// Retour : `201 { document_id }`.
pub async fn upload_patient_document(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Extension(storage): Extension<Arc<dyn StorageClient>>,
    Path(patient_id): Path<Uuid>,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<UploadPatientDocumentResponse>), AppError> {
    let mut category_raw: Option<String> = None;
    let mut filename_field: Option<String> = None;
    let mut file_mime: Option<String> = None;
    let mut file_bytes: Option<Vec<u8>> = None;
    let mut file_filename: Option<String> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|_| AppError::ValidationError)?
    {
        let name = field.name().unwrap_or("").to_string();
        match name.as_str() {
            "category" => {
                category_raw = Some(field.text().await.map_err(|_| AppError::ValidationError)?);
            }
            "filename" => {
                filename_field = Some(field.text().await.map_err(|_| AppError::ValidationError)?);
            }
            "file" => {
                file_mime = field
                    .content_type()
                    .map(|s| s.split(';').next().unwrap_or("").trim().to_string());
                file_filename = field.file_name().map(|s| s.to_string());
                let bytes = field.bytes().await.map_err(|_| AppError::ValidationError)?;
                if bytes.len() > MAX_CABINET_DOC_SIZE {
                    return Err(AppError::ValidationError);
                }
                file_bytes = Some(bytes.to_vec());
            }
            _ => {}
        }
    }

    let category = category_raw.ok_or(AppError::ValidationError)?;
    if !VALID_CATEGORIES.contains(&category.as_str()) {
        return Err(AppError::ValidationError);
    }

    let file_bytes = file_bytes.ok_or(AppError::ValidationError)?;
    let file_mime = file_mime.ok_or(AppError::ValidationError)?;
    if !ALLOWED_CABINET_DOC_MIMES.contains(&file_mime.as_str()) {
        return Err(AppError::ValidationError);
    }

    let size_bytes = file_bytes.len() as i64;
    let fname = filename_field
        .or(file_filename)
        .unwrap_or_else(|| "document.bin".to_string());

    // Stub : clé Object Storage (chiffrement AES-256-GCM KMS à NUB-T3 — ADR-009).
    let storage_key = Uuid::new_v4().to_string();
    let _ = storage; // storage client disponible pour la prod (upload objet)

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le tenant).
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

    let row = sqlx::query(
        "INSERT INTO document \
         (cabinet_id, patient_id, category, storage_key, filename, mime_type, \
          size_bytes, sha256, scan_status, uploaded_by) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, \
                 encode(digest($8, 'sha256'), 'hex'), 'pending', $9) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(&category)
    .bind(&storage_key)
    .bind(&fname)
    .bind(&file_mime)
    .bind(size_bytes)
    .bind(&file_bytes)
    .bind(claims.sub)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let document_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    // Audit — action upload_document.
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'upload_document', 'document', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(document_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        document_id = %document_id,
        category = %category,
        size_bytes,
        "patient document uploaded"
    );

    Ok((
        StatusCode::CREATED,
        Json(UploadPatientDocumentResponse { document_id }),
    ))
}
