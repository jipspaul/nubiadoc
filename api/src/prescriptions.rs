//! Handlers prescriptions : `POST /v1/cabinet/prescriptions` (création) et
//! `POST /v1/cabinet/prescriptions/{id}/sign` (signature eIDAS).

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState, SignatureClient,
};

// ── POST /v1/cabinet/prescriptions ───────────────────────────────────────────

/// Un item de médicament dans le body de création.
#[derive(Deserialize)]
pub struct PrescriptionItemInput {
    pub label: String,
    pub form: Option<String>,
    pub posology: String,
    pub duration: String,
    pub quantity: Option<String>,
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

    // Insère la prescription (statut draft).
    let presc_row = sqlx::query(
        "INSERT INTO prescription (cabinet_id, patient_id, practitioner_id, consultation_id, status) \
         VALUES ($1, $2, $3, $4, 'draft') \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.patient_id)
    .bind(practitioner_id)
    .bind(body.consultation_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let prescription_id: Uuid = presc_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Insère chaque ligne médicament.
    for item in &body.items {
        sqlx::query(
            "INSERT INTO prescription_item \
             (cabinet_id, prescription_id, label, form, posology, duration, quantity) \
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(claims.cabinet_id)
        .bind(prescription_id)
        .bind(&item.label)
        .bind(&item.form)
        .bind(&item.posology)
        .bind(&item.duration)
        .bind(&item.quantity)
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
        "SELECT id, label, form, posology, duration, quantity \
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

// ── POST /v1/cabinet/prescriptions/:id/send ──────────────────────────────────

/// Body de `POST /v1/cabinet/prescriptions/{id}/send`.
#[derive(Deserialize)]
pub struct SendPrescriptionBody {
    pub pharmacy_id: Uuid,
    /// Canal de recueil du consentement patient (défaut `verbal_in_office`).
    pub consent_channel: Option<String>,
}

/// `POST /v1/cabinet/prescriptions/{id}/send` — envoie l'ordonnance signée à
/// une pharmacie (crée la commande click-and-collect, docs/12 §17 et §22).
///
/// Token pro `practitioner` ou `admin` requis — `secretary` → 403.
/// - Prescription inexistante ou hors tenant → 404.
/// - Prescription non signée → 409 `invalid_status`.
/// - Pharmacie inconnue ou non listée → 404.
/// - Patient sans compte app (impossible de suivre la commande) → 422.
/// - Commande active déjà existante pour cette ordonnance → 409.
/// - Consentement patient tracé (`consent_record`, purpose `partage_pharmacie`,
///   evidence `{channel, collected_by}`) ; transition `signed → sent`.
pub async fn send_prescription(
    State(state): State<AppState>,
    Extension(hub): Extension<Arc<crate::realtime::WsHub>>,
    Extension(dispatcher): Extension<Arc<dyn crate::JobDispatcher>>,
    claims: ProPractitionerClaims,
    Path(prescription_id): Path<Uuid>,
    Json(body): Json<SendPrescriptionBody>,
) -> Result<(StatusCode, Json<crate::pharmacy::orders::OrderDto>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT patient_id, status, document_id \
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
    let document_id: Option<Uuid> = row.try_get("document_id").map_err(|_| AppError::Internal)?;

    // `sent` reste ré-envoyable (ex. après annulation patient) — l'index
    // unique partiel bloque les doublons actifs.
    if status != "signed" && status != "sent" {
        return Err(AppError::InvalidStatus);
    }
    let document_id = document_id.ok_or(AppError::InvalidStatus)?;

    // Pharmacie listée uniquement (policy annuaire public).
    let pharmacy = sqlx::query("SELECT raison_sociale FROM pharmacy WHERE id = $1 AND is_listed")
        .bind(body.pharmacy_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;
    let pharmacy_name: String = pharmacy
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;

    // Le suivi patient exige un compte app lié à la fiche patient.
    let account_row = sqlx::query("SELECT patient_account_id FROM patient WHERE id = $1")
        .bind(patient_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::Internal)?;
    let patient_account_id: Uuid = account_row
        .try_get::<Option<Uuid>, _>("patient_account_id")
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::ValidationError)?;

    let patient_display_name =
        crate::pharmacy::orders::minimized_patient_name(&mut tx, patient_id).await?;

    // Consentement (recueilli au cabinet). GUC compte requis pour l'upsert
    // (policy consent_account_update 0048) — valeur DB, jamais client.
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(patient_account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let channel = body
        .consent_channel
        .as_deref()
        .unwrap_or("verbal_in_office");
    let consent_row = sqlx::query(
        "INSERT INTO consent_record \
         (patient_account_id, purpose, granted, evidence) \
         VALUES ($1, 'partage_pharmacie', true, $2) \
         ON CONFLICT (patient_account_id, purpose) DO UPDATE \
         SET granted = true, granted_at = now(), revoked_at = NULL, \
             evidence = EXCLUDED.evidence \
         RETURNING id",
    )
    .bind(patient_account_id)
    .bind(serde_json::json!({
        "channel": channel,
        "collected_by": claims.sub,
        "pharmacy_id": body.pharmacy_id,
    }))
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let consent_record_id: Uuid = consent_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Création de la commande — doublon actif → 409 (index unique partiel).
    let order_row = sqlx::query(
        "INSERT INTO pharmacy_order \
         (pharmacy_id, cabinet_id, patient_account_id, prescription_id, document_id, \
          created_by_kind, created_by, consent_record_id, pharmacy_name, patient_display_name) \
         VALUES ($1, $2, $3, $4, $5, 'practitioner', $6, $7, $8, $9) \
         RETURNING id, pharmacy_id, pharmacy_name, patient_display_name, prescription_id, \
                   status, rejection_reason, received_at, updated_at, ready_at, picked_up_at",
    )
    .bind(body.pharmacy_id)
    .bind(claims.cabinet_id)
    .bind(patient_account_id)
    .bind(prescription_id)
    .bind(document_id)
    .bind(claims.sub)
    .bind(consent_record_id)
    .bind(&pharmacy_name)
    .bind(&patient_display_name)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            AppError::InvalidStatus
        }
        _ => AppError::Internal,
    })?;

    // Transition signed → sent.
    sqlx::query("UPDATE prescription SET status = 'sent' WHERE id = $1 AND cabinet_id = $2")
        .bind(prescription_id)
        .bind(claims.cabinet_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Audit — action send_prescription, zéro PII.
    sqlx::query(
        "INSERT INTO audit_log (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'practitioner', 'send_prescription', 'prescription', $3)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(prescription_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let order = crate::pharmacy::orders::order_from_row(&order_row)?;

    // Notification du staff pharmacie « nouvelle commande » (lot B4).
    let staff = crate::notify::notify_pharmacy_staff(
        &mut tx,
        body.pharmacy_id,
        "order_received",
        "Nouvelle commande reçue",
        serde_json::json!({ "order_id": order.id, "status": "received" }),
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    for (app_user_id, notification_id) in staff {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }
    hub.publish_named(
        &format!("pharmacy_orders:{}", body.pharmacy_id),
        crate::notify::order_event(
            &format!("pharmacy_orders:{}", body.pharmacy_id),
            order.id,
            "received",
        ),
    );

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        prescription_id = %prescription_id,
        order_id = %order.id,
        "prescription sent to pharmacy"
    );
    Ok((StatusCode::CREATED, Json(order)))
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

/// Réponse de `GET /v1/account/prescriptions`.
#[derive(Serialize)]
pub struct AccountPrescriptionsResponse {
    pub data: Vec<AccountPrescriptionItem>,
}

/// `GET /v1/account/prescriptions` — ordonnances visibles par le compte
/// patient (policy `prescription_patient_read`, 0109). Fournit les ids
/// nécessaires à `POST /v1/account/prescriptions/{id}/order`.
/// Les brouillons (`status = 'draft'`, jamais signés/envoyés) sont exclus,
/// cohérent avec la liste devis patient (fix #3487) : cf. issue #3622.
pub async fn list_account_prescriptions(
    State(state): State<AppState>,
    claims: crate::auth::PatientAccountClaims,
) -> Result<Json<AccountPrescriptionsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, status, document_id, created_at, signed_at \
         FROM prescription WHERE deleted_at IS NULL AND status <> 'draft' \
         ORDER BY created_at DESC LIMIT 100",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(|row| {
            Ok(AccountPrescriptionItem {
                id: row.try_get("id").map_err(|_| AppError::Internal)?,
                status: row.try_get("status").map_err(|_| AppError::Internal)?,
                document_id: row.try_get("document_id").map_err(|_| AppError::Internal)?,
                created_at: row
                    .try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
                    .map_err(|_| AppError::Internal)?
                    .to_rfc3339(),
                signed_at: row
                    .try_get::<Option<chrono::DateTime<chrono::Utc>>, _>("signed_at")
                    .map_err(|_| AppError::Internal)?
                    .map(|dt| dt.to_rfc3339()),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(AccountPrescriptionsResponse { data }))
}
