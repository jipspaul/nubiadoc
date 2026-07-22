//! Handler `GET /v1/cabinet/patients/:id/alerts` (#4093) : alertes
//! administratives agrégées pour l'accueil secrétariat — factures signées
//! impayées échues + documents administratifs attendus manquants.
//!
//! Volontairement exclu : toute précaution médicale/clinique (hors périmètre
//! secrétariat, R.4127-72 — même exclusion que `patient_detail.rs`).

use axum::{
    extract::{Path, State},
    Json,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Un devis signé est considéré « échu » 30 jours après signature s'il reste
/// un solde dû non couvert par un paiement pending/paid — seuil choisi en
/// l'absence d'un délai de relance déjà configuré ailleurs dans le domaine
/// (aucune donnée « délai de paiement contractuel » n'existe sur `cabinet`).
const OVERDUE_INVOICE_DELAY_DAYS: i32 = 30;

#[derive(Serialize)]
pub struct PatientAlert {
    pub kind: String,
    pub message: String,
    pub data: serde_json::Value,
}

#[derive(Serialize)]
pub struct PatientAlertsResponse {
    pub alerts: Vec<PatientAlert>,
}

/// `GET /v1/cabinet/patients/:id/alerts` — alertes administratives (impayés,
/// documents manquants), lecture seule.
///
/// Facture impayée échue : au moins un devis `signed` du patient dont
/// `signed_at` a plus de [`OVERDUE_INVOICE_DELAY_DAYS`] jours ET dont le
/// solde patient (même formule que `patient_detail::balance_due_cents`) est
/// encore positif. Document manquant : aucune `document.category =
/// 'carte_mutuelle'` non supprimée pour ce patient.
pub async fn get_patient_alerts(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<PatientAlertsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let patient_exists = sqlx::query("SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2")
        .bind(patient_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let mut alerts = Vec::new();

    let overdue_row = sqlx::query(
        "SELECT \
           (( \
             COALESCE((SELECT SUM(total_amount) FROM quote \
                       WHERE patient_id = $1 AND cabinet_id = $2 \
                         AND status = 'signed' AND deleted_at IS NULL), 0) \
             - \
             COALESCE((SELECT SUM(amount) FROM payment \
                       WHERE patient_id = $1 AND cabinet_id = $2 \
                         AND status IN ('pending', 'paid')), 0) \
           ) * 100)::bigint AS balance_due_cents, \
           (SELECT MIN(signed_at) FROM quote \
            WHERE patient_id = $1 AND cabinet_id = $2 \
              AND status = 'signed' AND deleted_at IS NULL \
              AND signed_at < now() - make_interval(days => $3)) AS oldest_overdue_signed_at",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .bind(OVERDUE_INVOICE_DELAY_DAYS)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let balance_due_cents: i64 = overdue_row
        .try_get("balance_due_cents")
        .map_err(|_| AppError::Internal)?;
    let oldest_overdue_signed_at: Option<chrono::DateTime<chrono::Utc>> = overdue_row
        .try_get("oldest_overdue_signed_at")
        .map_err(|_| AppError::Internal)?;
    if balance_due_cents > 0 {
        if let Some(signed_at) = oldest_overdue_signed_at {
            alerts.push(PatientAlert {
                kind: "unpaid_invoice".to_string(),
                message: "Facture signée impayée depuis plus de 30 jours.".to_string(),
                data: serde_json::json!({
                    "balance_due_cents": balance_due_cents,
                    "signed_at": signed_at.to_rfc3339(),
                }),
            });
        }
    }

    let missing_card = sqlx::query(
        "SELECT 1 FROM document \
         WHERE patient_id = $1 AND cabinet_id = $2 \
           AND category = 'carte_mutuelle' AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if missing_card.is_none() {
        alerts.push(PatientAlert {
            kind: "missing_document".to_string(),
            message: "Carte mutuelle non scannée.".to_string(),
            data: serde_json::json!({ "category": "carte_mutuelle" }),
        });
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(PatientAlertsResponse { alerts }))
}
