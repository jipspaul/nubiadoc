//! Handler `POST /v1/cabinet/prescriptions/{id}/sign` — signature eIDAS d'une ordonnance.

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, State},
    Json,
};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState, SignatureClient,
};

/// Réponse de `POST /v1/cabinet/prescriptions/{id}/sign`.
#[derive(serde::Serialize)]
pub struct SignPrescriptionResponse {
    pub signed_at: String,
    pub document_id: Uuid,
}

/// `POST /v1/cabinet/prescriptions/{id}/sign` — signature eIDAS d'une ordonnance.
///
/// Token pro `practitioner` ou `admin` requis — `secretary` → 403.
/// `cabinet_id` extrait du JWT (jamais du body/path — invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
///
/// Comportement :
/// - Prescription inexistante ou hors tenant → 404.
/// - Prescription en statut autre que `draft` → 409 (invalid_status).
/// - Transitions : `draft` → `signed`, `signed_at` positionné.
/// - Crée une entrée `signature` (Yousign stub — NUB-T3 : appel réel) et
///   un `document(category='ordonnance')` dans le coffre-fort du patient.
/// - Retourne `200 { signed_at, document_id }`.
pub async fn sign_prescription(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Extension(sig_client): Extension<Arc<dyn SignatureClient>>,
    Path(prescription_id): Path<Uuid>,
) -> Result<Json<SignPrescriptionResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope cabinet — RLS tenant_isolation (prescription, signature, document, audit_log).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Lecture de la prescription — 404 si hors tenant (RLS fail-closed).
    let row = sqlx::query(
        "SELECT id, patient_id, practitioner_id, status \
         FROM prescription \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(prescription_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    // Seule une ordonnance en statut `draft` peut être signée.
    if status != "draft" {
        return Err(AppError::InvalidStatus);
    }

    // Délégation de signature eIDAS au client Yousign (stub en dev, réel post-NUB-T3).
    let provider_ref = sig_client.create_signature(prescription_id);

    // Crée l'entrée signature (brique wedge — réutilisée depuis quote).
    let sig_row = sqlx::query(
        "INSERT INTO signature (cabinet_id, provider, provider_ref, level) \
         VALUES ($1, 'yousign', $2, 'aes') \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(&provider_ref)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let signature_id: Uuid = sig_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Génère le PDF d'ordonnance (stub : clé Object Storage, sha256 nul).
    // NUB-T3 : remplacer par génération PDF réelle + upload chiffré Object Storage.
    let storage_key = Uuid::new_v4().to_string();
    let filename = format!("ordonnance-{}.pdf", prescription_id);

    let doc_row = sqlx::query(
        "INSERT INTO document \
         (cabinet_id, patient_id, category, storage_key, filename, mime_type, \
          sha256, scan_status, uploaded_by, size_bytes) \
         VALUES ($1, $2, 'ordonnance', $3, $4, 'application/pdf', \
                 $5, 'clean', $6, 0) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(&storage_key)
    .bind(&filename)
    .bind(format!("{:0>64}", "0")) // sha256 stub
    .bind(claims.sub)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let document_id: Uuid = doc_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Transition de statut : draft → signed.
    let update_row = sqlx::query(
        "UPDATE prescription \
         SET status = 'signed', signature_id = $1, document_id = $2, signed_at = now() \
         WHERE id = $3 AND cabinet_id = $4 \
         RETURNING signed_at",
    )
    .bind(signature_id)
    .bind(document_id)
    .bind(prescription_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let signed_at: chrono::DateTime<chrono::Utc> = update_row
        .try_get("signed_at")
        .map_err(|_| AppError::Internal)?;

    // Audit — action sign_prescription, zéro PII.
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'sign_prescription', 'prescription', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind("practitioner")
    .bind(prescription_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        prescription_id = %prescription_id,
        document_id = %document_id,
        "prescription signed"
    );

    Ok(Json(SignPrescriptionResponse {
        signed_at: signed_at.to_rfc3339(),
        document_id,
    }))
}
