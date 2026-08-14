//! Handlers pour le coffre-fort patient :
//! GET /v1/documents, GET /v1/documents/:id, GET /v1/documents/:id/download, POST /v1/documents.

use std::sync::Arc;

use axum::{
    extract::{Extension, Multipart, Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState, StorageSigner,
};

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
pub struct ListDocumentsQuery {
    pub category: Option<String>,
    pub patient_account: Option<Uuid>,
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

/// `?patient_account=` partagé par `get_document`/`download_document`
/// (même résolution tuteur→proche que `list_documents`, issue #3778).
#[derive(Deserialize)]
pub struct PatientAccountQuery {
    pub patient_account: Option<Uuid>,
}

/// Résout le compte patient effectif pour une requête `?patient_account=`
/// (tuteur → proche à charge) : soi-même si absent/égal, sinon vérifie
/// `account_guardianship` (relation active) → `Forbidden` sinon.
/// Partagé par `list_documents`, `get_document`, `download_document`
/// (issue #3778 : les deux derniers ne le faisaient pas, cassant l'accès
/// tuteur→document d'un proche que `list_documents` autorise pourtant).
async fn resolve_effective_account(
    tx: &mut sqlx::PgConnection,
    account_id: Uuid,
    requested: Option<Uuid>,
) -> Result<Uuid, AppError> {
    let Some(dependent_id) = requested else {
        return Ok(account_id);
    };
    if dependent_id == account_id {
        return Ok(account_id);
    }
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let guardianship = sqlx::query(
        "SELECT id FROM account_guardianship \
         WHERE guardian_account_id = $1 AND dependent_account_id = $2 AND active = true",
    )
    .bind(account_id)
    .bind(dependent_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if guardianship.is_none() {
        return Err(AppError::Forbidden);
    }
    Ok(dependent_id)
}

#[derive(Serialize)]
pub struct DocumentItem {
    pub id: Uuid,
    pub category: String,
    pub filename: String,
    pub mime_type: String,
    pub size_bytes: i64,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

#[derive(Serialize)]
pub struct ListDocumentsResponse {
    pub data: Vec<DocumentItem>,
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

/// `GET /v1/documents` — coffre-fort patient : liste paginée des documents.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` (migration 0034).
/// Catégorie inconnue → `200` liste vide (pas d'erreur).
/// `?patient_account` : tuteur accède aux docs d'un proche (vérifié contre
/// `account_guardianship` — refus `403` si tutelle inexistante ou inactive).
/// Chaque document retourné est audité (`read_document`, zéro PII).
pub async fn list_documents(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Query(params): Query<ListDocumentsQuery>,
) -> Result<Json<ListDocumentsResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);

    // Catégorie inconnue → liste vide immédiate, sans requête DB.
    if let Some(ref cat) = params.category {
        if !VALID_CATEGORIES.contains(&cat.as_str()) {
            return Ok(Json(ListDocumentsResponse {
                data: vec![],
                page: PageInfo {
                    next_cursor: None,
                    limit,
                },
            }));
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Résout le compte effectif (tuteur → proche, ou soi-même).
    let effective_account_id =
        resolve_effective_account(&mut tx, claims.account_id, params.patient_account).await?;

    // Scope patient — RLS document_patient_read (migration 0034).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(effective_account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Requis pour la branche tutelle de document_patient_read (migration
    // 0218, account_guardianship RLS) — cf. appointment_patient_read (0196).
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cursor = match params.cursor.as_deref() {
        Some(s) => Some(decode_cursor(s).ok_or(AppError::ValidationError)?),
        None => None,
    };
    let fetch_limit = limit + 1;

    let category_clause = if params.category.is_some() {
        " AND d.category = $2"
    } else {
        ""
    };

    let cursor_clause = match (params.category.is_some(), cursor.is_some()) {
        (true, true) => " AND (d.created_at < $3 OR (d.created_at = $3 AND d.id < $4))",
        (false, true) => " AND (d.created_at < $2 OR (d.created_at = $2 AND d.id < $3))",
        _ => "",
    };

    let sql = format!(
        "SELECT d.id, d.category, d.filename, d.mime_type, d.size_bytes, d.created_at, d.cabinet_id \
         FROM document d \
         WHERE d.deleted_at IS NULL\
         {category_clause}{cursor_clause} \
         ORDER BY d.created_at DESC, d.id DESC \
         LIMIT $1"
    );

    let rows = match (params.category.as_deref(), cursor) {
        (Some(cat), Some((cursor_at, cursor_id))) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cat)
            .bind(cursor_at)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        (Some(cat), None) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cat)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        (None, Some((cursor_at, cursor_id))) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cursor_at)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        (None, None) => sqlx::query(&sql)
            .bind(fetch_limit)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
    };

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<DocumentItem> = Vec::with_capacity(visible.len());
    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;
    // (cabinet_id, doc_id) pour l'audit — nil UUID pour les docs plateforme (cabinet_id IS NULL)
    let mut audit_entries: Vec<(Uuid, Uuid)> = Vec::with_capacity(visible.len());

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let category: String = row.try_get("category").map_err(|_| AppError::Internal)?;
        let filename: String = row.try_get("filename").map_err(|_| AppError::Internal)?;
        let mime_type: String = row.try_get("mime_type").map_err(|_| AppError::Internal)?;
        let size_bytes: i64 = row.try_get("size_bytes").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        let cabinet_id: Option<Uuid> = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;

        last_created_at = Some(created_at);
        last_id = Some(id);
        audit_entries.push((cabinet_id.unwrap_or(Uuid::nil()), id));

        data.push(DocumentItem {
            id,
            category,
            filename,
            mime_type,
            size_bytes,
            created_at: created_at.to_rfc3339(),
        });
    }

    // Audit — un log par document lu (action read_document, zéro PII).
    // Le GUC app.current_cabinet_id est repositionné pour chaque cabinet via SET LOCAL.
    for (cabinet_id, doc_id) in &audit_entries {
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        sqlx::query(
            "INSERT INTO audit_log \
             (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
             VALUES ($1, $2, 'patient', 'read_document', 'document', $3)",
        )
        .bind(cabinet_id)
        .bind(claims.sub)
        .bind(doc_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        account_id = %claims.account_id,
        effective_account_id = %effective_account_id,
        count = data.len(),
        "documents listed"
    );

    Ok(Json(ListDocumentsResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}
#[derive(Serialize)]
pub struct DocumentDetail {
    pub id: Uuid,
    pub category: String,
    pub filename: String,
    pub mime_type: String,
    pub size_bytes: i64,
    pub sha256: String,
    pub created_at: String,
    pub signed_url: String,
    pub signed_url_expires_at: String,
}

/// `GET /v1/documents/:id` — métadonnées complètes + URL signée expirante.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` (migration 0034) :
/// document hors tenant → `404` (jamais `403`, anti-énumération).
/// URL signée valable 15 min maximum. Accès audité (`read_document`).
pub async fn get_document(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Extension(signer): Extension<Arc<dyn StorageSigner>>,
    Path(doc_id): Path<Uuid>,
    Query(params): Query<PatientAccountQuery>,
) -> Result<Json<DocumentDetail>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Résout le compte effectif (tuteur → proche, ou soi-même) — même règle
    // que list_documents, absente ici avant #3778.
    let effective_account_id =
        resolve_effective_account(&mut tx, claims.account_id, params.patient_account).await?;

    // Scope patient — RLS document_patient_read (migration 0034) → 0 ligne si hors tenant.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(effective_account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Requis pour la branche tutelle de document_patient_read (migration
    // 0218, account_guardianship RLS) — cf. appointment_patient_read (0196).
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT d.id, d.category, d.filename, d.mime_type, d.size_bytes, d.sha256, \
         d.created_at, d.storage_key, d.cabinet_id \
         FROM document d \
         WHERE d.id = $1 AND d.deleted_at IS NULL",
    )
    .bind(doc_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let category: String = row.try_get("category").map_err(|_| AppError::Internal)?;
    let filename: String = row.try_get("filename").map_err(|_| AppError::Internal)?;
    let mime_type: String = row.try_get("mime_type").map_err(|_| AppError::Internal)?;
    let size_bytes: i64 = row.try_get("size_bytes").map_err(|_| AppError::Internal)?;
    let sha256: String = row.try_get("sha256").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    let storage_key: String = row.try_get("storage_key").map_err(|_| AppError::Internal)?;
    let cabinet_id: Option<Uuid> = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;

    // URL signée valable 15 minutes — signer réel (Scaleway en prod, #4717),
    // jamais le StorageClient/StubStorageClient hardcodé sur storage.stub (#4835).
    // `signer.sign() == None` : le lien n'a jamais été généré (signer non
    // configuré, ex. `SCW_*` absentes), pas "expiré" — 502 upstream_unavailable,
    // pas 410 link_expired (régression #4835 constatée en prod après #5395).
    let signed_url = signer
        .sign(&storage_key)
        .ok_or(AppError::UpstreamUnavailable)?;
    let signed_url_expires_at = chrono::Utc::now() + chrono::Duration::seconds(900);

    // Audit — uniquement si le document appartient à un cabinet.
    if let Some(cab_id) = cabinet_id {
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cab_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        sqlx::query(
            "INSERT INTO audit_log \
             (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
             VALUES ($1, $2, 'patient', 'read_document', 'document', $3)",
        )
        .bind(cab_id)
        .bind(claims.sub)
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        document_id = %id,
        "document fetched"
    );

    Ok(Json(DocumentDetail {
        id,
        category,
        filename,
        mime_type,
        size_bytes,
        sha256,
        created_at: created_at.to_rfc3339(),
        signed_url,
        signed_url_expires_at: signed_url_expires_at.to_rfc3339(),
    }))
}

const PRESIGN_TTL_SECS: i64 = 300;

/// Réponse de `GET /v1/documents/:id/download`.
#[derive(Serialize)]
pub struct DownloadUrlResponse {
    pub download_url: String,
    pub expires_at: String,
}

/// `GET /v1/documents/{id}/download` — URL signée expirante (TTL = 300 s).
///
/// Génère une URL fraîche à chaque appel. Pas de 302 : le front lit le JSON.
/// Doc inexistant → `404`. Signer indisponible (lien jamais généré) → `502 upstream_unavailable`.
/// Audit : action `read_document` (zéro PII).
pub async fn download_document(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Extension(signer): Extension<Arc<dyn StorageSigner>>,
    Path(id): Path<Uuid>,
    Query(params): Query<PatientAccountQuery>,
) -> Result<Json<DownloadUrlResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Résout le compte effectif (tuteur → proche, ou soi-même) — même règle
    // que list_documents, absente ici avant #3778.
    let effective_account_id =
        resolve_effective_account(&mut tx, claims.account_id, params.patient_account).await?;

    // Scope patient — RLS document_patient_read (migration 0034).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(effective_account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Requis pour la branche tutelle de document_patient_read (migration
    // 0218, account_guardianship RLS) — cf. appointment_patient_read (0196).
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT d.storage_key, d.cabinet_id \
         FROM document d \
         WHERE d.id = $1 AND d.deleted_at IS NULL",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let storage_key: String = row.try_get("storage_key").map_err(|_| AppError::Internal)?;
    let cabinet_id: Option<Uuid> = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let audit_cab_id = cabinet_id.unwrap_or(Uuid::nil());

    // Génère une URL signée fraîche — 502 upstream_unavailable si le signer
    // n'a jamais pu produire de lien (config manquante), pas 410 link_expired
    // qui signifierait un lien généré puis lapsé (régression #4835).
    let signed_url = signer
        .sign(&storage_key)
        .ok_or(AppError::UpstreamUnavailable)?;

    // Audit — action read_document, zéro PII.
    // Pour les docs plateforme (cabinet_id IS NULL) on utilise le nil UUID comme convention.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(audit_cab_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'read_document', 'document', $3)",
    )
    .bind(audit_cab_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let expires_at = chrono::Utc::now() + chrono::Duration::seconds(PRESIGN_TTL_SECS);

    tracing::info!(
        account_id = %claims.account_id,
        doc_id = %id,
        "document download url generated"
    );

    Ok(Json(DownloadUrlResponse {
        download_url: signed_url,
        expires_at: expires_at.to_rfc3339(),
    }))
}

pub(crate) const MAX_UPLOAD_SIZE: usize = 20 * 1024 * 1024;
const ALLOWED_UPLOAD_MIMES: &[&str] = &["application/pdf", "image/jpeg", "image/png"];

/// Réponse de `POST /v1/documents`.
#[derive(Serialize)]
pub struct UploadDocumentResponse {
    pub document_id: Uuid,
    pub category: String,
    pub filename: String,
    pub size_bytes: i64,
    pub sha256: String,
}

/// `POST /v1/documents` — coffre-fort patient : upload d'une pièce jointe / justificatif.
///
/// Champs multipart :
/// - `file` : binaire requis (PDF / JPEG / PNG ≤ 20 Mo). MIME déclaré vérifié → `422` sinon.
/// - `category` : enum strict requis → `422` si absent ou invalide.
/// - `filename` : optionnel ; remplace le nom issu du champ `file` si fourni.
///
/// Chiffrement au repos : stub UTF-8 en dev — AES-256-GCM KMS à NUB-T3 (ADR-009).
/// Antivirus : stub, `scan_status = 'pending'`.
/// Audit : action `upload_document` journalisée (`cabinet_id` = nil UUID, zéro PII).
/// Retour : `201 { document_id, category, filename, size_bytes, sha256 }`.
pub async fn upload_document(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<UploadDocumentResponse>), AppError> {
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
                if bytes.len() > MAX_UPLOAD_SIZE {
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
    if file_bytes.is_empty() {
        return Err(AppError::ValidationError);
    }
    let file_mime = file_mime.ok_or(AppError::ValidationError)?;
    if !ALLOWED_UPLOAD_MIMES.contains(&file_mime.as_str()) {
        return Err(AppError::ValidationError);
    }

    let size_bytes = file_bytes.len() as i64;
    let fname = filename_field
        .or(file_filename)
        .unwrap_or_else(|| "document.bin".to_string());

    // Stub : clé Object Storage (chiffrement AES-256-GCM KMS à NUB-T3 — ADR-009).
    let storage_key = Uuid::new_v4().to_string();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // RLS document_patient_owner (migration 0026) : scoped par patient_account_id.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO document \
         (patient_account_id, category, storage_key, filename, mime_type, \
          size_bytes, sha256, scan_status, uploaded_by) \
         VALUES ($1, $2, $3, $4, $5, $6, \
                 encode(digest($7, 'sha256'), 'hex'), 'pending', $8) \
         RETURNING id, sha256",
    )
    .bind(claims.account_id)
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
    let sha256: String = row.try_get("sha256").map_err(|_| AppError::Internal)?;

    // Audit — zéro PII ; cabinet_id = nil UUID (entité plateforme, pas de cabinet).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'patient', 'upload_document', 'document', $3)",
    )
    .bind(Uuid::nil())
    .bind(claims.sub)
    .bind(document_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        document_id = %document_id,
        category = %category,
        size_bytes,
        "document uploaded"
    );

    Ok((
        StatusCode::CREATED,
        Json(UploadDocumentResponse {
            document_id,
            category,
            filename: fname,
            size_bytes,
            sha256,
        }),
    ))
}
