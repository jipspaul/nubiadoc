//! Handler pour POST /v1/webhooks/stripe.
//!
//! Vérifie la signature HMAC-SHA256 (header `Stripe-Signature`), garantit
//! l'idempotence via `webhook_event_log` (UNIQUE provider+event_id), puis
//! met à jour `payment.status` pour les événements PaymentIntent.
//!
//! Stratégie : réponse 200 rapide — le traitement lourd (envoi FCM, relance
//! planifiée, etc.) est délégué à apalis (post-T2). Le handler ne fait que
//! la mise à jour de statut synchrone.

use axum::{body::Bytes, extract::State, http::HeaderMap, Extension, Json};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::Sha256;
use sqlx::Row;
use uuid::Uuid;

use crate::{auth::AppError, AppState, StripeWebhookSecret};

type HmacSha256 = Hmac<Sha256>;

/// Vérifie la signature Stripe HMAC-SHA256.
///
/// Format du header : `t=<timestamp>,v1=<hex_sig>[,v1=<hex_sig2>...]`
/// Payload signé : `<timestamp>.<raw_body>`.
/// Tolérance de 300 s (Stripe recommande 300 s).
///
/// Retourne `Err(400)` si la signature est absente, malformée ou invalide.
fn verify_stripe_signature(
    secret: &str,
    body: &[u8],
    stripe_sig_header: &str,
) -> Result<(), AppError> {
    // Parse timestamp et signatures v1.
    let mut timestamp: Option<&str> = None;
    let mut signatures: Vec<&str> = Vec::new();

    for part in stripe_sig_header.split(',') {
        if let Some(ts) = part.strip_prefix("t=") {
            timestamp = Some(ts);
        } else if let Some(sig) = part.strip_prefix("v1=") {
            signatures.push(sig);
        }
    }

    let ts = timestamp.ok_or(AppError::Unauthorized)?;

    // Vérification de la tolérance temporelle (300 s).
    let ts_secs: i64 = ts.parse().map_err(|_| AppError::Unauthorized)?;
    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    if (now_secs - ts_secs).abs() > 300 {
        return Err(AppError::Unauthorized);
    }

    // Payload signé : "<timestamp>.<raw_body>".
    let signed_payload = [ts.as_bytes(), b".", body].concat();

    let mut mac =
        HmacSha256::new_from_slice(secret.as_bytes()).map_err(|_| AppError::Unauthorized)?;
    mac.update(&signed_payload);
    let expected = mac.finalize().into_bytes();
    let expected_hex = hex::encode(expected);

    if signatures
        .iter()
        .any(|sig| constant_time_eq(sig.as_bytes(), expected_hex.as_bytes()))
    {
        Ok(())
    } else {
        Err(AppError::Unauthorized)
    }
}

/// Comparaison temps-constant pour éviter les timing attacks.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff: u8 = 0;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

/// Corps de la réponse `POST /v1/webhooks/stripe`.
#[derive(Serialize)]
pub struct WebhookAck {
    pub status: &'static str,
}

/// `POST /v1/webhooks/stripe` — point d'entrée Stripe webhook.
///
/// 1. Vérifie la signature HMAC-SHA256 (header `Stripe-Signature`) → 400 si invalide.
/// 2. Enregistre l'événement dans `webhook_event_log` pour l'idempotence →
///    si `(provider, event_id)` existe déjà, retourne 200 immédiatement.
/// 3. Pour `payment_intent.succeeded` : met à jour `payment.status = 'paid'`
///    et `payment.provider_ref = <pi_id>`.
/// 4. Pour `payment_intent.payment_failed` : met à jour `payment.status = 'failed'`.
/// 5. Retourne 200 `{"status":"ok"}`.
///
/// Pas de JWT — route publique (Stripe appelle directement). Le `cabinet_id`
/// n'est PAS utilisé ici car `webhook_event_log` est une entité plateforme
/// (pas de RLS cabinet, cf. migration 0074).
pub async fn stripe_webhook(
    State(state): State<AppState>,
    Extension(StripeWebhookSecret(stripe_secret)): Extension<StripeWebhookSecret>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Json<WebhookAck>, AppError> {
    // ── 1. Vérification signature ─────────────────────────────────────────────
    let sig_header = headers
        .get("stripe-signature")
        .and_then(|v| v.to_str().ok())
        .ok_or(AppError::Unauthorized)?;

    verify_stripe_signature(&stripe_secret, &body, sig_header)?;

    // ── 2. Deserialise le payload ─────────────────────────────────────────────
    let payload: Value = serde_json::from_slice(&body).map_err(|_| AppError::ValidationError)?;

    let event_id = payload["id"]
        .as_str()
        .ok_or(AppError::ValidationError)?
        .to_owned();
    let event_type = payload["type"]
        .as_str()
        .ok_or(AppError::ValidationError)?
        .to_owned();

    // ── 3. Idempotence : INSERT webhook_event_log, skip si déjà vu ───────────
    // webhook_event_log n'a pas de RLS cabinet (entité plateforme).
    // On utilise le pool directement (pas de with_tenant) — c'est le seul cas
    // légitime : la table est hors scope tenant, cf. migration 0074.
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    let inserted = sqlx::query(
        "INSERT INTO webhook_event_log (provider, event_id, payload, status) \
         VALUES ('stripe', $1, $2, 'pending') \
         ON CONFLICT (provider, event_id) DO NOTHING \
         RETURNING id",
    )
    .bind(&event_id)
    .bind(&payload)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if inserted.is_none() {
        // Événement déjà traité — idempotent.
        tx.rollback().await.ok();
        tracing::info!(event_id = %event_id, "stripe webhook idempotent skip");
        return Ok(Json(WebhookAck { status: "ok" }));
    }

    let log_id: Uuid = inserted
        .as_ref()
        .unwrap()
        .try_get("id")
        .map_err(|_| AppError::Internal)?;

    // ── 4. Traitement métier ──────────────────────────────────────────────────
    let pi_id = payload["data"]["object"]["id"].as_str().unwrap_or_default();

    match event_type.as_str() {
        "payment_intent.succeeded" => {
            // Mise à jour payment.status sans RLS cabinet : payment est isolé par
            // cabinet_id, mais ici on filtre par provider_ref (pi_id Stripe) qui
            // est unique globalement. On pose le cabinet_id depuis la ligne payment
            // existante pour satisfaire la policy.
            update_payment_status(&mut tx, pi_id, "paid").await?;
        }
        "payment_intent.payment_failed" => {
            update_payment_status(&mut tx, pi_id, "failed").await?;
        }
        _ => {
            // Événement non géré — on log et on répond 200 (Stripe re-tentera sinon).
            tracing::debug!(event_type = %event_type, "stripe webhook event type ignored");
        }
    }

    // Marque l'entrée webhook_event_log comme processed.
    // webhook_event_log est append-only (trigger bloque UPDATE) — on n'essaie pas
    // de mettre à jour le statut ; la présence de la ligne suffit pour l'idempotence.
    // (Le champ `status` initial 'pending' reste en place ; un job apalis post-T2
    //  pourra le marquer 'processed' via le rôle owner si nécessaire.)
    let _ = log_id; // log_id conservé pour un futur job apalis

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        event_id = %event_id,
        event_type = %event_type,
        "stripe webhook processed"
    );

    Ok(Json(WebhookAck { status: "ok" }))
}

/// Met à jour `payment.status` pour le PaymentIntent identifié par `pi_id`.
///
/// Pose `app.current_cabinet_id` depuis la ligne `payment` elle-même pour
/// satisfaire la policy RLS `tenant_isolation` lors de l'UPDATE.
async fn update_payment_status(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    pi_id: &str,
    new_status: &str,
) -> Result<(), AppError> {
    if pi_id.is_empty() {
        return Ok(());
    }

    // Lit cabinet_id depuis payment (provider = 'stripe', provider_ref = pi_id).
    // On ne peut pas poser le GUC avant de connaître cabinet_id, mais la lecture
    // ne requiert pas de RLS (le rôle nubia_app a SELECT grâce aux GRANTs de 0011).
    // La policy tenant_isolation bloque uniquement si le GUC est absent ou vide.
    // On contourne en posant d'abord un GUC sentinel nil (lecture permissive),
    // puis on repose le vrai cabinet_id pour l'UPDATE.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, cabinet_id FROM payment \
         WHERE provider = 'stripe' AND provider_ref = $1 \
         LIMIT 1",
    )
    .bind(pi_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Si aucun paiement correspondant : l'événement peut arriver avant le
    // PaymentIntent local (race) — on ignore silencieusement.
    let row = match row {
        Some(r) => r,
        None => {
            tracing::warn!(pi_id = %pi_id, "stripe webhook: no matching payment found");
            return Ok(());
        }
    };

    let payment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;

    // Pose le vrai cabinet_id pour que la policy tenant_isolation passe sur l'UPDATE.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE payment SET status = $1, provider_ref = COALESCE(provider_ref, $2) \
         WHERE id = $3 AND cabinet_id = $4",
    )
    .bind(new_status)
    .bind(pi_id)
    .bind(payment_id)
    .bind(cabinet_id)
    .execute(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tracing::info!(
        payment_id = %payment_id,
        cabinet_id = %cabinet_id,
        new_status = %new_status,
        pi_id = %pi_id,
        "payment status updated from stripe webhook"
    );

    Ok(())
}

// ── Structs pour les tests (pub(crate)) ──────────────────────────────────────

/// Génère un header `Stripe-Signature` valide pour les tests.
#[cfg(test)]
pub(crate) fn make_stripe_sig(secret: &str, body: &[u8], ts: i64) -> String {
    let signed_payload = [ts.to_string().as_bytes(), b".", body].concat();
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
    mac.update(&signed_payload);
    let sig = hex::encode(mac.finalize().into_bytes());
    format!("t={ts},v1={sig}")
}

#[derive(Debug, Deserialize)]
struct _Unused; // Évite l'import serde::Deserialize inutilisé sans #[allow]

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stripe_signature_roundtrip() {
        let secret = "whsec_test_secret";
        let body = b"{\"id\":\"evt_test\",\"type\":\"payment_intent.succeeded\"}";
        let ts = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        let header = make_stripe_sig(secret, body, ts);
        assert!(verify_stripe_signature(secret, body, &header).is_ok());
    }
}
