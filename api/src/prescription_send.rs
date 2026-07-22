//! Handler `POST /v1/cabinet/prescriptions/{id}/send` — extrait de
//! `prescriptions.rs` (refactor de taille, CLAUDE.md plafond 700 lignes,
//! avant d'ajouter #4131) : module autonome, même handler/contrat, aucun
//! changement fonctionnel.

use std::sync::Arc;

use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    Json,
};
use serde::Deserialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

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
        "SELECT patient_id, practitioner_id, status, document_id \
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
    let document_id: Option<Uuid> = row.try_get("document_id").map_err(|_| AppError::Internal)?;

    // Seul le praticien prescripteur peut envoyer sa propre ordonnance à la
    // pharmacie (même garde que sign_prescription). #3684.
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
