//! Handler pour POST /v1/webhooks/yousign.
//!
//! Vérifie la signature HMAC-SHA256 (header `X-Yousign-Signature`), puis
//! pour l'événement `signature.completed` met à jour le devis correspondant :
//! `signed_at = now(), status = 'signed'` (idempotent via `signed_at IS NULL`).
//!
//! Stratégie : route publique (Yousign appelle directement, pas de JWT).
//! Tout autre type d'événement → 200 silencieux (no-op).

use axum::{body::Bytes, extract::State, http::HeaderMap, Extension, Json};
use hmac::{Hmac, Mac};
use serde::Serialize;
use serde_json::Value;
use sha2::Sha256;
use uuid::Uuid;

use crate::{auth::AppError, AppState, YousignWebhookSecret};

type HmacSha256 = Hmac<Sha256>;

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

/// Vérifie la signature Yousign HMAC-SHA256.
///
/// Format du header : `<hex_sig>` (SHA256 HMAC du body brut).
/// Retourne `Err(Unauthorized)` si la signature est absente ou invalide.
fn verify_yousign_signature(secret: &str, body: &[u8], sig_header: &str) -> Result<(), AppError> {
    let mut mac =
        HmacSha256::new_from_slice(secret.as_bytes()).map_err(|_| AppError::Unauthorized)?;
    mac.update(body);
    let expected = mac.finalize().into_bytes();
    let expected_hex = hex::encode(expected);

    if constant_time_eq(sig_header.trim().as_bytes(), expected_hex.as_bytes()) {
        Ok(())
    } else {
        Err(AppError::Unauthorized)
    }
}

/// Corps de la réponse `POST /v1/webhooks/yousign`.
#[derive(Serialize)]
pub struct WebhookAck {
    pub status: &'static str,
}

/// `POST /v1/webhooks/yousign` — point d'entrée Yousign webhook.
///
/// 1. Vérifie la signature HMAC-SHA256 (header `X-Yousign-Signature`) → 401 si invalide/absent.
/// 2. Pour `signature.completed` : met à jour `quote.signed_at = now(), status = 'signed'`
///    WHERE `quote.id = <quote_id>` et `signed_at IS NULL` (idempotent).
///    Le `quote_id` est lu depuis `payload.data.quote_id` (champ personnalisé Yousign sandbox).
/// 3. Tout autre type d'événement → 200 silencieux.
///
/// Pas de JWT — route publique (Yousign appelle directement).
/// Le `cabinet_id` est récupéré depuis la ligne `quote` pour satisfaire la policy RLS.
pub async fn yousign_webhook(
    State(state): State<AppState>,
    Extension(YousignWebhookSecret(secret)): Extension<YousignWebhookSecret>,
    headers: HeaderMap,
    body: Bytes,
) -> Result<Json<WebhookAck>, AppError> {
    // ── 1. Vérification signature ─────────────────────────────────────────────
    let sig_header = headers
        .get("x-yousign-signature")
        .and_then(|v| v.to_str().ok())
        .ok_or(AppError::Unauthorized)?;

    verify_yousign_signature(&secret, &body, sig_header)?;

    // ── 2. Désérialise le payload ─────────────────────────────────────────────
    let payload: Value = serde_json::from_slice(&body).map_err(|_| AppError::ValidationError)?;

    let event_type = payload["event_type"]
        .as_str()
        .ok_or(AppError::ValidationError)?;

    // ── 3. No-op si événement non géré ────────────────────────────────────────
    if event_type != "signature.completed" {
        tracing::debug!(event_type = %event_type, "yousign webhook event type ignored");
        return Ok(Json(WebhookAck { status: "ok" }));
    }

    // ── 4. Extrait le quote_id depuis payload.data.quote_id ──────────────────
    let quote_id_str = payload["data"]["quote_id"]
        .as_str()
        .ok_or(AppError::ValidationError)?;
    let quote_id = Uuid::parse_str(quote_id_str).map_err(|_| AppError::ValidationError)?;

    // ── 5. Résout cabinet_id + met à jour le devis ────────────────────────────
    // webhook_event_log est hors scope ici (pas d'idempotency table pour Yousign).
    // L'UPDATE `WHERE signed_at IS NULL` garantit l'idempotence nativement.
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Lecture cabinet_id depuis quote (sans RLS — on pose nil le temps de lire).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query("SELECT cabinet_id FROM quote WHERE id = $1 AND deleted_at IS NULL")
        .bind(quote_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        tracing::warn!(quote_id = %quote_id, "yousign webhook: quote not found");
        tx.rollback().await.ok();
        return Ok(Json(WebhookAck { status: "ok" }));
    };

    let cabinet_id: Uuid = row.try_get("cabinet_id").map_err(|_| AppError::Internal)?;

    // Pose le vrai cabinet_id pour que la policy tenant_isolation passe sur l'UPDATE.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE quote \
         SET signed_at = now(), status = 'signed', updated_at = now() \
         WHERE id = $1 AND cabinet_id = $2 AND signed_at IS NULL",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        quote_id = %quote_id,
        cabinet_id = %cabinet_id,
        "yousign signature.completed processed"
    );

    Ok(Json(WebhookAck { status: "ok" }))
}

// ── Import pour l'Extension extractor ────────────────────────────────────────

use sqlx::Row;

// ── Tests unitaires (vérification HMAC) ──────────────────────────────────────

/// Génère un header `X-Yousign-Signature` valide pour les tests.
#[cfg(test)]
pub(crate) fn make_yousign_sig(secret: &str, body: &[u8]) -> String {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes()).unwrap();
    mac.update(body);
    hex::encode(mac.finalize().into_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn yousign_signature_roundtrip() {
        let secret = "yousign_test_secret";
        let body = b"{\"event_type\":\"signature.completed\",\"data\":{\"quote_id\":\"00000000-0000-0000-0000-000000000001\"}}";
        let header = make_yousign_sig(secret, body);
        assert!(verify_yousign_signature(secret, body, &header).is_ok());
    }

    #[test]
    fn yousign_signature_invalid_returns_err() {
        let secret = "yousign_test_secret";
        let body = b"{\"event_type\":\"signature.completed\"}";
        assert!(verify_yousign_signature(secret, body, "deadbeef").is_err());
    }
}
