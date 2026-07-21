//! `POST /v1/cabinet/payments/manual` — encaissement manuel au cabinet
//! (espèces, chèque, virement) sans PaymentIntent Stripe/GoCardless (#4070).
//!
//! Quoi : `payment.method` (migration 0055/0043) n'autorisait que
//! `card`/`apple_pay`/`google_pay`/`sepa` — impossible d'enregistrer un
//! règlement reçu physiquement au cabinet, pourtant quotidien en cabinet
//! dentaire. Crée directement un `payment` en `status='paid'`
//! (`provider='manual'`), sans webhook de confirmation puisqu'il n'y a pas
//! de provider de paiement en ligne à confirmer.
//! Quand : secrétariat encaisse un règlement physique (espèces/chèque/
//! virement reçu) associé à un devis existant.
//! Pourquoi un module dédié : `billing_payments.rs` était déjà à 547 lignes
//! (CLAUDE.md, zone acceptable dépassée dès 500).
//! Modes d'échec : `method` hors `cash`/`check`/`bank_transfer` (les canaux
//! carte/SEPA doivent passer par le flux `PaymentIntent` existant, jamais
//! par cette route) ou montant hors bornes → 422 ; patient ou devis
//! inexistant/hors cabinet, ou devis n'appartenant pas au patient → 404.

use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Canaux de règlement manuels acceptés par cette route — jamais les canaux
/// carte/SEPA (`card`/`apple_pay`/`google_pay`/`sepa`), qui doivent passer
/// par `POST /v1/payments/intent` (PCI délégué, doc07 §6.1).
const MANUAL_PAYMENT_METHODS: [&str; 3] = ["cash", "check", "bank_transfer"];

/// Plafond métier réaliste, même borne que `create_cabinet_quote`
/// (`cabinet_quotes::MAX_ITEM_AMOUNT_CENTS`) : évite un débordement de
/// précision `numeric(12,2)` silencieusement avalé en 500.
const MAX_MANUAL_AMOUNT_CENTS: i64 = 100_000_000;

/// Corps de `POST /v1/cabinet/payments/manual`.
#[derive(Deserialize)]
pub struct ManualPaymentBody {
    pub patient_id: Uuid,
    pub quote_id: Uuid,
    pub amount_cents: i64,
    pub method: String,
}

/// Réponse de `POST /v1/cabinet/payments/manual`.
#[derive(Serialize)]
pub struct ManualPaymentResponse {
    pub payment_id: Uuid,
    pub status: &'static str,
}

/// `POST /v1/cabinet/payments/manual` — enregistre un règlement physique.
///
/// - Auth JWT pro `secretary`/`practitioner`/`admin`/`manager` requis.
/// - `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`.
/// - `method` doit être `cash`/`check`/`bank_transfer` → 422 sinon.
/// - `amount_cents` doit être dans `]0, 100_000_000]` → 422 sinon.
/// - `patient_id`/`quote_id` doivent exister dans le cabinet courant et le
///   devis doit appartenir au patient donné → 404 sinon (fail-closed RLS :
///   un patient d'un autre cabinet ne peut jamais être ciblé).
/// - Crée `payment` en `status='paid'`, `provider='manual'`, `kind='full'`
///   (un encaissement manuel solde le montant reçu, pas un acompte partiel
///   suivi automatiquement).
/// - Retourne `201 { payment_id, status: "paid" }`.
pub async fn create_manual_payment(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<ManualPaymentBody>,
) -> Result<(StatusCode, Json<ManualPaymentResponse>), AppError> {
    if !MANUAL_PAYMENT_METHODS.contains(&body.method.as_str()) {
        return Err(AppError::ValidationError);
    }
    if body.amount_cents <= 0 || body.amount_cents > MAX_MANUAL_AMOUNT_CENTS {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

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

    // Le devis doit exister dans ce cabinet ET appartenir au patient donné
    // (pas seulement au même cabinet) : évite d'associer par erreur le
    // règlement au devis d'un autre patient du cabinet.
    let quote_exists = sqlx::query(
        "SELECT 1 FROM quote \
         WHERE id = $1 AND cabinet_id = $2 AND patient_id = $3 AND deleted_at IS NULL",
    )
    .bind(body.quote_id)
    .bind(claims.cabinet_id)
    .bind(body.patient_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if quote_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let payment_row = sqlx::query(
        "INSERT INTO payment \
         (cabinet_id, patient_id, quote_id, amount, currency, kind, provider, status, method) \
         VALUES ($1, $2, $3, $4::numeric / 100, 'EUR', 'full', 'manual', 'paid', $5) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.patient_id)
    .bind(body.quote_id)
    .bind(body.amount_cents)
    .bind(&body.method)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let payment_id: Uuid = payment_row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %claims.sub,
        cabinet_id = %claims.cabinet_id,
        payment_id = %payment_id,
        method = %body.method,
        "manual payment recorded"
    );

    Ok((
        StatusCode::CREATED,
        Json(ManualPaymentResponse {
            payment_id,
            status: "paid",
        }),
    ))
}
