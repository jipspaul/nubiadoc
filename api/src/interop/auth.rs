//! Extracteur JWT pour les routes `/v1/interop/*` protégées par bearer token
//! (`aud = "interop"`), émis par `POST /v1/interop/oauth/token`.
//!
//! Mirrore le pattern des extracteurs `Pro*Claims`/`Pharma*Claims`
//! (`api/src/auth/mod.rs`) : lit `Authorization: Bearer <token>`, vérifie la
//! signature avec `AppState::jwt_secret` (même clé que le reste de l'API —
//! pas de secret dédié), puis vérifie `aud`.

use async_trait::async_trait;
use axum::{extract::FromRequestParts, http::request::Parts};
use integrations_interop::{parse_scopes, Scope};
use jsonwebtoken::{decode, DecodingKey, Validation};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{interop::error::InteropError, AppState};

/// Audience attendue pour tout token émis par `/v1/interop/oauth/token`.
pub const INTEROP_AUDIENCE: &str = "interop";

/// Claims JWT portées par un token partenaire interop (`client_credentials`).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InteropClaims {
    /// `interop_client.id`.
    pub sub: Uuid,
    pub aud: String,
    pub client_id: String,
    pub cabinet_id: Uuid,
    /// Scopes accordés, format OAuth2 (espace-séparé) — champ brut du JWT.
    pub scope: String,
    pub exp: u64,
}

impl InteropClaims {
    /// Décode `scope` en liste de [`Scope`] typés.
    ///
    /// Un scope inconnu dans un token que nous avons nous-mêmes signé
    /// indiquerait une corruption (ou une évolution de l'enum côté serveur
    /// après émission) — fail-closed : liste vide plutôt que de paniquer ou
    /// de faire confiance à un scope non reconnu.
    pub fn scopes(&self) -> Vec<Scope> {
        parse_scopes(&self.scope).unwrap_or_default()
    }
}

#[async_trait]
impl FromRequestParts<AppState> for InteropClaims {
    type Rejection = InteropError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let header = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or(InteropError::Unauthorized)?;

        let token = header
            .strip_prefix("Bearer ")
            .ok_or(InteropError::Unauthorized)?;

        let key = DecodingKey::from_secret(state.jwt_secret.as_bytes());
        let mut validation = Validation::default();
        validation.validate_exp = true;
        // `aud` vérifié manuellement ci-dessous plutôt que via `Validation::set_audience`
        // pour renvoyer systématiquement l'enveloppe RFC 6749 `invalid_token`.
        validation.validate_aud = false;

        let claims = decode::<InteropClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| InteropError::Unauthorized)?;

        if claims.aud != INTEROP_AUDIENCE {
            return Err(InteropError::Unauthorized);
        }

        Ok(claims)
    }
}

/// Vérifie que `claims` porte bien `scope` — sinon `403 insufficient_scope`.
///
/// Appelée par les handlers de ressources FHIR (`Slot`/`Schedule`/... — lot
/// A3+) juste après extraction de [`InteropClaims`], avant tout accès DB.
pub fn require_scope(claims: &InteropClaims, scope: Scope) -> Result<(), InteropError> {
    if claims.scopes().contains(&scope) {
        Ok(())
    } else {
        Err(InteropError::InsufficientScope)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn claims_with_scope(scope: &str) -> InteropClaims {
        InteropClaims {
            sub: Uuid::new_v4(),
            aud: INTEROP_AUDIENCE.to_string(),
            client_id: "client-test".to_string(),
            cabinet_id: Uuid::new_v4(),
            scope: scope.to_string(),
            exp: 0,
        }
    }

    #[test]
    fn require_scope_passes_when_present() {
        let claims = claims_with_scope("appointments:read directory:read");
        assert!(require_scope(&claims, Scope::AppointmentsRead).is_ok());
    }

    #[test]
    fn require_scope_rejects_when_absent() {
        let claims = claims_with_scope("directory:read");
        assert!(matches!(
            require_scope(&claims, Scope::AppointmentsWrite),
            Err(InteropError::InsufficientScope)
        ));
    }

    #[test]
    fn scopes_decodes_space_separated_list() {
        let claims = claims_with_scope("appointments:read patients:read");
        assert_eq!(
            claims.scopes(),
            vec![Scope::AppointmentsRead, Scope::PatientsRead]
        );
    }

    #[test]
    fn scopes_returns_empty_on_unknown_scope() {
        let claims = claims_with_scope("appointments:read totally:bogus");
        assert!(claims.scopes().is_empty());
    }
}
