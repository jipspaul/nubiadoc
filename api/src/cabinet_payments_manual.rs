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
//! inexistant/hors cabinet, ou devis n'appartenant pas au patient → 404 ;
//! devis pas `signed` → 409 (#4311) ; montant > reste dû → 422 (#4311) ;
//! `Idempotency-Key` absent → 422, clé rejouée avec une empreinte différente
//! → 409 (#4311, parité avec `billing_payments::create_payment_intent`).

use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    reviews::is_unique_violation,
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
/// - Header `Idempotency-Key` obligatoire → `422` si absent. Rejeu avec la
///   même clé et la même requête → `201` avec le même `payment_id` (aucune
///   nouvelle ligne) ; rejeu avec une empreinte différente → `409`.
/// - `method` doit être `cash`/`check`/`bank_transfer` → `422` sinon.
/// - `amount_cents` doit être dans `]0, 100_000_000]` → `422` sinon.
/// - `patient_id`/`quote_id` doivent exister dans le cabinet courant et le
///   devis doit appartenir au patient donné → `404` sinon (fail-closed RLS :
///   un patient d'un autre cabinet ne peut jamais être ciblé).
/// - Le devis doit être `signed` → `409 invalid_status` sinon (#4311, parité
///   avec le chemin Stripe qui exige la même chose avant tout PaymentIntent —
///   un règlement physique reçu avant signature n'a pas de contrepartie
///   contractuelle à solder).
/// - `amount_cents` ne peut pas dépasser le reste dû (reste-à-charge patient
///   du devis, c.-à-d. total des lignes moins part AMO/AMC, moins les
///   paiements `pending`/`paid` déjà enregistrés, sous verrou `FOR UPDATE`
///   pour sérialiser deux encaissements concurrents) → `422` sinon (#4311,
///   #4573, même garde anti-sur-encaissement que le chemin Stripe).
/// - Crée `payment` en `status='paid'`, `provider='manual'`, `kind='full'`
///   (un encaissement manuel solde le montant reçu, pas un acompte partiel
///   suivi automatiquement).
/// - Retourne `201 { payment_id, status: "paid" }`.
pub async fn create_manual_payment(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    headers: HeaderMap,
    Json(body): Json<ManualPaymentBody>,
) -> Result<(StatusCode, Json<ManualPaymentResponse>), AppError> {
    let idempotency_key = headers
        .get("idempotency-key")
        .and_then(|v| v.to_str().ok())
        .filter(|s| !s.is_empty())
        .ok_or(AppError::ValidationError)?
        .to_owned();

    if !MANUAL_PAYMENT_METHODS.contains(&body.method.as_str()) {
        return Err(AppError::ValidationError);
    }
    if body.amount_cents <= 0 || body.amount_cents > MAX_MANUAL_AMOUNT_CENTS {
        return Err(AppError::ValidationError);
    }

    // Empreinte de la requête : une même clé rejouée avec un patient/devis/
    // montant/méthode différent ne doit jamais renvoyer le paiement d'une
    // autre requête (même garde que billing_payments::create_payment_intent, #3547).
    let fingerprint = format!(
        "cabinet={}|patient={}|quote={}|amount={}|method={}",
        claims.cabinet_id, body.patient_id, body.quote_id, body.amount_cents, body.method
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Idempotence : check idempotency_keys avant tout travail tenant-scoped (TTL 24h).
    let cached = sqlx::query(
        "SELECT response, fingerprint FROM idempotency_keys \
         WHERE key = $1 AND created_at > now() - interval '24 hours'",
    )
    .bind(&idempotency_key)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(cached_row) = cached {
        let cached_fingerprint: String = cached_row
            .try_get("fingerprint")
            .map_err(|_| AppError::Internal)?;
        if cached_fingerprint != fingerprint {
            tx.commit().await.map_err(|_| AppError::Internal)?;
            tracing::warn!(
                cabinet_id = %claims.cabinet_id,
                "idempotency key replayed with a different fingerprint"
            );
            return Err(AppError::IdempotencyKeyConflict);
        }
        let resp: serde_json::Value = cached_row
            .try_get("response")
            .map_err(|_| AppError::Internal)?;
        let payment_id: Uuid = resp["payment_id"]
            .as_str()
            .and_then(|s| Uuid::parse_str(s).ok())
            .ok_or(AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        tracing::info!(
            cabinet_id = %claims.cabinet_id,
            payment_id = %payment_id,
            "manual payment idempotent replay"
        );
        return Ok((
            StatusCode::CREATED,
            Json(ManualPaymentResponse {
                payment_id,
                status: "paid",
            }),
        ));
    }

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

    // Verrouille la ligne quote (garde TOCTOU, même pattern que
    // billing_payments::create_payment_intent) : deux encaissements manuels
    // concurrents sur le même devis se sérialisent ici, si bien que le calcul
    // du reste-dû ci-dessous voit toujours les paiements déjà insérés par la
    // transaction gagnante. Le devis doit exister dans ce cabinet ET
    // appartenir au patient donné (pas seulement au même cabinet) : évite
    // d'associer par erreur le règlement au devis d'un autre patient du cabinet.
    let quote_row = sqlx::query(
        "SELECT status \
         FROM quote \
         WHERE id = $1 AND cabinet_id = $2 AND patient_id = $3 AND deleted_at IS NULL \
         FOR UPDATE",
    )
    .bind(body.quote_id)
    .bind(claims.cabinet_id)
    .bind(body.patient_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let status: String = quote_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;

    // #4311 : parité avec le chemin Stripe (billing_payments.rs:176-178) — un
    // règlement physique reçu avant signature n'a pas de contrepartie
    // contractuelle à solder.
    if status != "signed" {
        return Err(AppError::InvalidStatus);
    }

    // #4573 : reste-à-charge réel du patient (total des lignes - part AMO -
    // part AMC), même sous-requête que billing_payments.rs:223-227 — le
    // tiers-payant ne doit jamais forcer le patient à préfinancer la part
    // remboursée par l'assurance. Un encaissement manuel plafonné sur le total
    // BRUT du devis laissait la secrétaire encaisser la part AMO/AMC.
    let patient_share_row = sqlx::query(
        "SELECT coalesce(sum((qi.qty * qi.unit_amount \
             - coalesce(qi.amo_part, 0) - coalesce(qi.amc_part, 0)) * 100), 0)::bigint \
             AS patient_share_cents \
         FROM quote_item qi WHERE qi.quote_id = $1",
    )
    .bind(body.quote_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let patient_share_cents: i64 = patient_share_row
        .try_get("patient_share_cents")
        .map_err(|_| AppError::Internal)?;

    // #4311 : reste dû = reste-à-charge patient - paiements déjà en cours/
    // aboutis (jamais les `failed`/`refunded`, qui n'engagent aucune somme) —
    // même garde anti-sur-encaissement que billing_payments.rs:239-251.
    let already_committed_row = sqlx::query(
        "SELECT COALESCE(SUM(amount * 100), 0)::bigint AS committed_cents \
         FROM payment \
         WHERE quote_id = $1 AND status IN ('pending', 'paid')",
    )
    .bind(body.quote_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let already_committed_cents: i64 = already_committed_row
        .try_get("committed_cents")
        .map_err(|_| AppError::Internal)?;

    // #5683 : un payment_schedule ne crée aucune ligne `payment` — sans ce
    // second SELECT (symétrique à payment_schedules.rs), la garde ci-dessous
    // ignorait les échéanciers déjà posés et laissait engager le patient 2x
    // son reste-à-charge (échéancier actif + paiement manuel).
    let already_scheduled_row = sqlx::query(
        "SELECT COALESCE(SUM(total_amount * 100), 0)::bigint AS scheduled_cents \
         FROM payment_schedule \
         WHERE quote_id = $1 AND status = 'active'",
    )
    .bind(body.quote_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let already_scheduled_cents: i64 = already_scheduled_row
        .try_get("scheduled_cents")
        .map_err(|_| AppError::Internal)?;

    let remaining_due_cents =
        patient_share_cents - already_committed_cents - already_scheduled_cents;

    if body.amount_cents > remaining_due_cents {
        return Err(AppError::ValidationError);
    }

    let insert_result = sqlx::query(
        "INSERT INTO payment \
         (cabinet_id, patient_id, quote_id, amount, currency, kind, provider, status, \
          idempotency_key, method) \
         VALUES ($1, $2, $3, $4::numeric / 100, 'EUR', 'full', 'manual', 'paid', $5, $6) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.patient_id)
    .bind(body.quote_id)
    .bind(body.amount_cents)
    .bind(&idempotency_key)
    .bind(&body.method)
    .fetch_one(&mut *tx)
    .await;

    // Contrainte UNIQUE payment_idempotency_key_unique (permanente, sans
    // fenêtre de temps — contrairement au cache idempotency_keys, TTL 24h).
    // Même garde que billing_payments.rs:258-276 : refuse en 409 plutôt que
    // de laisser la violation UNIQUE remonter en 500.
    let payment_row = match insert_result {
        Ok(row) => row,
        Err(e) if is_unique_violation(&e) => {
            tracing::warn!(
                cabinet_id = %claims.cabinet_id,
                "idempotency key already bound to a payment outside the 24h cache window"
            );
            return Err(AppError::IdempotencyKeyConflict);
        }
        Err(_) => return Err(AppError::Internal),
    };

    let payment_id: Uuid = payment_row.try_get("id").map_err(|_| AppError::Internal)?;

    // Stocke la réponse + l'empreinte dans idempotency_keys pour les replays < 24h.
    sqlx::query(
        "INSERT INTO idempotency_keys (key, response, fingerprint) VALUES ($1, $2, $3) \
         ON CONFLICT (key) DO NOTHING",
    )
    .bind(&idempotency_key)
    .bind(serde_json::json!({"payment_id": payment_id}))
    .bind(&fingerprint)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

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
