//! `POST /v1/cabinet/cash-register/closing` — clôture de caisse journalière
//! (#4071).
//!
//! Quoi : agrège les paiements `status='paid'` du jour par méthode
//! (`payment.method`) et fige le résultat dans `cash_register_closing`
//! (migration 0165, RLS tenant + `UNIQUE (cabinet_id, closing_date)`).
//! Quand : fin de journée, secrétariat clôture la caisse pour produire le
//! total encaissé par mode de paiement (espèces/chèque/virement/carte/SEPA).
//! Pourquoi un module dédié : nouvelle table/route, pas de fichier existant
//! pertinent à étendre (cohérent avec le découpage établi cette session,
//! ex. `cabinet_payments_manual.rs`).
//! Modes d'échec : clôture déjà existante pour ce cabinet+jour → `409
//! cash_register_already_closed` (pré-vérifiée explicitement plutôt que de
//! laisser remonter la contrainte UNIQUE en 500).

use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Corps de `POST /v1/cabinet/cash-register/closing`. `closing_date`
/// optionnel (`"YYYY-MM-DD"`, défaut : aujourd'hui UTC) — `chrono::NaiveDate`
/// n'implémente `Deserialize`/`Serialize` qu'avec la feature `serde` de
/// `chrono` (non activée ici, cf. `date_filter` dans `marketplace.rs`) : on
/// passe par `String` et on parse manuellement.
#[derive(Deserialize)]
pub struct CloseCashRegisterBody {
    pub closing_date: Option<String>,
}

/// Réponse de `POST /v1/cabinet/cash-register/closing`.
#[derive(Serialize)]
pub struct CloseCashRegisterResponse {
    pub id: Uuid,
    pub closing_date: String,
    pub totals_by_method: serde_json::Value,
    pub total_amount_cents: i64,
}

/// `POST /v1/cabinet/cash-register/closing` — clôture la caisse d'un jour.
///
/// - Auth JWT pro `secretary`/`practitioner`/`admin`/`manager` requis.
/// - `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`.
/// - `closing_date` optionnel, défaut aujourd'hui (UTC). Ne peut pas être
///   dans le futur (`> aujourd'hui`) → `422` sinon (#4313) : une clôture de
///   caisse est par nature « la caisse du jour », une date future est un
///   enregistrement comptable incohérent.
/// - Clôture déjà existante pour ce cabinet+jour → `409
///   cash_register_already_closed` (pas de double clôture — une correction
///   explicite reste hors scope #4071).
/// - Agrège `payment` (`status='paid'`, `created_at::date = closing_date`)
///   par `method` (`coalesce(method, 'unknown')` pour les lignes historiques
///   sans méthode renseignée) et fige le résultat.
/// - Retourne `201 { id, closing_date, totals_by_method, total_amount_cents }`.
pub async fn close_cash_register(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CloseCashRegisterBody>,
) -> Result<(StatusCode, Json<CloseCashRegisterResponse>), AppError> {
    let closing_date: NaiveDate = match body.closing_date {
        Some(ref s) => {
            NaiveDate::parse_from_str(s, "%Y-%m-%d").map_err(|_| AppError::ValidationError)?
        }
        None => chrono::Utc::now().date_naive(),
    };

    // #4313 : une clôture de caisse est « la caisse du jour » — aucune borne
    // haute ne bloquait une date future (ex. 2099-12-31), enregistrement
    // comptable incohérent.
    if closing_date > chrono::Utc::now().date_naive() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let already_closed = sqlx::query(
        "SELECT 1 FROM cash_register_closing WHERE cabinet_id = $1 AND closing_date = $2",
    )
    .bind(claims.cabinet_id)
    .bind(closing_date)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if already_closed.is_some() {
        return Err(AppError::CashRegisterAlreadyClosed);
    }

    let rows = sqlx::query(
        "SELECT coalesce(method, 'unknown') AS method, \
                sum(amount * 100)::bigint AS cents \
         FROM payment \
         WHERE cabinet_id = $1 AND status = 'paid' AND created_at::date = $2 \
         GROUP BY coalesce(method, 'unknown')",
    )
    .bind(claims.cabinet_id)
    .bind(closing_date)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut totals_by_method = serde_json::Map::new();
    let mut total_amount_cents: i64 = 0;
    for row in &rows {
        let method: String = row.try_get("method").map_err(|_| AppError::Internal)?;
        let cents: i64 = row.try_get("cents").map_err(|_| AppError::Internal)?;
        total_amount_cents += cents;
        totals_by_method.insert(method, serde_json::json!(cents));
    }
    let totals_by_method = serde_json::Value::Object(totals_by_method);

    let closing_row = sqlx::query(
        "INSERT INTO cash_register_closing \
         (cabinet_id, closing_date, totals_by_method, total_amount, closed_by) \
         VALUES ($1, $2, $3, $4::numeric / 100, $5) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(closing_date)
    .bind(&totals_by_method)
    .bind(total_amount_cents)
    .bind(claims.sub)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let id: Uuid = closing_row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %claims.sub,
        cabinet_id = %claims.cabinet_id,
        closing_id = %id,
        %closing_date,
        total_amount_cents,
        "cash register closed"
    );

    Ok((
        StatusCode::CREATED,
        Json(CloseCashRegisterResponse {
            id,
            closing_date: closing_date.to_string(),
            totals_by_method,
            total_amount_cents,
        }),
    ))
}
