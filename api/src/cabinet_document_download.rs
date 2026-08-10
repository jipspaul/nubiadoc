//! `GET /v1/cabinet/patients/:id/documents/:doc_id/download` — URL signée
//! pour le contenu d'un document patient, côté cabinet (#4286).
//!
//! Quoi : jusqu'ici seule la métadonnée (`clinical::list_patient_documents`)
//! était accessible côté praticien/secrétariat — aucune route ne servait le
//! CONTENU (téléchargement/prévisualisation), seule `documents::download_document`
//! existait et est typée en dur sur `PatientAccountClaims` (patient uniquement).
//! Quand : bloquant pour la prévisualisation image de l'onglet Documents/Radios
//! côté praticien (#4133, livré en scope réduit — liste + upload seulement — en
//! l'absence de cette route).
//! Pourquoi cette approche : nouveau fichier plutôt qu'ajout dans `clinical.rs`
//! (déjà loin au-dessus du plafond CLAUDE.md) — même stratégie que
//! `quote_signature.rs`, extrait de `billing.rs` pour la même raison.
//! Modes d'échec : patient hors cabinet / document introuvable → `404` ;
//! praticien sans relation de soin (§14, catégorie clinique) → `403` ;
//! secrétaire hors scope secrétariat (R10) → `404` (pas de fuite d'existence,
//! même contrat que `list_patient_documents`) ; signer inaccessible → `410
//! link_expired`.

use axum::extract::{Extension, Path, State};
use axum::Json;
use serde::Serialize;
use sqlx::Row;
use std::sync::Arc;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    clinical::NON_CLINICAL_CATEGORIES,
    AppState, StorageSigner,
};

const PRESIGN_TTL_SECS: i64 = 300;

/// Réponse de `GET /v1/cabinet/patients/:id/documents/:doc_id/download`.
#[derive(Serialize)]
pub struct CabinetDocumentDownloadResponse {
    pub download_url: String,
    pub expires_at: String,
}

/// `GET /v1/cabinet/patients/:id/documents/:doc_id/download` — URL signée
/// expirante (TTL = 300 s), sur le modèle de `documents::download_document`
/// mais pour un accès cabinet (praticien/secrétariat/admin).
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT. Patient hors cabinet, ou document hors du
/// dossier de ce patient → `404`.
///
/// §14 — même garde que `list_patient_documents` : un praticien sans
/// `appointment` avec ce patient → `403`. Un rôle non-praticien ne peut
/// télécharger qu'un document `NON_CLINICAL_CATEGORIES` (devis, facture,
/// attestation, carte_mutuelle) ; une catégorie clinique demandée par un
/// non-praticien → `403` (pas de relation de soin possible).
///
/// R10 — même garde de scope secrétariat que `list_patient_documents` :
/// une secrétaire hors du secrétariat du patient → `404` (pas de fuite
/// d'existence via un 403).
pub async fn download_cabinet_patient_document(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Extension(signer): Extension<Arc<dyn StorageSigner>>,
    Path((patient_id, doc_id)): Path<(Uuid, Uuid)>,
) -> Result<Json<CabinetDocumentDownloadResponse>, AppError> {
    let is_practitioner = claims.role == "practitioner";

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

    // §14 : même garde qu'en lecture liste (list_patient_documents) — un
    // praticien doit avoir eu au moins un appointment avec ce patient dans
    // ce cabinet pour accéder à son dossier documentaire.
    if is_practitioner {
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
    }

    // R10 : même garde de scope secrétariat que list_patient_documents —
    // sans elle, une secrétaire pouvait sonder/télécharger un document
    // administratif d'un patient hors de son secrétariat (#3823/#3821).
    if claims.role == "secretary" {
        let in_scope = match claims.secretariat_id {
            Some(secretariat_id) => sqlx::query(
                "SELECT 1 FROM appointment a \
                 JOIN provider pr ON pr.practitioner_id = a.practitioner_id \
                 JOIN provider_secretariat ps ON ps.provider_id = pr.id \
                 WHERE a.patient_id = $1 \
                   AND a.deleted_at IS NULL \
                   AND a.status <> 'cancelled' \
                   AND ps.secretariat_id = $2 \
                   AND ps.active = true",
            )
            .bind(patient_id)
            .bind(secretariat_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .is_some(),
            None => false,
        };
        if !in_scope {
            return Err(AppError::NotFound);
        }
    }

    // Document rattaché à ce patient — même union à deux familles que
    // list_patient_documents (cabinet-natif OU coffre-fort plateforme
    // rattaché via patient_account_id, migration 0135).
    let row = sqlx::query(
        "SELECT d.storage_key, d.category \
         FROM document d \
         WHERE d.id = $1 \
           AND ( \
             (d.patient_id = $2 AND d.cabinet_id = $3) \
             OR (d.cabinet_id IS NULL \
                 AND d.patient_account_id = ( \
                   SELECT patient_account_id FROM patient WHERE id = $2 \
                 )) \
           ) \
           AND d.deleted_at IS NULL",
    )
    .bind(doc_id)
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let storage_key: String = row.try_get("storage_key").map_err(|_| AppError::Internal)?;
    let category: String = row.try_get("category").map_err(|_| AppError::Internal)?;

    // §14 : un non-praticien ne peut télécharger qu'une catégorie administrative.
    // NotFound ici (et non Forbidden) : la LISTE (list_patient_documents) masque
    // déjà les catégories cliniques au secrétariat, donc un 403 sur ce endpoint
    // révélerait l'existence d'un document clinique (oracle d'existence,
    // cf. issue #4757). On renvoie 404, indistinct du cas « document inexistant ».
    if !is_practitioner && !NON_CLINICAL_CATEGORIES.contains(&category.as_str()) {
        return Err(AppError::NotFound);
    }

    let signed_url = signer.sign(&storage_key).ok_or(AppError::LinkExpired)?;

    // Audit — action read_document, zéro PII (même action que le téléchargement patient).
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'read_document', 'document', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(doc_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let expires_at = chrono::Utc::now() + chrono::Duration::seconds(PRESIGN_TTL_SECS);

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        doc_id = %doc_id,
        "cabinet document download url generated"
    );

    Ok(Json(CabinetDocumentDownloadResponse {
        download_url: signed_url,
        expires_at: expires_at.to_rfc3339(),
    }))
}
