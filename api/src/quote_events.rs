//! Handler `GET /v1/quotes/:id/events` (#7176, DP-F15.b) — journal
//! patient-lisible d'un devis (envoyé, consulté, relancé, signé). Table
//! `quote_event` (migration 0287, #7177), RLS `quote_event_patient_read`.
//!
//! Aussi : `record_quote_event`, helper d'écriture partagé par les points
//! d'émission : `cabinet_quotes::send_cabinet_quote` (`sent`),
//! `billing::get_quote` (`viewed`), `quote_relance_dispatch::maybe_send_milestone`
//! (`reminded`), `billing::sign_quote` et `webhooks::yousign::yousign_webhook`
//! (`signed`). Kind `refused` (CHECK, migration 0287) n'a volontairement
//! aucun point d'émission ici : aucune route de l'API ne fait aujourd'hui
//! transiter un devis vers `status = 'refused'` (valeur présente dans le
//! CHECK `quote.status`, migration 0006, mais jamais écrite par le backend
//! actuel) — rien à journaliser tant que cette mutation n'existe pas.

use axum::extract::{Path, State};
use axum::Json;
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, ProSecretaryPlusClaims},
    AppState,
};

/// Insère un `quote_event`. Doit être appelé depuis une transaction ayant
/// déjà posé `app.current_cabinet_id` (policy `tenant_isolation` sur
/// `quote_event`, migration 0287) — jamais de connexion nue.
pub(crate) async fn record_quote_event(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    quote_id: Uuid,
    cabinet_id: Uuid,
    kind: &str,
    actor_kind: &str,
    actor_id: Option<Uuid>,
    meta: serde_json::Value,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO quote_event (quote_id, cabinet_id, kind, actor_kind, actor_id, meta) \
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(kind)
    .bind(actor_kind)
    .bind(actor_id)
    .bind(meta)
    .execute(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    Ok(())
}

/// Un événement de la timeline, tel qu'exposé au patient.
#[derive(Serialize)]
pub struct QuoteEventItem {
    pub kind: String,
    pub at: String,
    pub actor_kind: String,
}

/// Réponse de `GET /v1/quotes/:id/events`.
#[derive(Serialize)]
pub struct QuoteEventsResponse {
    pub data: Vec<QuoteEventItem>,
}

/// `GET /v1/quotes/:id/events` — timeline patient-lisible d'un devis.
///
/// Token `kind:"patient"` requis ; token pro → `403`. RLS via
/// `app.patient_account_id` (policy `quote_event_patient_read`, migration
/// 0287) : ne renvoie que les événements d'un devis non-`draft` appartenant
/// au patient (mêmes conditions que `quote_patient_read`, migration 0134) —
/// devis `draft`, hors patient ou inexistant → liste vide, jamais `404` (la
/// RLS ne permet pas de distinguer les trois cas sans fuite d'information,
/// même choix que `quote_attachments::list_patient_quote_attachments`).
/// N'expose ni `actor_id` ni `meta` (identifiants internes/PII potentielle) —
/// seuls `kind`/`at`/`actor_kind` sont utiles à l'affichage. Tri `at ASC`.
pub async fn list_patient_quote_events(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<QuoteEventsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT kind, at, actor_kind FROM quote_event WHERE quote_id = $1 ORDER BY at ASC",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in &rows {
        let kind: String = row.try_get("kind").map_err(|_| AppError::Internal)?;
        let at: chrono::DateTime<chrono::Utc> =
            row.try_get("at").map_err(|_| AppError::Internal)?;
        let actor_kind: String = row.try_get("actor_kind").map_err(|_| AppError::Internal)?;
        data.push(QuoteEventItem {
            kind,
            at: at.to_rfc3339(),
            actor_kind,
        });
    }

    Ok(Json(QuoteEventsResponse { data }))
}

/// `GET /v1/cabinet/quotes/:id/events` — timeline d'un devis côté cabinet
/// (#7467) : `list_patient_quote_events` n'était lisible que par le patient
/// (`PatientAccountClaims`), laissant secrétariat/praticien sans accès au
/// journal pourtant déjà alimenté par `record_quote_event` — le bloc
/// « Suivi » du volet détail (design-v2) n'a donc jamais pu s'appuyer dessus.
///
/// Praticien/secrétaire (`ProSecretaryPlusClaims`) — `cabinet_id` extrait du
/// JWT, policy `tenant_isolation` (migration 0287), même pattern que
/// `quote_relances::list_quote_relances`. Devis inexistant ou hors tenant →
/// `404`. Contrairement à la variante patient, `draft` n'est pas filtré : le
/// cabinet voit ses propres événements dès la création du devis. Tri `at
/// ASC`.
pub async fn list_cabinet_quote_events(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(quote_id): Path<Uuid>,
) -> Result<Json<QuoteEventsResponse>, AppError> {
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
        "SELECT kind, at, actor_kind FROM quote_event \
         WHERE quote_id = $1 AND cabinet_id = $2 ORDER BY at ASC",
    )
    .bind(quote_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in &rows {
        let kind: String = row.try_get("kind").map_err(|_| AppError::Internal)?;
        let at: chrono::DateTime<chrono::Utc> =
            row.try_get("at").map_err(|_| AppError::Internal)?;
        let actor_kind: String = row.try_get("actor_kind").map_err(|_| AppError::Internal)?;
        data.push(QuoteEventItem {
            kind,
            at: at.to_rfc3339(),
            actor_kind,
        });
    }

    Ok(Json(QuoteEventsResponse { data }))
}
