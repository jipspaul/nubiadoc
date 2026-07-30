//! Handler `GET /v1/cabinet/payments/bank-deposit-slip` (#4128) — bordereau
//! de remise en banque des chèques encaissés.
//!
//! Quoi : liste + totalise les paiements `method='check'`, `status='paid'`
//! sur `[from, to]` (bornes inclusives, `payment.created_at`), **non encore
//! inclus dans un bordereau précédent**, et génère un nouveau bordereau
//! (`bank_deposit_slip` + `bank_deposit_slip_payment`) qui les marque comme
//! traités.
//!
//! Quand : appelée par le secrétariat au moment du dépôt physique en
//! agence — chaque appel produit un nouveau bordereau immutable et exclut
//! ces chèques de tout appel ultérieur (`UNIQUE(payment_id)` sur la table de
//! liaison, migration 0209).
//!
//! Pourquoi cette approche : la route est un `GET` (imposée par l'issue),
//! mais "Générer un bordereau" est intrinsèquement un effet de bord — le
//! choix assumé ici est que l'appel EST l'événement de génération (mirror
//! du verbe "Générer" du titre de l'issue), pas une prévisualisation sans
//! effet. Un second appel sur la même période ne renvoie donc que les
//! chèques encaissés depuis, jamais les mêmes deux fois.
//!
//! Modes d'échec : `422 validation_error` si `from`/`to` absents ou non
//! parsables (`YYYY-MM-DD`) ou `from > to`. Aucun chèque éligible → bordereau
//! non généré, réponse vide (`data: []`, `total_amount_cents: 0`,
//! `slip_id: null`, `pdf_url: null`) — pas d'erreur, cas normal.

use std::sync::Arc;

use axum::extract::{Extension, Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState, StorageSigner,
};

/// Query de `GET /v1/cabinet/payments/bank-deposit-slip` — bornes de date
/// `YYYY-MM-DD` (inclusives), obligatoires (contrairement aux stats
/// d'activité : un bordereau sans borne n'a pas de sens métier).
#[derive(Deserialize)]
pub struct BankDepositSlipQuery {
    pub from: String,
    pub to: String,
}

/// Un chèque inclus dans le bordereau généré.
#[derive(Serialize)]
pub struct BankDepositSlipItem {
    pub payment_id: Uuid,
    pub patient_name: String,
    pub amount_cents: i64,
    pub created_at: String,
}

/// Réponse de `GET /v1/cabinet/payments/bank-deposit-slip`.
#[derive(Serialize)]
pub struct BankDepositSlipResponse {
    pub slip_id: Option<Uuid>,
    pub data: Vec<BankDepositSlipItem>,
    pub total_amount_cents: i64,
    pub pdf_url: Option<String>,
}

pub async fn get_bank_deposit_slip(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<BankDepositSlipQuery>,
    Extension(signer): Extension<Arc<dyn StorageSigner>>,
) -> Result<Json<BankDepositSlipResponse>, AppError> {
    let from = chrono::NaiveDate::parse_from_str(&params.from, "%Y-%m-%d")
        .map_err(|_| AppError::ValidationError)?;
    let to = chrono::NaiveDate::parse_from_str(&params.to, "%Y-%m-%d")
        .map_err(|_| AppError::ValidationError)?;
    if from > to {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT p.id AS payment_id, \
                trim(concat(pt.first_name, ' ', pt.last_name)) AS patient_name, \
                (p.amount * 100)::bigint AS amount_cents, \
                p.created_at \
         FROM payment p \
         JOIN patient pt ON pt.id = p.patient_id \
         WHERE p.cabinet_id = $1 \
           AND p.method = 'check' AND p.status = 'paid' \
           AND p.created_at::date >= $2 AND p.created_at::date <= $3 \
           AND NOT EXISTS ( \
             SELECT 1 FROM bank_deposit_slip_payment bdsp WHERE bdsp.payment_id = p.id \
           ) \
         ORDER BY p.created_at ASC",
    )
    .bind(claims.cabinet_id)
    .bind(from)
    .bind(to)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    let mut payment_ids = Vec::with_capacity(rows.len());
    let mut total_amount_cents: i64 = 0;
    for row in rows {
        let payment_id: Uuid = row.try_get("payment_id").map_err(|_| AppError::Internal)?;
        let amount_cents: i64 = row
            .try_get("amount_cents")
            .map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        total_amount_cents += amount_cents;
        payment_ids.push(payment_id);
        data.push(BankDepositSlipItem {
            payment_id,
            patient_name: row
                .try_get("patient_name")
                .map_err(|_| AppError::Internal)?,
            amount_cents,
            created_at: created_at.to_rfc3339(),
        });
    }

    if payment_ids.is_empty() {
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok(Json(BankDepositSlipResponse {
            slip_id: None,
            data,
            total_amount_cents: 0,
            pdf_url: None,
        }));
    }

    let slip_id: Uuid = sqlx::query(
        "INSERT INTO bank_deposit_slip (cabinet_id, period_from, period_to, total_amount_cents) \
         VALUES ($1, $2, $3, $4) RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(from)
    .bind(to)
    .bind(total_amount_cents)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .try_get("id")
    .map_err(|_| AppError::Internal)?;

    for payment_id in &payment_ids {
        sqlx::query(
            "INSERT INTO bank_deposit_slip_payment (cabinet_id, slip_id, payment_id) \
             VALUES ($1, $2, $3)",
        )
        .bind(claims.cabinet_id)
        .bind(slip_id)
        .bind(payment_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Export PDF mocké : clé de stockage dérivée du bordereau (même
    // convention que `export_implant_passport` — aucun PDF n'est réellement
    // généré côté backend).
    let storage_key = format!("bank-deposit-slip/{slip_id}.pdf");
    let pdf_url = signer.sign(&storage_key);

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        slip_id = %slip_id,
        payments = data.len(),
        total_amount_cents,
        "bank deposit slip generated"
    );

    Ok(Json(BankDepositSlipResponse {
        slip_id: Some(slip_id),
        data,
        total_amount_cents,
        pdf_url,
    }))
}
