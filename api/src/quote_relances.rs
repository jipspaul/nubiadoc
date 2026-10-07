//! Handlers `/v1/cabinet/quotes/:id/relances` (historique, #4126) et
//! `/v1/cabinet/quotes/:id/remind` (relance manuelle, #6970). Fichier dédié
//! plutôt qu'ajouté à `cabinet_quotes.rs` (déjà au plafond absolu CLAUDE.md,
//! 700+ lignes).

use axum::{
    extract::{Extension, Path, State},
    Json,
};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    notify,
    permissions::ProBillingClaims,
    quote_events::record_quote_event,
    AppState, JobDispatcher,
};

/// Délai minimal entre deux relances manuelles du même devis (#8087) — même
/// contrat que le jumeau officine (`pharmacy/quotes.rs::REMINDER_COOLDOWN_SECS`).
const REMINDER_COOLDOWN_SECS: i64 = 60;

/// Une relance enregistrée (`quote_relance`, migration 0207).
#[derive(Serialize)]
pub struct QuoteRelanceItem {
    pub milestone: String,
    pub sent_at: String,
}

/// Réponse de `GET /v1/cabinet/quotes/:id/relances`.
#[derive(Serialize)]
pub struct QuoteRelancesResponse {
    pub data: Vec<QuoteRelanceItem>,
}

/// `GET /v1/cabinet/quotes/:id/relances` — historique de relance J+3/J+7
/// d'un devis (#4126).
///
/// Praticien/secrétaire (`ProSecretaryPlusClaims`) — `cabinet_id` extrait du
/// JWT. Devis inexistant ou hors tenant → `404`. Trié `sent_at ASC`
/// (chronologique : `j3` avant `j7`). Aucune relance encore envoyée →
/// `{ data: [] }`.
pub async fn list_quote_relances(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(quote_id): Path<Uuid>,
) -> Result<Json<QuoteRelancesResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let quote_exists =
        sqlx::query("SELECT 1 FROM quote WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL")
            .bind(quote_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if quote_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let rows = sqlx::query(
        "SELECT milestone, sent_at FROM quote_relance \
         WHERE quote_id = $1 AND cabinet_id = $2 \
         ORDER BY sent_at ASC",
    )
    .bind(quote_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data: Vec<QuoteRelanceItem> = Vec::with_capacity(rows.len());
    for row in rows {
        let milestone: String = row.try_get("milestone").map_err(|_| AppError::Internal)?;
        let sent_at: chrono::DateTime<chrono::Utc> =
            row.try_get("sent_at").map_err(|_| AppError::Internal)?;
        data.push(QuoteRelanceItem {
            milestone,
            sent_at: sent_at.to_rfc3339(),
        });
    }

    Ok(Json(QuoteRelancesResponse { data }))
}

// ── POST /v1/cabinet/quotes/:id/remind ───────────────────────────────────────

/// Réponse de `POST /v1/cabinet/quotes/:id/remind`.
#[derive(Serialize)]
pub struct RemindCabinetQuoteResponse {
    pub id: Uuid,
    pub status: String,
    pub reminded: bool,
}

/// `POST /v1/cabinet/quotes/:id/remind` — relance manuelle d'un devis en
/// attente de signature (#6970). Le bouton secrétariat « Relancer » (facette
/// « À signer ») appelait jusqu'ici `POST .../send`, dont la garde
/// d'idempotence (devis déjà `sent` → `200` sans écriture) neutralisait
/// l'action pour l'ensemble des devis sur lesquels ce bouton s'affiche.
///
/// Contrairement à `send_cabinet_quote`, PAS de branche idempotente : un
/// devis `sent` est justement la cible de cette route, et une relance
/// manuelle est répétable à volonté (migration 0305 — `quote_relance.milestone
/// = 'manual'`, sans la garde `UNIQUE(quote_id, milestone)` réservée aux
/// jalons automatiques j3/j7). Répétable, mais pas sans délai : bornée par
/// [`REMINDER_COOLDOWN_SECS`] (#8087), même contrat que
/// `pharmacy::quotes::remind_pharmacy_quote` — sans lui, 3 appels concurrents
/// (le verrou `FOR UPDATE` ci-dessous sérialise mais ne refuse rien) écrivent
/// 3 lignes `quote_relance` et notifient le patient 3 fois.
///
/// `ProBillingClaims` (même garde que `send_cabinet_quote`, #4081/#5729) :
/// action de facturation, pas une simple lecture (`ProSecretaryPlusClaims`
/// suffit à `list_quote_relances` ci-dessus).
/// - Devis inexistant ou hors tenant → `404`.
/// - Devis pas `sent` (`draft`/`signed`/`paid`/`expired`/`cancelled`) → `409
///   invalid_status` (rien à relancer).
/// - 2e relance manuelle du même devis sous [`REMINDER_COOLDOWN_SECS`] → `429
///   too_many_requests` avec `Retry-After`.
pub async fn remind_cabinet_quote(
    State(state): State<AppState>,
    Extension(dispatcher): Extension<std::sync::Arc<dyn JobDispatcher>>,
    claims: ProBillingClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<RemindCabinetQuoteResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Verrou FOR UPDATE (même pattern que `send_cabinet_quote`) : sérialise
    // avec un envoi concurrent du même devis.
    let row = sqlx::query(
        "SELECT q.status, p.patient_account_id \
         FROM quote q \
         LEFT JOIN patient p ON p.id = q.patient_id \
         WHERE q.id = $1 AND q.cabinet_id = $2 AND q.deleted_at IS NULL \
         FOR UPDATE OF q",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let patient_account_id: Option<Uuid> = row
        .try_get("patient_account_id")
        .map_err(|_| AppError::Internal)?;

    if status != "sent" {
        return Err(AppError::InvalidStatus);
    }

    // Même fenêtre de garde que `remind_pharmacy_quote` (#8087) : sous le
    // verrou `FOR UPDATE` posé ci-dessus, lit la dernière relance avant
    // d'écrire la nouvelle, pour que les appels concurrents se refusent
    // plutôt que de simplement se sérialiser.
    let last_reminded_at: Option<chrono::DateTime<chrono::Utc>> = sqlx::query(
        "SELECT max(sent_at) AS last_sent_at FROM quote_relance \
         WHERE quote_id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .try_get("last_sent_at")
    .map_err(|_| AppError::Internal)?;

    if let Some(last_reminded_at) = last_reminded_at {
        let elapsed_secs = (chrono::Utc::now() - last_reminded_at).num_seconds();
        if elapsed_secs < REMINDER_COOLDOWN_SECS {
            let retry_after = (REMINDER_COOLDOWN_SECS - elapsed_secs).max(1) as u32;
            return Err(AppError::TooManyRequests(retry_after));
        }
    }

    sqlx::query(
        "INSERT INTO quote_relance (cabinet_id, quote_id, milestone) \
         VALUES ($1, $2, 'manual')",
    )
    .bind(claims.cabinet_id)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Journal du devis (#7176) : événement 'reminded', émis par le cabinet
    // (acteur humain, contrairement au jalon automatique du worker).
    record_quote_event(
        &mut tx,
        id,
        claims.cabinet_id,
        "reminded",
        "cabinet",
        Some(claims.sub),
        serde_json::json!({ "milestone": "manual" }),
    )
    .await?;

    // Notifie le patient (même contrat que le jalon automatique
    // `quote_relance_dispatch::maybe_send_milestone`). Patient sans compte
    // app (walk-in) : notification silencieusement absente.
    let mut push_target: Option<(Uuid, Uuid)> = None;
    if let Some(account_id) = patient_account_id {
        push_target = notify::notify_patient_account(
            &mut tx,
            account_id,
            "quote_relance",
            "Un devis vous attend",
            serde_json::json!({ "quote_id": id }),
        )
        .await?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    if let Some((app_user_id, notification_id)) = push_target {
        dispatcher.enqueue_push_notification(app_user_id, notification_id);
    }

    tracing::info!(
        user_id = %claims.sub,
        cabinet_id = %claims.cabinet_id,
        quote_id = %id,
        "cabinet quote reminded manually"
    );

    Ok(Json(RemindCabinetQuoteResponse {
        id,
        status,
        reminded: true,
    }))
}
