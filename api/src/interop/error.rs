//! Erreurs du module interop — rendu **RFC 6749** (`{"error": "..."}`),
//! volontairement distinct du contrat `{"code": ...}` / RFC 9457
//! `application/problem+json` du reste de l'API : les clients OAuth2
//! partenaires attendent la forme standard `invalid_client`/`invalid_scope`/...

use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde_json::json;

/// Erreur du domaine interop (extracteur bearer + token endpoint).
#[derive(Debug)]
pub enum InteropError {
    /// `client_id`/`client_secret` invalide, client révoqué, ou aucun secret actif.
    InvalidClient,
    /// `grant_type` absent ou non supporté (seul `client_credentials`, lot A1).
    UnsupportedGrantType,
    /// Scope demandé absent/mal formé ou pas un sous-ensemble des scopes
    /// accordés au client (tentative d'escalade).
    InvalidScope,
    /// Requête malformée (champs manquants/vides).
    InvalidRequest,
    /// JWT bearer absent, expiré, signature invalide, ou `aud != "interop"`.
    Unauthorized,
    /// Scope requis absent des claims du token porteur.
    InsufficientScope,
    /// Erreur interne (DB, hachage, encodage JWT, ...) — jamais de détail exposé.
    Internal,
}

impl IntoResponse for InteropError {
    fn into_response(self) -> Response {
        // Forme RFC 6749 §5.2 / §7.2 : {"error": "...", "error_description": "..."}.
        let (status, error, description): (StatusCode, &str, Option<&str>) = match self {
            InteropError::InvalidClient => (
                StatusCode::UNAUTHORIZED,
                "invalid_client",
                Some("client_id ou client_secret invalide"),
            ),
            InteropError::UnsupportedGrantType => (
                StatusCode::BAD_REQUEST,
                "unsupported_grant_type",
                Some("seul client_credentials est supporté"),
            ),
            InteropError::InvalidScope => (
                StatusCode::BAD_REQUEST,
                "invalid_scope",
                Some("scope demandé hors du périmètre accordé au client"),
            ),
            InteropError::InvalidRequest => (
                StatusCode::BAD_REQUEST,
                "invalid_request",
                Some("paramètres de requête manquants ou invalides"),
            ),
            InteropError::Unauthorized => (StatusCode::UNAUTHORIZED, "invalid_token", None),
            InteropError::InsufficientScope => (StatusCode::FORBIDDEN, "insufficient_scope", None),
            InteropError::Internal => (StatusCode::INTERNAL_SERVER_ERROR, "server_error", None),
        };

        let mut body = json!({ "error": error });
        if let Some(desc) = description {
            body["error_description"] = json!(desc);
        }

        (status, Json(body)).into_response()
    }
}

/// Erreur des routes ressources FHIR (`Practitioner`/`Organization`/`Location`
/// lot A2, `Slot`/`Schedule` lot A3, `Appointment` lot A6, ...) — rendue en
/// `OperationOutcome` (FHIR R4), volontairement **distinct** du format
/// RFC 6749 ci-dessus : une fois le bearer token validé par
/// [`crate::interop::auth::InteropClaims`] (qui reste RFC 6749/6750, cf. son
/// propre extracteur), toute erreur décidée *dans* un handler ressource
/// (scope insuffisant, ressource introuvable, paramètre de recherche
/// invalide, erreur interne) doit prendre la forme attendue par un client
/// FHIR standard.
#[derive(Debug)]
pub enum FhirError {
    /// Scope requis absent des claims du token porteur (cf. `require_scope`).
    Forbidden,
    /// Ressource absente, ou appartenant à un autre cabinet que celui du token
    /// (jamais distingué du "vraiment absent" — pas de fuite d'existence
    /// cross-tenant).
    NotFound,
    /// Paramètre de recherche malformé (ex. `from`/`to` non ISO 8601, lot A3).
    InvalidParameter(String),
    /// Erreur interne (DB, ...) — jamais de détail exposé.
    Internal,
}

/// Une [`InteropError::InsufficientScope`] (rejet de `require_scope`) se
/// traduit en `Forbidden` FHIR ; toute autre variante (ne devrait pas se
/// produire ici, `require_scope` ne renvoie que celle-ci) tombe en `Internal`
/// fail-closed plutôt que de paniquer sur un pattern non exhaustif.
impl From<InteropError> for FhirError {
    fn from(err: InteropError) -> Self {
        match err {
            InteropError::InsufficientScope => FhirError::Forbidden,
            _ => FhirError::Internal,
        }
    }
}

impl IntoResponse for FhirError {
    fn into_response(self) -> Response {
        let (status, code, diagnostics): (StatusCode, &str, String) = match self {
            FhirError::Forbidden => (
                StatusCode::FORBIDDEN,
                "forbidden",
                "scope insuffisant pour accéder à cette ressource".to_string(),
            ),
            FhirError::NotFound => (
                StatusCode::NOT_FOUND,
                "not-found",
                "ressource introuvable".to_string(),
            ),
            FhirError::InvalidParameter(detail) => (StatusCode::BAD_REQUEST, "invalid", detail),
            FhirError::Internal => (
                StatusCode::INTERNAL_SERVER_ERROR,
                "exception",
                "erreur interne".to_string(),
            ),
        };

        let body = json!({
            "resourceType": "OperationOutcome",
            "issue": [{
                "severity": "error",
                "code": code,
                "diagnostics": diagnostics,
            }]
        });

        (status, Json(body)).into_response()
    }
}

#[cfg(test)]
mod fhir_error_tests {
    use super::*;

    #[test]
    fn insufficient_scope_maps_to_forbidden() {
        assert!(matches!(
            FhirError::from(InteropError::InsufficientScope),
            FhirError::Forbidden
        ));
    }

    #[test]
    fn other_interop_errors_map_to_internal_fail_closed() {
        assert!(matches!(
            FhirError::from(InteropError::Unauthorized),
            FhirError::Internal
        ));
    }
}
