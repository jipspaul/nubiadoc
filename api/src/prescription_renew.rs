//! Handler `POST /v1/cabinet/prescriptions/{id}/renew` (#4131) : duplique
//! les lignes d'une ordonnance existante dans un nouveau brouillon, pour
//! éviter au praticien de tout retaper à chaque renouvellement.
//!
//! Module dédié plutôt qu'ajouté à `prescriptions.rs` (déjà ramené à 551
//! lignes par le refactor `prescription_send.rs`, mais garder les nouvelles
//! fonctionnalités dans des modules séparés évite de re-grossir le fichier
//! au fil des issues).

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

/// Réponse de `POST /v1/cabinet/prescriptions/{id}/renew`.
#[derive(Serialize)]
pub struct RenewPrescriptionResponse {
    pub prescription_id: Uuid,
}

/// `POST /v1/cabinet/prescriptions/{id}/renew` — copie les
/// `prescription_item` d'une ordonnance existante dans une nouvelle
/// `prescription` en statut `draft`, sur le pattern transactionnel de
/// `create_prescription`.
///
/// - Auth JWT pro `practitioner` ou `admin` requis — `secretary` → 403.
/// - `cabinet_id` extrait du JWT (jamais du path — invariant tenancy).
/// - Ordonnance source inexistante ou hors tenant → 404.
/// - Le praticien appelant doit avoir eu au moins un `appointment` avec le
///   patient de l'ordonnance source dans ce cabinet (même garde relation-de-
///   soin E.2.16.c §14 que `create_prescription` — pas de restriction au
///   seul prescripteur d'origine : contrairement à `sign`/`send`, un
///   renouvellement en brouillon n'engage aucune signature).
/// - Peut renouveler une ordonnance de N'IMPORTE QUEL statut (draft/signed/
///   sent) — l'issue ne restreint pas aux seules ordonnances signées, et
///   dupliquer un brouillon existant reste inoffensif.
/// - Le nouveau brouillon est rattaché au praticien appelant (pas au
///   prescripteur d'origine) et n'a pas de `consultation_id` (aucune séance
///   de rattachement lors d'un renouvellement hors consultation).
/// - Audit `action:'renew_prescription', entity:'prescription'`.
/// - Retourne `201 { prescription_id }`.
pub async fn renew_prescription(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(source_id): Path<Uuid>,
) -> Result<(StatusCode, Json<RenewPrescriptionResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let prac_row =
        sqlx::query("SELECT id FROM practitioner WHERE cabinet_id = $1 AND user_id = $2")
            .bind(claims.cabinet_id)
            .bind(claims.sub)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::Forbidden)?;
    let practitioner_id: Uuid = prac_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Ordonnance source — 404 si hors tenant (RLS fail-closed + filtre explicite).
    let source_row = sqlx::query(
        "SELECT patient_id FROM prescription \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(source_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let patient_id: Uuid = source_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

    // Garde relation-de-soin E.2.16.c §14 (miroir create_prescription).
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

    // Nouvelle prescription (statut draft, rattachée au praticien appelant).
    let new_row = sqlx::query(
        "INSERT INTO prescription (cabinet_id, patient_id, practitioner_id, status) \
         VALUES ($1, $2, $3, 'draft') \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let new_prescription_id: Uuid = new_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Copie des lignes de l'ordonnance source.
    let items_copied = sqlx::query(
        "INSERT INTO prescription_item \
         (cabinet_id, prescription_id, label, form, posology, duration, quantity) \
         SELECT cabinet_id, $1, label, form, posology, duration, quantity \
         FROM prescription_item WHERE prescription_id = $2 AND cabinet_id = $3",
    )
    .bind(new_prescription_id)
    .bind(source_id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .rows_affected();

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'practitioner', 'renew_prescription', 'prescription', $3)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(new_prescription_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        source_prescription_id = %source_id,
        new_prescription_id = %new_prescription_id,
        items_copied,
        "prescription renewed"
    );

    Ok((
        StatusCode::CREATED,
        Json(RenewPrescriptionResponse {
            prescription_id: new_prescription_id,
        }),
    ))
}
