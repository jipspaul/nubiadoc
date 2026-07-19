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
