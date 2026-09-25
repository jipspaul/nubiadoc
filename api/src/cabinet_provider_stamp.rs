//! `POST /v1/cabinet/provider/signature` et `POST /v1/cabinet/provider/stamp`
//! (#7148, DP-F25.b) — upload de la signature manuscrite et du tampon du
//! praticien, référencés depuis `provider.signature_image_id`/
//! `stamp_image_id` (migration 0299, #7149) pour être apposés sur les PDF
//! générés (`letters.rs`, `billing.rs::render_quote_pdf`).
//!
//! JPEG uniquement (`image/jpeg`) : l'apposition sur un PDF sans dépendance
//! externe (`pdf_text::JpegImage`) réinjecte les octets JPEG tels quels dans
//! un flux `/Filter /DCTDecode` — un PNG demanderait de rejouer son
//! filtrage par ligne (Paeth/Up/Sub/Average), hors de portée ici.

use std::sync::Arc;

use axum::{
    extract::{Extension, Multipart, State},
    http::StatusCode,
    Json,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    pdf_text::JpegImage,
    upload_storage, AppState, ObjectStorage,
};

const MAX_STAMP_SIZE: usize = 5 * 1024 * 1024;

/// Réponse commune aux deux endpoints.
#[derive(Serialize)]
pub struct UploadStampResponse {
    pub document_id: Uuid,
    pub size_bytes: i64,
}

/// `POST /v1/cabinet/provider/signature` — téléverse la signature du
/// praticien connecté.
pub async fn upload_provider_signature(
    state: State<AppState>,
    claims: ProPractitionerClaims,
    object_storage: Extension<Arc<dyn ObjectStorage>>,
    multipart: Multipart,
) -> Result<(StatusCode, Json<UploadStampResponse>), AppError> {
    upload_stamp(
        state,
        claims,
        object_storage,
        multipart,
        StampKind::Signature,
    )
    .await
}

/// `POST /v1/cabinet/provider/stamp` — téléverse le tampon du praticien
/// connecté.
pub async fn upload_provider_stamp(
    state: State<AppState>,
    claims: ProPractitionerClaims,
    object_storage: Extension<Arc<dyn ObjectStorage>>,
    multipart: Multipart,
) -> Result<(StatusCode, Json<UploadStampResponse>), AppError> {
    upload_stamp(state, claims, object_storage, multipart, StampKind::Stamp).await
}

#[derive(Clone, Copy)]
enum StampKind {
    Signature,
    Stamp,
}

impl StampKind {
    fn document_category(self) -> &'static str {
        match self {
            StampKind::Signature => "signature",
            StampKind::Stamp => "tampon",
        }
    }

    fn provider_column(self) -> &'static str {
        match self {
            StampKind::Signature => "signature_image_id",
            StampKind::Stamp => "stamp_image_id",
        }
    }
}

/// Champ multipart requis : `file` (JPEG, ≤ [`MAX_STAMP_SIZE`], non vide).
/// MIME déclaré vérifié contre l'allowlist ET contre le nombre magique du
/// contenu (#7302, même garde que les autres endpoints d'upload) → `422`
/// sinon. Le JPEG doit en plus être décodable par [`JpegImage::parse`]
/// (marqueur SOF exploitable) → `422` sinon, faute de quoi l'apposition sur
/// PDF serait silencieusement impossible plus tard.
///
/// Écrit dans l'`ObjectStorage` (`upload_storage::PREFIX_CABINET_DOCUMENT`),
/// insère la ligne `document` (`category = 'signature'`/`'tampon'`) et met à
/// jour `provider.signature_image_id`/`stamp_image_id` pour le praticien
/// connecté (`cabinet_id` + `user_id` du JWT). Provider absent pour ce
/// couple (cabinet, user) → `404`. Retourne `201 { document_id, size_bytes }`.
async fn upload_stamp(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Extension(object_storage): Extension<Arc<dyn ObjectStorage>>,
    mut multipart: Multipart,
    kind: StampKind,
) -> Result<(StatusCode, Json<UploadStampResponse>), AppError> {
    let mut file_mime: Option<String> = None;
    let mut file_bytes: Option<Vec<u8>> = None;
    let mut file_filename: Option<String> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|_| AppError::ValidationError)?
    {
        if field.name().unwrap_or("") == "file" {
            file_mime = field
                .content_type()
                .map(|s| s.split(';').next().unwrap_or("").trim().to_string());
            file_filename = field.file_name().map(|s| s.to_string());
            let bytes = field.bytes().await.map_err(|_| AppError::ValidationError)?;
            if bytes.len() > MAX_STAMP_SIZE {
                return Err(AppError::ValidationError);
            }
            file_bytes = Some(bytes.to_vec());
        }
    }

    let file_bytes = file_bytes.ok_or(AppError::ValidationError)?;
    if file_bytes.is_empty() {
        return Err(AppError::ValidationError);
    }
    crate::file_scan::reject_eicar(&file_bytes)?;
    let file_mime = file_mime.ok_or(AppError::ValidationError)?;
    if file_mime != "image/jpeg" {
        return Err(AppError::ValidationError);
    }
    crate::file_scan::verify_content_matches_declared_mime(&file_bytes, &file_mime)?;
    // Doit être décodable pour l'apposition sur PDF (dimensions/colorspace
    // lues depuis le marqueur SOF) — un fichier accepté ici mais illisible
    // plus tard resterait silencieusement absent des PDF générés.
    if JpegImage::parse(file_bytes.clone()).is_none() {
        return Err(AppError::ValidationError);
    }

    let size_bytes = file_bytes.len() as i64;
    let filename = file_filename.unwrap_or_else(|| format!("{}.jpg", kind.document_category()));

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Le praticien doit avoir un profil `provider` dans ce cabinet (même
    // garde que `patch_cabinet_provider`) avant d'écrire quoi que ce soit.
    let provider_exists =
        sqlx::query("SELECT 1 FROM provider WHERE cabinet_id = $1 AND user_id = $2")
            .bind(claims.cabinet_id)
            .bind(claims.sub)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if provider_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let storage_key = upload_storage::store_upload(
        object_storage.as_ref(),
        upload_storage::PREFIX_PROVIDER_STAMP,
        &file_mime,
        file_bytes.clone(),
    )
    .await?;

    let doc_row = sqlx::query(
        "INSERT INTO document \
         (cabinet_id, category, storage_key, filename, mime_type, size_bytes, \
          sha256, scan_status, uploaded_by) \
         VALUES ($1, $2, $3, $4, $5, $6, encode(digest($7, 'sha256'), 'hex'), 'clean', $8) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(kind.document_category())
    .bind(&storage_key)
    .bind(&filename)
    .bind(&file_mime)
    .bind(size_bytes)
    .bind(&file_bytes)
    .bind(claims.sub)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let document_id: Uuid = doc_row.try_get("id").map_err(|_| AppError::Internal)?;

    let update_sql = format!(
        "UPDATE provider SET {} = $1 WHERE cabinet_id = $2 AND user_id = $3",
        kind.provider_column()
    );
    sqlx::query(&update_sql)
        .bind(document_id)
        .bind(claims.cabinet_id)
        .bind(claims.sub)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

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
        document_id = %document_id,
        category = kind.document_category(),
        "provider stamp uploaded"
    );

    Ok((
        StatusCode::CREATED,
        Json(UploadStampResponse {
            document_id,
            size_bytes,
        }),
    ))
}
