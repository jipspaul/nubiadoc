//! Handlers `GET /v1/cabinet/patients`, `POST /v1/cabinet/patients`,
//! et `POST /v1/cabinet/patients/:id/notes`.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims, ProSecretaryPlusClaims},
    AppState,
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
