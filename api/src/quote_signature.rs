//! `POST /v1/quotes/:id/signature` — démarre une session de signature eIDAS
//! réelle pour un devis (#4064).
//!
//! Extrait de `billing.rs` (CLAUDE.md plafond 700 lignes : `billing.rs` était
//! déjà à 619 lignes) — contrat documenté doc12 §10.
//!
//! Quoi : contrairement à `billing::sign_quote` (`POST /v1/quotes/:id/sign`,
//! stub historique qui passe `sent → signed` **immédiatement**, toujours
//! utilisé par `app_patient` Flutter — #3705), cette route appelle
//! réellement le provider de signature (`QuoteSignatureClient`) pour
//! démarrer une session, et renvoie `202` avec `redirect_url`/`embed_token`.
//! Le devis **reste `sent`** : la transition vers `signed` n'arrive que via
//! le webhook entrant existant (`webhooks::yousign::yousign_webhook`).
//! Quand : `web-console` appelle déjà cette route avec ce contrat exact
//! (`web-console/src/lib/endpoints.ts`, `tests/flows/EP5.flow.spec.ts` /
//! `EX3.flow.spec.ts` attendent `202`+`signature_id`/`redirect_url` —
//! contrat déjà écrit côté frontend, jamais honoré côté API jusqu'ici).
//! Pourquoi : ne PAS toucher `/sign` (légacy, app patient) évite toute
//! régression ; `/signature` diverge maintenant volontairement de `/sign`.
//! Modes d'échec : devis signé → `409 quote_locked` ; devis refused/expired
//! → `409 invalid_status` ; devis draft (masqué par `quote_patient_read`,
//! migration 0134/#3487 — un brouillon cabinet n'est jamais visible du
//! patient) / inexistant / hors patient → `404` ; provider injoignable →
//! `502`.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::{Extension, Json};
use serde::Serialize;
use std::sync::Arc;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState, QuoteSignatureClient,
};

/// Réponse de `POST /v1/quotes/:id/signature`.
#[derive(Serialize)]
pub struct InitiateQuoteSignatureResponse {
    pub signature_id: Uuid,
    pub provider: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub redirect_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub embed_token: Option<String>,
}

/// `POST /v1/quotes/:id/signature` — démarre une session de signature eIDAS.
///
/// Token `kind:"patient"` requis ; token pro → `403`.
/// RLS via `app.patient_account_id` (policy `quote_patient_read`, comme
/// `billing::sign_quote`).
/// - Devis inexistant / hors patient / `draft` → `404` (un brouillon cabinet
///   pas encore envoyé est exclu de `quote_patient_read`, migration
///   0134/#3487 — structurellement indistinguable d'un devis inexistant ici).
/// - Devis `signed` → `409 quote_locked` (déjà immuable, pas de nouvelle
///   session à démarrer).
/// - Devis `refused`/`expired` → `409 invalid_status` (`sent` est l'étape
///   obligatoire, même contrainte que `sign_quote`).
/// - Provider injoignable/refus → `502`.
/// - Sinon : appelle le provider, crée une ligne `signature`, pose
///   `quote.signature_id` (le statut du devis, lui, **ne change pas**) et
///   renvoie `202 { signature_id, provider, redirect_url?, embed_token? }`.
pub async fn initiate_quote_signature(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Extension(client): Extension<Arc<dyn QuoteSignatureClient>>,
    Path(id): Path<Uuid>,
) -> Result<(StatusCode, Json<InitiateQuoteSignatureResponse>), AppError> {
    use sqlx::Row;

    // ── 1. Lecture + vérification de statut (transaction courte, read-only) ──
    let (cabinet_id, current_status) = {
        let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

        sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
            .bind(claims.account_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let row = sqlx::query(
            "SELECT q.cabinet_id, q.status \
             FROM quote q \
             JOIN patient p ON p.id = q.patient_id \
             WHERE q.id = $1 AND q.deleted_at IS NULL \
               AND p.patient_account_id = $2",
        )
        .bind(id)
        .bind(claims.account_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

        let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

        tx.commit().await.map_err(|_| AppError::Internal)?;
        (cabinet_id, status)
    };

    if current_status == "signed" {
        return Err(AppError::QuoteLocked);
    }
    if current_status != "sent" {
        return Err(AppError::InvalidStatus);
    }

    // ── 2. Appel provider — HORS transaction (pas de lock DB tenu pendant
    //    l'I/O réseau). ────────────────────────────────────────────────────
    let session = client.create_session(id).await.map_err(|err| {
        tracing::warn!(quote_id = %id, error = %err, "quote_signature: provider injoignable");
        AppError::UpstreamUnavailable
    })?;

    // ── 3. Persistance : signature + quote.signature_id (statut inchangé) ──
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let sig_row = sqlx::query(
        "INSERT INTO signature (cabinet_id, provider, provider_ref) \
         VALUES ($1, 'yousign', $2) \
         RETURNING id",
    )
    .bind(cabinet_id)
    .bind(&session.external_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let signature_id: Uuid = sig_row.try_get("id").map_err(|_| AppError::Internal)?;

    sqlx::query("UPDATE quote SET signature_id = $1, updated_at = now() WHERE id = $2")
        .bind(signature_id)
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        quote_id = %id,
        signature_id = %signature_id,
        "quote signature session initiated"
    );

    Ok((
        StatusCode::ACCEPTED,
        Json(InitiateQuoteSignatureResponse {
            signature_id,
            provider: "yousign",
            redirect_url: session.redirect_url,
            embed_token: session.embed_token,
        }),
    ))
}
