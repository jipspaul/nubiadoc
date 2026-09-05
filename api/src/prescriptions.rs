//! Handlers prescriptions : `POST /v1/cabinet/prescriptions` (création) et
//! `POST /v1/cabinet/prescriptions/{id}/sign` (signature eIDAS).

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, Query, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState, ObjectStorage, SignatureClient,
};

/// Valide la forme de `structured_posology` : `{dose: number,
/// frequency_per_day: number, duration_in_days: integer}` (design-v2,
/// #4991-#4999 ; cf. décodeur strict Flutter `StructuredPosologyDto.fromJson`,
/// `prescription_dto.dart:60-65`). Accepté tel quel côté serveur avant #6156,
/// un champ manquant ou d'un mauvais type était persisté en JSONB opaque et
/// faisait échouer le décodage strict côté client (`TypeError` -> tout le
/// Journal du patient disparaissait).
fn validate_structured_posology(value: &serde_json::Value) -> Result<(), AppError> {
    let obj = value.as_object().ok_or(AppError::ValidationError)?;

    obj.get("dose")
        .and_then(serde_json::Value::as_f64)
        .ok_or(AppError::ValidationError)?;
    obj.get("frequency_per_day")
        .and_then(serde_json::Value::as_f64)
        .ok_or(AppError::ValidationError)?;
    obj.get("duration_in_days")
        .and_then(serde_json::Value::as_i64)
        .ok_or(AppError::ValidationError)?;

    Ok(())
}

// ── POST /v1/cabinet/prescriptions ───────────────────────────────────────────

/// Un item de médicament dans le body de création.
#[derive(Deserialize)]
pub struct PrescriptionItemInput {
    pub label: String,
    pub form: Option<String>,
    pub posology: String,
    pub duration: String,
    pub quantity: Option<String>,
    /// Posologie décomposée `{dose, frequency_per_day, duration_in_days}`
    /// (design-v2, #4991-#4999). `None` pour une ligne en texte libre.
    #[serde(default)]
    pub structured_posology: Option<serde_json::Value>,
    /// Référence produit référentiel médicament `{id, dci, galenic_form,
    /// therapeutic_class}` (design-v2). `None` hors référentiel.
    #[serde(default)]
    pub product_reference: Option<serde_json::Value>,
    /// Motif de la mention légale « non substituable » (ex. MTE).
    #[serde(default)]
    pub non_substitution_reason: Option<String>,
    /// Mention légale « non renouvelable ».
    #[serde(default)]
    pub non_renouvelable: bool,
}

/// Body de `POST /v1/cabinet/prescriptions`.
#[derive(Deserialize)]
pub struct CreatePrescriptionBody {
    pub consultation_id: Option<Uuid>,
    pub patient_id: Uuid,
    pub items: Vec<PrescriptionItemInput>,
}

/// Réponse de `POST /v1/cabinet/prescriptions`.
#[derive(Serialize)]
pub struct CreatePrescriptionResponse {
    pub prescription_id: Uuid,
}

/// `POST /v1/cabinet/prescriptions` — crée une ordonnance (statut `draft`) avec ses lignes.
///
/// - Auth JWT pro `practitioner` ou `admin` requis — `secretary` → 403.
/// - `cabinet_id` extrait du JWT (jamais du body — invariant tenancy).
/// - Body invalide (items vides, champs manquants) → 422 (Axum rejection).
/// - `patient_id` inconnu/hors tenant → 404 ; sans relation de soin
///   (aucun `appointment` du praticien avec ce patient) → 403 (#3769).
/// - `consultation_id` (si fourni) inexistant, hors tenant ou hors patient → 404 (#3790).
/// - Insert `prescription` + N `prescription_item` dans la même transaction RLS-scoped.
/// - Audit `action:'create_prescription', entity:'prescription'`.
/// - Retourne `201 { prescription_id }`.
pub async fn create_prescription(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Json(body): Json<CreatePrescriptionBody>,
) -> Result<(StatusCode, Json<CreatePrescriptionResponse>), AppError> {
    if body.items.is_empty() {
        return Err(AppError::ValidationError);
    }
    if body.items.iter().any(|i| {
        i.label.trim().is_empty() || i.posology.trim().is_empty() || i.duration.trim().is_empty()
    }) {
        return Err(AppError::ValidationError);
    }
    // #4410 : NUL byte non filtré → bind Postgres échoue, masqué en 500.
    for item in &body.items {
        crate::text_validation::reject_nul_byte(&item.label)?;
        crate::text_validation::reject_nul_byte(&item.posology)?;
        crate::text_validation::reject_nul_byte(&item.duration)?;
        if let Some(form) = &item.form {
            crate::text_validation::reject_nul_byte(form)?;
        }
        if let Some(quantity) = &item.quantity {
            crate::text_validation::reject_nul_byte(quantity)?;
        }
        if let Some(reason) = &item.non_substitution_reason {
            crate::text_validation::reject_nul_byte(reason)?;
        }
        if let Some(structured_posology) = &item.structured_posology {
            validate_structured_posology(structured_posology)?;
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope RLS tenant — SET LOCAL à chaque opération DB (règle hard #1).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Résout le practitioner_id depuis le user_id JWT (clé cabinet + user).
    let prac_row =
        sqlx::query("SELECT id FROM practitioner WHERE cabinet_id = $1 AND user_id = $2")
            .bind(claims.cabinet_id)
            .bind(claims.sub)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::Forbidden)?;

    let practitioner_id: Uuid = prac_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Vérifie que le patient appartient au cabinet (RLS garantit le tenant).
    let patient_exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(body.patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // RLS strict E.2.16.c : le praticien doit avoir eu au moins un appointment
    // avec ce patient dans ce cabinet (§14 — garde relation-de-soin, cf. #3769 —
    // manquait ici alors qu'elle est imposée par tous les frères cliniques :
    // add_patient_note, patch_medical_record, put_dental_chart).
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
           AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(body.patient_id)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    // Vérifie que la consultation (si fournie) existe, appartient au cabinet
    // et concerne bien ce patient — sinon FK 23503 remontée en 500 (#3790).
    // #6204 : capture aussi l'appointment_id de la séance, dénormalisé sur
    // la prescription pour restituer « N ordonnance(s) » dans
    // GET /v1/appointments (chip historique patient).
    let mut appointment_id: Option<Uuid> = None;
    if let Some(consultation_id) = body.consultation_id {
        let consultation_row = sqlx::query(
            "SELECT a.id AS appointment_id FROM consultation_session cs \
             JOIN appointment a ON a.id = cs.appointment_id \
             WHERE cs.id = $1 AND cs.cabinet_id = $2 AND a.patient_id = $3",
        )
        .bind(consultation_id)
        .bind(claims.cabinet_id)
        .bind(body.patient_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        let consultation_row = consultation_row.ok_or(AppError::NotFound)?;
        appointment_id = Some(
            consultation_row
                .try_get("appointment_id")
                .map_err(|_| AppError::Internal)?,
        );
    }

    // Insère la prescription (statut draft).
    let presc_row = sqlx::query(
        "INSERT INTO prescription \
         (cabinet_id, patient_id, practitioner_id, consultation_id, appointment_id, status) \
         VALUES ($1, $2, $3, $4, $5, 'draft') \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.patient_id)
    .bind(practitioner_id)
    .bind(body.consultation_id)
    .bind(appointment_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let prescription_id: Uuid = presc_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Insère chaque ligne médicament.
    for item in &body.items {
        sqlx::query(
            "INSERT INTO prescription_item \
             (cabinet_id, prescription_id, label, form, posology, duration, quantity, \
              structured_posology, product_reference, non_substitution_reason, non_renouvelable) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
        )
        .bind(claims.cabinet_id)
        .bind(prescription_id)
        .bind(&item.label)
        .bind(&item.form)
        .bind(&item.posology)
        .bind(&item.duration)
        .bind(&item.quantity)
        .bind(&item.structured_posology)
        .bind(&item.product_reference)
        .bind(&item.non_substitution_reason)
        .bind(item.non_renouvelable)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    // Audit — zéro PII, action create_prescription.
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'create_prescription', 'prescription', $4)",
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
        items = body.items.len(),
        "prescription created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreatePrescriptionResponse { prescription_id }),
    ))
}

/// Réponse de `POST /v1/cabinet/prescriptions/{id}/sign`.
#[derive(Serialize)]
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
    Extension(object_storage): Extension<Arc<dyn ObjectStorage>>,
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
        "SELECT id, patient_id, practitioner_id, status, created_at \
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
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let prescription_created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    // Seul le praticien prescripteur peut signer sa propre ordonnance : la
    // signature eIDAS (AES) engage sa responsabilité. Le scope cabinet (RLS) ne
    // suffit pas — on vérifie prescription.practitioner_id -> practitioner.user_id
    // == claims.sub, comme add_consultation_act / complete_consultation. #3684.
    let owner = sqlx::query(
        "SELECT id FROM practitioner WHERE id = $1 AND user_id = $2 AND cabinet_id = $3",
    )
    .bind(practitioner_id)
    .bind(claims.sub)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if owner.is_none() {
        return Err(AppError::Forbidden);
    }

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

    // Lignes de l'ordonnance — nécessaires au rendu du PDF.
    let item_rows = sqlx::query(
        "SELECT label, form, posology, duration, quantity \
         FROM prescription_item \
         WHERE prescription_id = $1 AND cabinet_id = $2",
    )
    .bind(prescription_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let items: Vec<PrescriptionItemInput> = item_rows
        .into_iter()
        .map(|r| {
            Ok::<_, AppError>(PrescriptionItemInput {
                label: r.try_get("label").map_err(|_| AppError::Internal)?,
                form: r.try_get("form").map_err(|_| AppError::Internal)?,
                posology: r.try_get("posology").map_err(|_| AppError::Internal)?,
                duration: r.try_get("duration").map_err(|_| AppError::Internal)?,
                quantity: r.try_get("quantity").map_err(|_| AppError::Internal)?,
                // Non nécessaires au rendu PDF (render_prescription_pdf n'imprime
                // que label/form/posology/duration/quantity) — pas de colonne
                // supplémentaire à sélectionner ici.
                structured_posology: None,
                product_reference: None,
                non_substitution_reason: None,
                non_renouvelable: false,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    // Identité patient/praticien — affichées sur le PDF d'ordonnance.
    let patient_row = sqlx::query("SELECT first_name, last_name FROM patient WHERE id = $1")
        .bind(patient_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let patient_name = format!(
        "{} {}",
        patient_row
            .try_get::<String, _>("first_name")
            .map_err(|_| AppError::Internal)?,
        patient_row
            .try_get::<String, _>("last_name")
            .map_err(|_| AppError::Internal)?
    );

    let practitioner_row = sqlx::query(
        "SELECT COALESCE(pv.display_name, 'Praticien') AS display_name \
         FROM practitioner pr \
         LEFT JOIN provider pv ON pv.practitioner_id = pr.id \
         WHERE pr.id = $1 \
         LIMIT 1",
    )
    .bind(practitioner_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let practitioner_name: String = practitioner_row
        .try_get("display_name")
        .map_err(|_| AppError::Internal)?;

    // Génère le PDF d'ordonnance (contenu réel — remplace le stub NUB-T3) puis
    // l'upload dans l'Object Storage via le client injecté (Scaleway/MinIO en
    // prod, in-memory en test) : `storage_key` référence désormais un objet
    // effectivement uploadé, plus une clé fantôme.
    let pdf_bytes = render_prescription_pdf(
        prescription_id,
        &patient_name,
        &practitioner_name,
        prescription_created_at,
        &items,
    );
    let size_bytes = pdf_bytes.len() as i64;
    let storage_key = format!("ordonnance/{}.pdf", prescription_id);
    let filename = format!("ordonnance-{}.pdf", prescription_id);
    object_storage
        .upload(&storage_key, "application/pdf", pdf_bytes.clone())
        .await
        .map_err(|_| AppError::Internal)?;

    let doc_row = sqlx::query(
        "INSERT INTO document \
         (cabinet_id, patient_id, category, storage_key, filename, mime_type, \
          sha256, scan_status, uploaded_by, size_bytes) \
         VALUES ($1, $2, 'ordonnance', $3, $4, 'application/pdf', \
                 encode(digest($5, 'sha256'), 'hex'), 'clean', $6, $7) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(&storage_key)
    .bind(&filename)
    .bind(&pdf_bytes)
    .bind(claims.sub)
    .bind(size_bytes)
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

// ── GET /v1/cabinet/prescriptions/:id ────────────────────────────────────────

/// Un item dans la réponse `PrescriptionDto`.
#[derive(Serialize)]
pub struct PrescriptionItemDto {
    pub id: Uuid,
    pub label: String,
    pub form: Option<String>,
    pub posology: String,
    pub duration: String,
    pub quantity: Option<String>,
    pub structured_posology: Option<serde_json::Value>,
    pub product_reference: Option<serde_json::Value>,
    pub non_substitution_reason: Option<String>,
    pub non_renouvelable: bool,
}

/// DTO ordonnance — partagé par create (201) et get (200).
#[derive(Serialize)]
pub struct PrescriptionDto {
    pub id: Uuid,
    pub patient_id: Uuid,
    pub consultation_id: Option<Uuid>,
    pub status: String,
    pub signed_at: Option<String>,
    pub document_id: Option<Uuid>,
    pub created_at: String,
    pub items: Vec<PrescriptionItemDto>,
}

/// `GET /v1/cabinet/prescriptions/:id` — lecture d'une ordonnance avec ses lignes.
///
/// - Auth JWT pro `practitioner` ou `admin` requis — `secretary` → 403.
/// - Prescription inexistante ou hors tenant → 404.
/// - Retourne `200 PrescriptionDto`.
pub async fn get_prescription(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(prescription_id): Path<Uuid>,
) -> Result<Json<PrescriptionDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, patient_id, consultation_id, status, signed_at, document_id, created_at \
         FROM prescription \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(prescription_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
    let consultation_id: Option<Uuid> = row
        .try_get("consultation_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let signed_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("signed_at").map_err(|_| AppError::Internal)?;
    let document_id: Option<Uuid> = row.try_get("document_id").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    let item_rows = sqlx::query(
        "SELECT id, label, form, posology, duration, quantity, \
                structured_posology, product_reference, non_substitution_reason, non_renouvelable \
         FROM prescription_item \
         WHERE prescription_id = $1 AND cabinet_id = $2",
    )
    .bind(prescription_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let items = item_rows
        .into_iter()
        .map(|r| {
            Ok(PrescriptionItemDto {
                id: r.try_get("id").map_err(|_| AppError::Internal)?,
                label: r.try_get("label").map_err(|_| AppError::Internal)?,
                form: r.try_get("form").map_err(|_| AppError::Internal)?,
                posology: r.try_get("posology").map_err(|_| AppError::Internal)?,
                duration: r.try_get("duration").map_err(|_| AppError::Internal)?,
                quantity: r.try_get("quantity").map_err(|_| AppError::Internal)?,
                structured_posology: r
                    .try_get("structured_posology")
                    .map_err(|_| AppError::Internal)?,
                product_reference: r
                    .try_get("product_reference")
                    .map_err(|_| AppError::Internal)?,
                non_substitution_reason: r
                    .try_get("non_substitution_reason")
                    .map_err(|_| AppError::Internal)?,
                non_renouvelable: r
                    .try_get("non_renouvelable")
                    .map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(PrescriptionDto {
        id,
        patient_id,
        consultation_id,
        status,
        signed_at: signed_at.map(|t| t.to_rfc3339()),
        document_id,
        created_at: created_at.to_rfc3339(),
        items,
    }))
}

// ── GET /v1/account/prescriptions ─────────────────────────────────────────────

/// Une ordonnance du patient (vue compte — id nécessaire pour l'envoi en
/// pharmacie, lot F7).
#[derive(Serialize)]
pub struct AccountPrescriptionItem {
    pub id: Uuid,
    pub status: String,
    pub document_id: Option<Uuid>,
    pub created_at: String,
    pub signed_at: Option<String>,
}

/// Pagination cursor de `page.next_cursor` (même schéma que `documents.rs`
/// `PageInfo` : `list_documents`).
#[derive(Serialize)]
pub struct AccountPrescriptionsPageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

/// Réponse de `GET /v1/account/prescriptions`.
#[derive(Serialize)]
pub struct AccountPrescriptionsResponse {
    pub data: Vec<AccountPrescriptionItem>,
    pub page: AccountPrescriptionsPageInfo,
}

#[derive(Deserialize)]
pub struct ListAccountPrescriptionsQuery {
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

fn encode_prescriptions_cursor(created_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", created_at.timestamp_micros(), id)
}

fn decode_prescriptions_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/account/prescriptions` — ordonnances visibles par le compte
/// patient, propre OU tuteur légal actif d'un dépendant (policy
/// `prescription_patient_read`, 0109/0221, #4597). Fournit les ids
/// nécessaires à `POST /v1/account/prescriptions/{id}/order`.
/// Les brouillons (`status = 'draft'`, jamais signés/envoyés) sont exclus,
/// cohérent avec la liste devis patient (fix #3487) : cf. issue #3622.
/// Paginée par curseur (`limit`/`cursor`, même schéma que `list_documents`) :
/// avant #6381, `LIMIT 100` était figé en dur, tous patients du foyer
/// confondus, sans aucun moyen d'aller au-delà.
pub async fn list_account_prescriptions(
    State(state): State<AppState>,
    claims: crate::auth::PatientAccountClaims,
    Query(params): Query<ListAccountPrescriptionsQuery>,
) -> Result<Json<AccountPrescriptionsResponse>, AppError> {
    // Défaut à 100 (comportement historique du `LIMIT 100` en dur) pour ne
    // pas régresser les clients existants qui n'envoient pas `limit` — la
    // pagination par curseur permet désormais d'aller au-delà.
    let limit: i64 = params.limit.unwrap_or(100).clamp(1, 100);
    let cursor = match params.cursor.as_deref() {
        Some(s) => Some(decode_prescriptions_cursor(s).ok_or(AppError::ValidationError)?),
        None => None,
    };
    let fetch_limit = limit + 1;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    // GUC compte : requis par la policy guardianship_owner_select (0025) pour
    // que la sous-requête account_guardianship de prescription_patient_read
    // (0109/0221) voie la tutelle du tuteur en session (#4597).
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cursor_clause = if cursor.is_some() {
        " AND (created_at < $2 OR (created_at = $2 AND id < $3))"
    } else {
        ""
    };

    let sql = format!(
        "SELECT id, status, document_id, created_at, signed_at \
         FROM prescription WHERE deleted_at IS NULL AND status <> 'draft'\
         {cursor_clause} \
         ORDER BY created_at DESC, id DESC LIMIT $1"
    );

    let rows = match cursor {
        Some((cursor_at, cursor_id)) => sqlx::query(&sql)
            .bind(fetch_limit)
            .bind(cursor_at)
            .bind(cursor_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
        None => sqlx::query(&sql)
            .bind(fetch_limit)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?,
    };
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    let data = visible
        .iter()
        .map(|row| {
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let created_at: chrono::DateTime<chrono::Utc> =
                row.try_get("created_at").map_err(|_| AppError::Internal)?;
            last_created_at = Some(created_at);
            last_id = Some(id);
            Ok(AccountPrescriptionItem {
                id,
                status: row.try_get("status").map_err(|_| AppError::Internal)?,
                document_id: row.try_get("document_id").map_err(|_| AppError::Internal)?,
                created_at: created_at.to_rfc3339(),
                signed_at: row
                    .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("signed_at")
                    .map_err(|_| AppError::Internal)?
                    .map(|dt| dt.to_rfc3339()),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| encode_prescriptions_cursor(dt, id))
    } else {
        None
    };

    Ok(Json(AccountPrescriptionsResponse {
        data,
        page: AccountPrescriptionsPageInfo { next_cursor, limit },
    }))
}

// ── GET /v1/account/prescriptions/:id ─────────────────────────────────────────

/// Un item dans la réponse détail patient — mêmes champs que
/// `pharmacy::orders::OrderItemDto` (pas de données internes cabinet comme
/// `product_reference`/`non_substitution_reason`).
#[derive(Serialize)]
pub struct AccountPrescriptionItemDto {
    pub label: String,
    pub form: Option<String>,
    pub posology: String,
    pub duration: String,
    pub quantity: Option<String>,
}

/// Réponse de `GET /v1/account/prescriptions/{id}`.
#[derive(Serialize)]
pub struct AccountPrescriptionDetailDto {
    pub id: Uuid,
    pub status: String,
    pub document_id: Option<Uuid>,
    pub created_at: String,
    pub signed_at: Option<String>,
    pub prescriber_name: Option<String>,
    pub prescriber_practice: Option<String>,
    pub items: Vec<AccountPrescriptionItemDto>,
}

/// `GET /v1/account/prescriptions/{id}` — détail (lignes + prescripteur)
/// d'une ordonnance visible par le compte patient (policy
/// `prescription_patient_read`, mêmes bornes que `list_account_prescriptions`).
/// Symétrique à `GET /v1/account/orders/{id}` — corrige #6507 : jusqu'ici
/// seule une coquille technique (id/status/document_id/dates) était exposée
/// côté liste, sans libellé, posologie, durée ni prescripteur, et aucune
/// route de détail n'existait (404 routeur).
///
/// - Ordonnance invisible (RLS) ou en `draft` → 404 (un brouillon n'est
///   jamais un document opposable, cohérent avec la liste).
pub async fn get_account_prescription(
    State(state): State<AppState>,
    claims: crate::auth::PatientAccountClaims,
    Path(prescription_id): Path<Uuid>,
) -> Result<Json<AccountPrescriptionDetailDto>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    // GUC compte : requis par guardianship_owner_select (0025) pour que la
    // sous-requête account_guardianship de prescription_patient_read
    // (0109/0223) voie la tutelle du tuteur en session (#4597).
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, cabinet_id, practitioner_id, status, document_id, created_at, signed_at \
         FROM prescription \
         WHERE id = $1 AND deleted_at IS NULL AND status <> 'draft'",
    )
    .bind(prescription_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let document_id: Option<Uuid> = row.try_get("document_id").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    let signed_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("signed_at").map_err(|_| AppError::Internal)?;

    // GUC cabinet : nécessaire pour résoudre le prescripteur (#6253, cf.
    // pharmacy::orders::prescriber_identity) sous les policies
    // `tenant_isolation` (cabinet) / `provider_cabinet_manage` — même schéma
    // que pharmacy::orders::create_account_order.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let (prescriber_name, prescriber_practice) =
        crate::pharmacy::orders::prescriber_identity(&mut tx, cabinet_id, practitioner_id).await?;

    // RLS `prescription_line_patient_read` (0108, étendue par 0243) borne
    // déjà aux lignes des ordonnances du patient courant OU d'un dépendant
    // sous tutelle active, via les GUC posés ci-dessus.
    let item_rows = sqlx::query(
        "SELECT label, form, posology, duration, quantity \
         FROM prescription_item WHERE prescription_id = $1",
    )
    .bind(prescription_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let items = item_rows
        .into_iter()
        .map(|r| {
            Ok(AccountPrescriptionItemDto {
                label: r.try_get("label").map_err(|_| AppError::Internal)?,
                form: r.try_get("form").map_err(|_| AppError::Internal)?,
                posology: r.try_get("posology").map_err(|_| AppError::Internal)?,
                duration: r.try_get("duration").map_err(|_| AppError::Internal)?,
                quantity: r.try_get("quantity").map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(AccountPrescriptionDetailDto {
        id,
        status,
        document_id,
        created_at: created_at.to_rfc3339(),
        signed_at: signed_at.map(|t| t.to_rfc3339()),
        prescriber_name,
        prescriber_practice,
        items,
    }))
}

// ── Génération PDF de l'ordonnance signée ────────────────────────────────────

/// Génère le contenu binaire (PDF minimal valide) de l'ordonnance signée.
///
/// Remplace le stub NUB-T3 (`size_bytes=0`, `sha256` nul) : construit un vrai
/// PDF (structure `%PDF-1.4` + objets + stream de contenu texte) à partir des
/// lignes de prescription, du patient et du praticien. Pas de dépendance
/// externe (crate PDF) : la structure minimale suffit à obtenir un document
/// ouvrable par n'importe quel lecteur PDF, avec un contenu réel et non nul —
/// c'est le strict nécessaire pour corriger le bug (taille et hash réels,
/// document lisible par la pharmacie).
fn render_prescription_pdf(
    prescription_id: Uuid,
    patient_name: &str,
    practitioner_name: &str,
    created_at: chrono::DateTime<chrono::Utc>,
    items: &[PrescriptionItemInput],
) -> Vec<u8> {
    let escape = |s: &str| {
        s.replace('\\', "\\\\")
            .replace('(', "\\(")
            .replace(')', "\\)")
    };

    let mut lines: Vec<String> = vec![
        "Ordonnance".to_string(),
        format!("Patient : {}", patient_name),
        format!("Praticien : {}", practitioner_name),
        format!("Date : {}", created_at.to_rfc3339()),
        format!("Reference : {}", prescription_id),
        String::new(),
    ];
    for item in items {
        let mut line = item.label.clone();
        if let Some(form) = &item.form {
            line.push_str(&format!(" ({})", form));
        }
        line.push_str(&format!(" - {}", item.posology));
        line.push_str(&format!(" - {}", item.duration));
        if let Some(quantity) = &item.quantity {
            line.push_str(&format!(" - QSP {}", quantity));
        }
        lines.push(line);
    }

    let mut content = String::from("BT /F1 12 Tf 50 780 Td 14 TL\n");
    for line in &lines {
        content.push_str(&format!("({}) Tj T*\n", escape(line)));
    }
    content.push_str("ET");

    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>".to_string(),
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_string(),
        "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> \
         /MediaBox [0 0 595 842] /Contents 4 0 R >>"
            .to_string(),
        format!(
            "<< /Length {} >>\nstream\n{}\nendstream",
            content.len(),
            content
        ),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".to_string(),
    ];

    let mut pdf = String::from("%PDF-1.4\n");
    let mut offsets = Vec::with_capacity(objects.len());
    for (i, obj) in objects.iter().enumerate() {
        offsets.push(pdf.len());
        pdf.push_str(&format!("{} 0 obj\n{}\nendobj\n", i + 1, obj));
    }
    let xref_offset = pdf.len();
    pdf.push_str(&format!("xref\n0 {}\n", objects.len() + 1));
    pdf.push_str("0000000000 65535 f \n");
    for off in &offsets {
        pdf.push_str(&format!("{:010} 00000 n \n", off));
    }
    pdf.push_str(&format!(
        "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{}\n%%EOF",
        objects.len() + 1,
        xref_offset
    ));

    pdf.into_bytes()
}
