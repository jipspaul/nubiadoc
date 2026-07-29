//! `POST /v1/interop/oauth/token` — grant `client_credentials` (RFC 6749 §4.4).
//!
//! Pas de contexte tenant à l'entrée (le client s'authentifie par
//! `client_id`/`client_secret`, pas par JWT) : le lookup passe par les
//! fonctions `SECURITY DEFINER` posées en migration 0148
//! (`interop_client_find_by_client_id`, `interop_client_secret_find_active`),
//! même précédent que `payment_find_by_provider_ref` (`api/src/webhooks/stripe.rs`).

use std::str::FromStr;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::{
    extract::{Form, State},
    Json,
};
use integrations_interop::{parse_scopes, scopes_to_string, verify_secret, Scope};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    interop::{
        auth::{InteropClaims, INTEROP_AUDIENCE},
        error::InteropError,
    },
    AppState,
};

/// Durée de vie d'un token interop — volontairement courte (client_credentials
/// machine-à-machine, pas de refresh token en lot A1 : le client redemande).
const TOKEN_TTL_SECS: u64 = 900;

/// Corps `application/x-www-form-urlencoded` de `POST /v1/interop/oauth/token`.
#[derive(Debug, Deserialize)]
pub struct TokenRequest {
    grant_type: String,
    client_id: String,
    client_secret: String,
    #[serde(default)]
    scope: Option<String>,
}

/// Réponse de succès (RFC 6749 §4.4.3).
#[derive(Serialize)]
pub struct TokenResponse {
    access_token: String,
    token_type: &'static str,
    expires_in: u64,
    scope: String,
}

/// `POST /v1/interop/oauth/token` — échange `client_id`/`client_secret` contre
/// un JWT `aud:"interop"` de courte durée.
///
/// 1. `grant_type` doit valoir `client_credentials` → sinon `unsupported_grant_type`.
/// 2. Lookup du client par `interop_client_find_by_client_id` (SECURITY DEFINER,
///    hors contexte tenant) → absent ou `status != 'active'` → `invalid_client`.
/// 3. Vérifie `client_secret` contre les secrets actifs/non-expirés
///    (`interop_client_secret_find_active`, argon2) → aucun match → `invalid_client`.
/// 4. Les scopes demandés doivent être un sous-ensemble des scopes accordés au
///    client → sinon `invalid_scope` (tentative d'escalade). Scope absent de la
///    requête = tous les scopes accordés.
/// 5. Émet le JWT + audite l'émission dans `audit_log` (`actor_role='interop_client'`,
///    `actor_id=interop_client.id`, aucune PII dans les métadonnées).
pub async fn issue_token(
    State(state): State<AppState>,
    Form(body): Form<TokenRequest>,
) -> Result<Json<TokenResponse>, InteropError> {
    if body.grant_type != "client_credentials" {
        return Err(InteropError::UnsupportedGrantType);
    }
    if body.client_id.trim().is_empty() || body.client_secret.is_empty() {
        return Err(InteropError::InvalidRequest);
    }

    // ── 1. Lookup client (SECURITY DEFINER, hors contexte tenant) ──────────
    // #4392 : pour un client_id totalement absent, la fonction SQL (non-SETOF,
    // cf. docstring plus bas) échoue au niveau requête au lieu de produire la
    // ligne composite NULL attendue — mappé en InvalidClient (401), pas
    // Internal (500) : côté endpoint public d'auth, un échec de ce lookup
    // précis signifie « client non reconnu », jamais une vraie panne serveur
    // à exposer. Remonter un 500 ici casserait aussi la gestion d'erreur
    // normale d'un partenaire qui teste un client_id invalide.
    let client_row = sqlx::query(
        "SELECT id, cabinet_id, scopes, status FROM interop_client_find_by_client_id($1)",
    )
    .bind(&body.client_id)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| InteropError::InvalidClient)?
    .ok_or(InteropError::InvalidClient)?;

    // `interop_client_find_by_client_id` n'est pas SETOF : appelée dans un FROM,
    // elle est censée produire une ligne composite NULL si aucun client ne
    // correspond (Postgres traite une fonction scalaire en FROM comme un set
    // d'une seule instance de son type de retour) — `id IS NULL` == client
    // inconnu. En pratique (#4392), pour un client_id totalement absent la
    // requête échoue au niveau exécution plutôt que de produire cette ligne
    // NULL — géré par le `.map_err` ci-dessus, mais gardé ici aussi (défense
    // en profondeur) pour le cas où la ligne composite-NULL est bien produite.
    let client_row_id: Option<Uuid> = client_row
        .try_get("id")
        .map_err(|_| InteropError::Internal)?;
    let client_row_id = client_row_id.ok_or(InteropError::InvalidClient)?;
    let cabinet_id: Uuid = client_row
        .try_get("cabinet_id")
        .map_err(|_| InteropError::Internal)?;
    let granted_raw: Vec<String> = client_row
        .try_get("scopes")
        .map_err(|_| InteropError::Internal)?;
    let status: String = client_row
        .try_get("status")
        .map_err(|_| InteropError::Internal)?;

    if status != "active" {
        return Err(InteropError::InvalidClient);
    }

    // ── 2. Vérification du secret contre les secrets actifs/non-expirés ────
    let secret_rows = sqlx::query("SELECT secret_hash FROM interop_client_secret_find_active($1)")
        .bind(client_row_id)
        .fetch_all(&state.db)
        .await
        .map_err(|_| InteropError::Internal)?;

    let secret_matches = secret_rows.iter().any(|row| {
        row.try_get::<String, _>("secret_hash")
            .map(|hash| verify_secret(&body.client_secret, &hash))
            .unwrap_or(false)
    });

    if !secret_matches {
        return Err(InteropError::InvalidClient);
    }

    // ── 3. Résolution des scopes (sous-ensemble des scopes accordés) ───────
    let granted: Vec<Scope> = granted_raw
        .iter()
        .filter_map(|s| Scope::from_str(s).ok())
        .collect();

    let requested = resolve_requested_scopes(body.scope.as_deref(), &granted)?;
    let scope_str = scopes_to_string(&requested);

    // ── 4. Émission du JWT ──────────────────────────────────────────────────
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + TOKEN_TTL_SECS;

    let claims = InteropClaims {
        sub: client_row_id,
        aud: INTEROP_AUDIENCE.to_string(),
        client_id: body.client_id.clone(),
        cabinet_id,
        scope: scope_str.clone(),
        exp,
    };

    let access_token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|_| InteropError::Internal)?;

    // ── 5. Audit (with_tenant manuel — même pattern que auth::patch_cabinet) ─
    let mut tx = state.db.begin().await.map_err(|_| InteropError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| InteropError::Internal)?;
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, 'interop_client', 'interop_token_issued', 'interop_client', $2, $3)",
    )
    .bind(cabinet_id)
    .bind(client_row_id)
    .bind(json!({"scope": scope_str}))
    .execute(&mut *tx)
    .await
    .map_err(|_| InteropError::Internal)?;
    tx.commit().await.map_err(|_| InteropError::Internal)?;

    tracing::info!(
        cabinet_id = %cabinet_id,
        client_id = %body.client_id,
        interop_client_id = %client_row_id,
        "interop token issued"
    );

    Ok(Json(TokenResponse {
        access_token,
        token_type: "Bearer",
        expires_in: TOKEN_TTL_SECS,
        scope: scope_str,
    }))
}

/// Résout les scopes à accorder pour ce token : sous-ensemble de `granted`
/// demandé explicitement, ou `granted` en entier si `scope` est absent/vide
/// (comportement OAuth2 usuel). Fail-closed : un scope inconnu, une demande
/// hors périmètre, ou un client sans aucun scope accordé → `invalid_scope`.
fn resolve_requested_scopes(
    requested_raw: Option<&str>,
    granted: &[Scope],
) -> Result<Vec<Scope>, InteropError> {
    let requested: Vec<Scope> = match requested_raw.map(str::trim) {
        Some(raw) if !raw.is_empty() => {
            parse_scopes(raw).map_err(|_| InteropError::InvalidScope)?
        }
        _ => granted.to_vec(),
    };

    if requested.is_empty() || !requested.iter().all(|s| granted.contains(s)) {
        return Err(InteropError::InvalidScope);
    }

    Ok(requested)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolve_requested_scopes_defaults_to_granted_when_absent() {
        let granted = vec![Scope::AppointmentsRead, Scope::DirectoryRead];
        let resolved = resolve_requested_scopes(None, &granted).unwrap();
        assert_eq!(resolved, granted);
    }

    #[test]
    fn resolve_requested_scopes_defaults_to_granted_when_empty_string() {
        let granted = vec![Scope::AppointmentsRead];
        let resolved = resolve_requested_scopes(Some("   "), &granted).unwrap();
        assert_eq!(resolved, granted);
    }

    #[test]
    fn resolve_requested_scopes_accepts_subset() {
        let granted = vec![Scope::AppointmentsRead, Scope::DirectoryRead];
        let resolved = resolve_requested_scopes(Some("appointments:read"), &granted).unwrap();
        assert_eq!(resolved, vec![Scope::AppointmentsRead]);
    }

    #[test]
    fn resolve_requested_scopes_rejects_escalation() {
        let granted = vec![Scope::AppointmentsRead];
        let err = resolve_requested_scopes(Some("appointments:write"), &granted).unwrap_err();
        assert!(matches!(err, InteropError::InvalidScope));
    }

    #[test]
    fn resolve_requested_scopes_rejects_unknown_scope_string() {
        let granted = vec![Scope::AppointmentsRead];
        let err = resolve_requested_scopes(Some("bogus:scope"), &granted).unwrap_err();
        assert!(matches!(err, InteropError::InvalidScope));
    }

    #[test]
    fn resolve_requested_scopes_rejects_when_client_has_no_granted_scopes() {
        let granted: Vec<Scope> = vec![];
        let err = resolve_requested_scopes(None, &granted).unwrap_err();
        assert!(matches!(err, InteropError::InvalidScope));
    }

    #[test]
    fn resolve_requested_scopes_partial_escalation_is_rejected_wholesale() {
        // Une requête mêlant un scope accordé et un scope hors périmètre est
        // rejetée en bloc (pas d'octroi partiel silencieux).
        let granted = vec![Scope::AppointmentsRead];
        let err = resolve_requested_scopes(Some("appointments:read appointments:write"), &granted)
            .unwrap_err();
        assert!(matches!(err, InteropError::InvalidScope));
    }
}
