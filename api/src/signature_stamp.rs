//! Résolution partagée de la signature / du tampon du praticien pour
//! apposition sur un PDF généré (#7148) : lit le document (`document.id =
//! provider.signature_image_id`/`stamp_image_id`, migration 0299),
//! télécharge ses octets depuis l'`ObjectStorage` et les décode en
//! [`crate::pdf_text::JpegImage`]. Utilisé par `letters.rs` (courriers) et
//! `billing.rs` (devis).
//!
//! Best-effort : id absent, document introuvable/supprimé, hors cabinet,
//! MIME différent de `image/jpeg`, ou JPEG non reconnu → `None`, sans jamais
//! faire échouer la génération du PDF (la signature/le tampon restent une
//! amélioration visuelle, pas une condition bloquante).

use sqlx::Row;
use uuid::Uuid;

use crate::{pdf_text::JpegImage, ObjectStorage};

/// Résout signature et tampon en une seule paire d'appels — `None` pour
/// l'un ou l'autre si l'id correspondant est absent (praticien n'ayant pas
/// téléversé l'image) ou si la résolution échoue silencieusement.
pub(crate) async fn load_practitioner_stamps(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    object_storage: &dyn ObjectStorage,
    cabinet_id: Uuid,
    signature_image_id: Option<Uuid>,
    stamp_image_id: Option<Uuid>,
) -> (Option<JpegImage>, Option<JpegImage>) {
    let signature = match signature_image_id {
        Some(id) => load_one(tx, object_storage, cabinet_id, id).await,
        None => None,
    };
    let stamp = match stamp_image_id {
        Some(id) => load_one(tx, object_storage, cabinet_id, id).await,
        None => None,
    };
    (signature, stamp)
}

async fn load_one(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    object_storage: &dyn ObjectStorage,
    cabinet_id: Uuid,
    document_id: Uuid,
) -> Option<JpegImage> {
    let row = sqlx::query(
        "SELECT storage_key, mime_type FROM document \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(document_id)
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .ok()??;

    let mime_type: String = row.try_get("mime_type").ok()?;
    if mime_type != "image/jpeg" {
        return None;
    }
    let storage_key: String = row.try_get("storage_key").ok()?;
    let (_, bytes) = object_storage.download(&storage_key).await?;
    JpegImage::parse(bytes)
}
