//! Handler `GET /v1/cabinet/patients/:id/alerts` (#4093) : alertes
//! administratives agrégées pour l'accueil secrétariat — factures signées
//! impayées échues + documents administratifs attendus manquants + bon de
//! travail prothétique non reçu la veille d'un RDV de pose (`#7208`).
//!
//! Volontairement exclu : toute précaution médicale/clinique (hors périmètre
//! secrétariat, R.4127-72 — même exclusion que `patient_detail.rs`). Le
//! suivi logistique d'un bon de travail prothétique n'en fait pas partie :
//! c'est un aléa de transit labo, pas un jugement clinique.

use axum::{
    extract::{Path, State},
    Json,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    lab_work_orders,
    patient_tags::ensure_secretary_scope,
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
/// documents manquants, prothèse non reçue), lecture seule.
///
/// Facture impayée échue : au moins un devis `signed` du patient dont
/// `signed_at` a plus de [`OVERDUE_INVOICE_DELAY_DAYS`] jours ET dont le
/// solde patient — part patient nette des devis signés (`quote_item.unit_amount
/// - amo_part - amc_part`, même formule que `patient_share_cents` exposée par
/// `GET /cabinet/quotes/:id`, #4794), pas le montant brut du devis — moins les
/// paiements enregistrés, est encore positif. Document manquant : aucune
/// `document.category = 'carte_mutuelle'` non supprimée pour ce patient.
/// Prothèse non reçue (#7208) : un `lab_work_order` du patient rattaché à un
/// `appointment` de demain (J+1) dont le statut n'a pas encore atteint
/// `received` dans [`lab_work_orders::STATUS_ORDER`].
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
    ensure_secretary_scope(&mut tx, &claims, patient_id).await?;

    let mut alerts = Vec::new();

    let overdue_row = sqlx::query(
        "SELECT \
           (( \
             COALESCE((SELECT SUM(qi.qty * qi.unit_amount \
                               - COALESCE(qi.amo_part, 0) - COALESCE(qi.amc_part, 0)) \
                       FROM quote_item qi \
                       JOIN quote q ON q.id = qi.quote_id \
                       WHERE q.patient_id = $1 AND q.cabinet_id = $2 \
                         AND q.status = 'signed' AND q.deleted_at IS NULL), 0) \
             - \
             COALESCE((SELECT SUM(amount) FROM payment \
                       WHERE patient_id = $1 AND cabinet_id = $2 \
                         AND quote_id IS NOT NULL \
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

    // #7208 (DP-F3.b) : RDV de pose demain (J+1) alors que le bon de travail
    // prothétique lié n'est pas encore arrivé au cabinet — logistique de
    // suivi labo, pas une précaution clinique (l'exclusion du module ne
    // s'applique pas ici, cf. doc de tête).
    let tomorrow_lab_work_order = sqlx::query(
        "SELECT lwo.id, lwo.status, a.starts_at \
         FROM lab_work_order lwo \
         JOIN appointment a ON a.id = lwo.appointment_id \
         WHERE lwo.patient_id = $1 AND lwo.cabinet_id = $2 \
           AND a.deleted_at IS NULL \
           AND a.status NOT IN ('cancelled', 'no_show') \
           AND a.starts_at >= date_trunc('day', now()) + interval '1 day' \
           AND a.starts_at <  date_trunc('day', now()) + interval '2 days' \
         ORDER BY a.starts_at ASC",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let received_rank = lab_work_orders::status_rank("received").unwrap_or(usize::MAX);
    for row in &tomorrow_lab_work_order {
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        if lab_work_orders::status_rank(&status).unwrap_or(usize::MAX) >= received_rank {
            continue;
        }
        let order_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let starts_at: chrono::DateTime<chrono::Utc> =
            row.try_get("starts_at").map_err(|_| AppError::Internal)?;
        alerts.push(PatientAlert {
            kind: "prosthesis_not_received".to_string(),
            message: "Prothèse non reçue pour le RDV de pose de demain.".to_string(),
            data: serde_json::json!({
                "lab_work_order_id": order_id,
                "appointment_starts_at": starts_at.to_rfc3339(),
                "status": status,
            }),
        });
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(PatientAlertsResponse { alerts }))
}
