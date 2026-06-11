//! Handler pour POST /v1/webhooks/gocardless.
//!
//! Vérifie la signature HMAC-SHA256 base64 (header `Webhook-Signature`),
//! puis pour l'événement `payments.confirmed` met à jour `payment.status = 'paid'`
//! WHERE `id = <payment_id>` AND `status = 'pending'` (idempotent).
//!
//! Tout autre type d'événement → 200 silencieux.
//! Route publique (GoCardless appelle directement, pas de JWT).

use axum::{body::Bytes, extract::State, http::HeaderMap, Extension, Json};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use hmac::{Hmac, Mac};
use serde::Serialize;
use serde_json::Value;
use sha2::Sha256;
use uuid::Uuid;

use crate::{auth::AppError, AppState};

type HmacSha256 = Hmac<Sha256>;

/// Secret GoCardless injecté via `Extension<GocardlessWebhookSecret>`.
#[derive(Clone)]
pub struct GocardlessWebhookSecret(pub String);

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

/// Vérifie la signature GoCardless HMAC-SHA256 base64.
///
/// Format du header `Webhook-Signature` : base64(HMAC-SHA256(secret, raw_body)).
/// Retourne `Err(Unauthorized)` si la signature est absente ou invalide.
fn verify_gocardless_signature(
    secret: &str,
    body: &[u8],
    sig_header: &str,
) -> Result<(), AppError> {
    let mut mac =
        HmacSha256::new_from_slice(secret.as_bytes()).map_err(|_| AppError::Unauthorized)?;
    mac.update(body);
    let expected_bytes = mac.finalize().into_bytes();
    let expected_b64 = BASE64.encode(expected_bytes);

    if constant_time_eq(sig_header.trim().as_bytes(), expected_b64.as_bytes()) {
        Ok(())
    } else {
        Err(AppError::Unauthorized)
    }
}

/// Corps de la réponse `POST /v1/webhooks/gocardless`.
#[derive(Serialize)]
pub struct WebhookAck {
    pub status: &'static str,
}

/// `POST /v1/webhooks/gocardless` — point d'entrée GoCardless webhook.
///
/// 1. Vérifie la signature HMAC-SHA256 base64 (header `Webhook-Signature`) → 401 si invalide/absent.
/// 2. Pour `payments.confirmed` : met à jour `payment.status = 'paid'`
///    WHERE `id = <payment_id>` AND `status IN ('pending','processing')` (idempotent).
///    Le `payment_id` est lu depuis `payload.links.payment` (ID GoCardless).
/// 3. Tout autre type d'événement → 200 silencieux.
///
/// Pas de JWT — route publique (GoCardless appelle directement).
/// Le `cabinet_id` est récupéré depuis la ligne `payment` pour satisfaire la policy RLS.
pub async fn gocardless_webhook(
    State(state): State<AppState>,
    Extension(GocardlessWebhookSecret(secret)): Extension<GocardlessWebhookSecret>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Json<WebhookAck>, AppError> {
    // ── 1. Vérification signature ─────────────────────────────────────────────
    let sig_header = headers
        .get("webhook-signature")
        .and_then(|v| v.to_str().ok())
        .ok_or(AppError::Unauthorized)?;

    verify_gocardless_signature(&secret, &body, sig_header)?;

    // ── 2. Désérialise le payload ─────────────────────────────────────────────
    let payload: Value = serde_json::from_slice(&body).map_err(|_| AppError::ValidationError)?;

    let event_type = payload["event"]["action"]
        .as_str()
        .ok_or(AppError::ValidationError)?;

    // ── 3. No-op si événement non géré ────────────────────────────────────────
    if event_type != "payments.confirmed" {
        tracing::debug!(event_type = %event_type, "gocardless webhook event type ignored");
        return Ok(Json(WebhookAck { status: "ok" }));
    }

    // ── 4. Extrait l'ID GoCardless du paiement ────────────────────────────────
    let gc_payment_id = payload["event"]["links"]["payment"]
        .as_str()
        .ok_or(AppError::ValidationError)?;

    // ── 5. Résout cabinet_id + met à jour payment ─────────────────────────────
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Lecture cabinet_id depuis payment (sans RLS — on pose nil le temps de lire).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, cabinet_id FROM payment \
         WHERE provider = 'gocardless' AND provider_ref = $1 \
         LIMIT 1",
    )
    .bind(gc_payment_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        tracing::warn!(gc_payment_id = %gc_payment_id, "gocardless webhook: no matching payment found");
        tx.rollback().await.ok();
        return Ok(Json(WebhookAck { status: "ok" }));
    };

    let payment_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;

    // Pose le vrai cabinet_id pour que la policy tenant_isolation passe sur l'UPDATE.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE payment \
         SET status = 'paid' \
         WHERE id = $1 AND cabinet_id = $2 AND status = 'pending'",
    )
    .bind(payment_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        payment_id = %payment_id,
        cabinet_id = %cabinet_id,
        gc_payment_id = %gc_payment_id,
        "gocardless payments.confirmed processed"
    );

    Ok(Json(WebhookAck { status: "ok" }))
}

use sqlx::Row;

#[cfg(test)]
mod tests {
    use super::*;

    fn make_gocardless_sig(secret: &str, body: &[u8]) -> String {
        let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
        mac.update(body);
        BASE64.encode(mac.finalize().into_bytes())
    }

    #[test]
    fn gocardless_signature_roundtrip() {
        let secret = "gc_test_secret";
        let body = b"{\"event\":{\"action\":\"payments.confirmed\",\"links\":{\"payment\":\"PM123\"}}}";
        let header = make_gocardless_sig(secret, body);
        assert!(verify_gocardless_signature(secret, body, &header).is_ok());
    }

    #[test]
    fn gocardless_signature_invalid_returns_err() {
        let secret = "gc_test_secret";
        let body = b"{\"event\":{\"action\":\"payments.confirmed\"}}";
        assert!(verify_gocardless_signature(secret, body, "badsig").is_err());
    }
}
