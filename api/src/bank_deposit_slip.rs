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
//!
//! Relecture (#6816) : le bordereau produit n'est pas un artefact jetable —
//! `GET /v1/cabinet/payments/bank-deposit-slip/:id` ([`get_bank_deposit_slip_by_id`])
//! relit un bordereau déjà généré (items + total + `pdf_url` re-signé) sans
//! aucun effet de bord, pour le cas où l'appel générateur est rejoué (reload,
//! retour arrière, préchargement) : les chèques déjà inclus restent
//! consultables via le `slip_id` renvoyé à la génération plutôt que perdus.
//! Le PDF est désormais réellement rendu et uploadé dans l'Object Storage
//! avant signature (même correctif que `export_implant_passport`, #6461) —
//! auparavant `pdf_url` pointait vers une clé jamais écrite et répondait 404.

use std::sync::Arc;

use axum::extract::{Extension, Path, Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    pdf_text, AppState, ObjectStorage, StorageSigner,
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
    Extension(object_storage): Extension<Arc<dyn ObjectStorage>>,
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

    let cabinet_name: String = sqlx::query("SELECT raison_sociale FROM cabinet WHERE id = $1")
        .bind(claims.cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // PDF réellement rendu puis uploadé dans l'Object Storage avant signature
    // (#6816, même correctif que `export_implant_passport`/#6461) — la clé
    // de stockage dérivée du bordereau référence désormais un objet
    // effectivement écrit, plus une clé fantôme répondant 404.
    let storage_key = format!("bank-deposit-slip/{slip_id}.pdf");
    let pdf_bytes =
        render_bank_deposit_slip_pdf(&cabinet_name, from, to, &data, total_amount_cents);
    object_storage
        .upload(&storage_key, "application/pdf", pdf_bytes)
        .await
        .map_err(|_| AppError::Internal)?;
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

/// `GET /v1/cabinet/payments/bank-deposit-slip/:id` — relit un bordereau déjà
/// généré (#6816), sans aucun effet de bord (ni `INSERT`, ni consommation de
/// chèque) : purement une lecture à partir de `bank_deposit_slip` +
/// `bank_deposit_slip_payment`, re-signe juste une URL fraîche pour le PDF
/// déjà uploadé lors de la génération. `404` si le bordereau n'existe pas ou
/// appartient à un autre cabinet (RLS `bank_deposit_slip_tenant_isolation`,
/// migration 0209).
pub async fn get_bank_deposit_slip_by_id(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(slip_id): Path<Uuid>,
    Extension(signer): Extension<Arc<dyn StorageSigner>>,
) -> Result<Json<BankDepositSlipResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let total_amount_cents: i64 =
        sqlx::query("SELECT total_amount_cents FROM bank_deposit_slip WHERE id = $1")
            .bind(slip_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?
            .try_get("total_amount_cents")
            .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT p.id AS payment_id, \
                trim(concat(pt.first_name, ' ', pt.last_name)) AS patient_name, \
                (p.amount * 100)::bigint AS amount_cents, \
                p.created_at \
         FROM bank_deposit_slip_payment bdsp \
         JOIN payment p ON p.id = bdsp.payment_id \
         JOIN patient pt ON pt.id = p.patient_id \
         WHERE bdsp.slip_id = $1 \
         ORDER BY p.created_at ASC",
    )
    .bind(slip_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in rows {
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        data.push(BankDepositSlipItem {
            payment_id: row.try_get("payment_id").map_err(|_| AppError::Internal)?,
            patient_name: row
                .try_get("patient_name")
                .map_err(|_| AppError::Internal)?,
            amount_cents: row
                .try_get("amount_cents")
                .map_err(|_| AppError::Internal)?,
            created_at: created_at.to_rfc3339(),
        });
    }

    let storage_key = format!("bank-deposit-slip/{slip_id}.pdf");
    let pdf_url = signer.sign(&storage_key);

    Ok(Json(BankDepositSlipResponse {
        slip_id: Some(slip_id),
        data,
        total_amount_cents,
        pdf_url,
    }))
}

/// Génère le contenu binaire (PDF minimal valide) du bordereau de remise en
/// banque — même approche que les autres exports du cabinet (pas de
/// dépendance externe, cf. `pdf_text`).
fn render_bank_deposit_slip_pdf(
    cabinet_name: &str,
    period_from: chrono::NaiveDate,
    period_to: chrono::NaiveDate,
    items: &[BankDepositSlipItem],
    total_amount_cents: i64,
) -> Vec<u8> {
    let header = vec![
        cabinet_name.to_string(),
        "Bordereau de remise en banque".to_string(),
        format!(
            "Periode : {} au {}",
            period_from.format("%d/%m/%Y"),
            period_to.format("%d/%m/%Y")
        ),
    ];
    let mut body: Vec<String> = Vec::with_capacity(items.len() + 2);
    for item in items {
        body.push(format!(
            "{} - {:.2} EUR - {}",
            item.patient_name,
            item.amount_cents as f64 / 100.0,
            item.created_at
        ));
    }
    body.push(String::new());
    body.push(format!(
        "Total : {:.2} EUR",
        total_amount_cents as f64 / 100.0
    ));
    pdf_text::build_text_pdf(&header, &body, &[])
}
