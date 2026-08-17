//! Handlers `GET /v1/payment-schedules` (patient) et
//! `POST /v1/cabinet/quotes/:id/payment-schedule` (praticien, #4072).
//!
//! `payment_schedule` (migration 0006) existe depuis longtemps
//! (`installments` jsonb multi-jalons) mais n'avait aucune route ni côté
//! lecture ni côté écriture — colonnes mortes. Policy RLS patient
//! (`payment_schedule_patient_read`) ajoutée par la migration 0204,
//! symétrique à `prescription_patient_read`/`implant_passport_patient_read`.

use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Extension, Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, ProPractitionerClaims},
    AlmaClient, AppState,
};

// ── GET /v1/payment-schedules ──────────────────────────────────────────────

/// Un jalon d'échéancier, tel que stocké dans `payment_schedule.installments`
/// (jsonb, aucun schéma imposé par la colonne — shape fixée ici côté API).
#[derive(Deserialize, Serialize, Clone)]
pub struct Installment {
    pub date: String,
    pub amount_cents: i64,
    #[serde(default = "default_installment_status")]
    pub status: String,
}

fn default_installment_status() -> String {
    "pending".to_string()
}

/// Un échéancier de paiement (vue compte patient ou cabinet — DTO partagé).
#[derive(Serialize)]
pub struct PaymentScheduleItem {
    pub id: Uuid,
    pub quote_id: Option<Uuid>,
    pub total_amount_cents: i64,
    pub installments: Vec<Installment>,
    pub provider: Option<String>,
    pub status: String,
    pub created_at: String,
}

/// Réponse de `GET /v1/payment-schedules`.
#[derive(Serialize)]
pub struct PaymentSchedulesResponse {
    pub data: Vec<PaymentScheduleItem>,
}

fn parse_schedule_row(row: &sqlx::postgres::PgRow) -> Result<PaymentScheduleItem, AppError> {
    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let quote_id: Option<Uuid> = row.try_get("quote_id").map_err(|_| AppError::Internal)?;
    let total_amount_cents: i64 = row
        .try_get("total_amount_cents")
        .map_err(|_| AppError::Internal)?;
    let installments_json: serde_json::Value = row
        .try_get("installments")
        .map_err(|_| AppError::Internal)?;
    let mut installments: Vec<Installment> =
        serde_json::from_value(installments_json).unwrap_or_default();
    installments.sort_by(|a, b| a.date.cmp(&b.date));
    let provider: Option<String> = row.try_get("provider").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    Ok(PaymentScheduleItem {
        id,
        quote_id,
        total_amount_cents,
        installments,
        provider,
        status,
        created_at: created_at.to_rfc3339(),
    })
}

/// `GET /v1/payment-schedules` — échéanciers du patient authentifié (#4072).
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id`
/// (`payment_schedule_patient_read`, migration 0204). Triés `created_at DESC`.
/// Aucun échéancier → `{ data: [] }`.
pub async fn list_payment_schedules(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<PaymentSchedulesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, quote_id, (total_amount * 100)::bigint AS total_amount_cents, \
                installments, provider, status, created_at \
         FROM payment_schedule \
         ORDER BY created_at DESC",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .iter()
        .map(parse_schedule_row)
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        account_id = %claims.account_id,
        count = data.len(),
        "payment schedules listed"
    );

    Ok(Json(PaymentSchedulesResponse { data }))
}

// ── POST /v1/cabinet/quotes/:id/payment-schedule ───────────────────────────

/// Un jalon fourni à la création (#4072) — le statut est toujours `pending`
/// à la création, non accepté en entrée (cohérence : un échéancier tout
/// juste créé n'a par construction aucun jalon déjà réglé).
#[derive(Deserialize)]
pub struct InstallmentInput {
    pub date: String,
    pub amount_cents: i64,
}

/// Corps de `POST /v1/cabinet/quotes/:id/payment-schedule`.
#[derive(Deserialize)]
pub struct CreatePaymentScheduleBody {
    pub installments: Vec<InstallmentInput>,
    #[serde(default)]
    pub provider: Option<String>,
}

/// Réponse de `POST /v1/cabinet/quotes/:id/payment-schedule`.
#[derive(Serialize)]
pub struct CreatePaymentScheduleResponse {
    pub schedule_id: Uuid,
}

/// Providers acceptés (#4072/#4163) — `alma` anticipé de longue date par le
/// commentaire de la colonne (migration 0006) mais jamais contraint par un
/// CHECK ; validé ici côté API plutôt qu'en base pour rester extensible sans
/// migration à chaque nouveau partenaire.
const VALID_PROVIDERS: &[&str] = &["stripe", "gocardless", "alma"];

/// `POST /v1/cabinet/quotes/:id/payment-schedule` — crée un échéancier
/// multi-jalons sur un devis (#4072).
///
/// Praticien uniquement (`ProPractitionerClaims`) — `cabinet_id` extrait du
/// JWT, jamais du body/path. Devis inexistant ou hors tenant → `404`.
/// Immutabilité du devis signé (même garde que `billing_payments.rs`) :
/// devis autre que `status = 'signed'` → `409 invalid_status`. `installments`
/// vide, un `amount_cents` ≤ 0, ou `provider` hors `VALID_PROVIDERS` → `422`.
/// `total_amount` = somme des jalons ; peut être inférieur au reste-dû (un
/// échéancier peut ne couvrir qu'une partie, ex. hors acompte déjà réglé)
/// mais jamais le dépasser (#4644) : garde stricte identique à
/// `create_manual_payment` (#4311/#4573), sur le reste-à-charge patient
/// (part AMO/AMC exclue) moins les paiements `pending`/`paid` déjà
/// enregistrés ET les échéanciers `active` déjà posés sur le devis (#5669),
/// sous verrou `FOR UPDATE` sur la ligne `quote` — dépassement
/// → `422 validation_error`. `provider = "alma"` (#4163) déclenche la souscription
/// synchrone auprès d'`AlmaClient` — un refus/timeout provider fait échouer
/// toute la création (`500`), pas d'échéancier fantôme non souscrit.
pub async fn create_payment_schedule(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Extension(alma_client): Extension<Arc<dyn AlmaClient>>,
    Path(quote_id): Path<Uuid>,
    Json(body): Json<CreatePaymentScheduleBody>,
) -> Result<(StatusCode, Json<CreatePaymentScheduleResponse>), AppError> {
    if body.installments.is_empty() {
        return Err(AppError::ValidationError);
    }
    if body.installments.iter().any(|i| i.amount_cents <= 0) {
        return Err(AppError::ValidationError);
    }
    if let Some(provider) = &body.provider {
        if !VALID_PROVIDERS.contains(&provider.as_str()) {
            return Err(AppError::ValidationError);
        }
    }
    for installment in &body.installments {
        crate::text_validation::reject_nul_byte(&installment.date)?;
        installment
            .date
            .parse::<chrono::NaiveDate>()
            .map_err(|_| AppError::ValidationError)?;
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Verrou FOR UPDATE (même pattern que cabinet_payments_manual.rs::create_manual_payment,
    // #4311/#4573) : sérialise avec tout autre encaissement/échéancier concurrent sur le
    // même devis pour que le calcul du reste-dû ci-dessous soit à jour.
    let quote_row = sqlx::query(
        "SELECT patient_id, status FROM quote \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         FOR UPDATE",
    )
    .bind(quote_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let patient_id: Uuid = quote_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = quote_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    if status != "signed" {
        return Err(AppError::InvalidStatus);
    }

    let installments: Vec<Installment> = body
        .installments
        .iter()
        .map(|i| Installment {
            date: i.date.clone(),
            amount_cents: i.amount_cents,
            status: default_installment_status(),
        })
        .collect();
    let total_cents: i64 = installments.iter().map(|i| i.amount_cents).sum();
    let installments_json = serde_json::to_value(&installments).map_err(|_| AppError::Internal)?;

    // #4644 : garde stricte sur le reste-dû réel du devis signé — même calcul que
    // create_manual_payment (#4311/#4573) : reste-à-charge patient (total lignes -
    // part AMO - part AMC) moins les paiements déjà pending/paid. Un échéancier ne
    // peut pas engager le patient sur un montant sans rapport avec le devis signé.
    let patient_share_row = sqlx::query(
        "SELECT coalesce(sum((qi.qty * qi.unit_amount \
             - coalesce(qi.amo_part, 0) - coalesce(qi.amc_part, 0)) * 100), 0)::bigint \
             AS patient_share_cents \
         FROM quote_item qi WHERE qi.quote_id = $1",
    )
    .bind(quote_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let patient_share_cents: i64 = patient_share_row
        .try_get("patient_share_cents")
        .map_err(|_| AppError::Internal)?;

    let already_committed_row = sqlx::query(
        "SELECT COALESCE(SUM(amount * 100), 0)::bigint AS committed_cents \
         FROM payment \
         WHERE quote_id = $1 AND status IN ('pending', 'paid')",
    )
    .bind(quote_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let already_committed_cents: i64 = already_committed_row
        .try_get("committed_cents")
        .map_err(|_| AppError::Internal)?;

    // #5669 : un payment_schedule ne crée aucune ligne `payment` — sans ce
    // second SUM, la garde ci-dessous ignore les échéanciers déjà posés sur
    // le devis et laisse créer N échéanciers cumulant chacun jusqu'au
    // reste-dû complet (sur-engagement patient).
    let already_scheduled_row = sqlx::query(
        "SELECT COALESCE(SUM(total_amount * 100), 0)::bigint AS scheduled_cents \
         FROM payment_schedule \
         WHERE quote_id = $1 AND status = 'active'",
    )
    .bind(quote_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let already_scheduled_cents: i64 = already_scheduled_row
        .try_get("scheduled_cents")
        .map_err(|_| AppError::Internal)?;

    let remaining_due_cents =
        patient_share_cents - already_committed_cents - already_scheduled_cents;

    if total_cents > remaining_due_cents {
        return Err(AppError::ValidationError);
    }

    let schedule_row = sqlx::query(
        "INSERT INTO payment_schedule \
         (cabinet_id, patient_id, quote_id, total_amount, installments, provider) \
         VALUES ($1, $2, $3, $4::numeric / 100, $5, $6) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(quote_id)
    .bind(total_cents)
    .bind(installments_json)
    .bind(&body.provider)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let schedule_id: Uuid = schedule_row.try_get("id").map_err(|_| AppError::Internal)?;

    // #4163 : souscription Alma synchrone — appelée APRÈS l'insert pour
    // disposer de schedule_id (référence envoyée au provider), toujours
    // dans la même transaction (un refus Alma annule la création entière
    // via le rollback implicite au drop de `tx` sur `?`).
    if body.provider.as_deref() == Some("alma") {
        let provider_ref = alma_client
            .subscribe(schedule_id, total_cents)
            .await
            .map_err(|_| AppError::Internal)?;
        sqlx::query("UPDATE payment_schedule SET provider_ref = $1 WHERE id = $2")
            .bind(&provider_ref)
            .bind(schedule_id)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        quote_id = %quote_id,
        schedule_id = %schedule_id,
        installments = installments.len(),
        "payment schedule created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreatePaymentScheduleResponse { schedule_id }),
    ))
}
