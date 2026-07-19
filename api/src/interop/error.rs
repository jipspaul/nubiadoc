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

/// Erreur des routes FHIR **ressources** (`Slot`/`Schedule`/... — lot A3+),
/// rendue en `OperationOutcome` FHIR R4 — contrat distinct de [`InteropError`]
/// (RFC 6749), qui reste réservé au token endpoint et à l'extracteur bearer
/// (`api/src/interop/auth.rs`) : un bearer token absent/expiré/mal signé
/// continue de produire `{"error": "invalid_token"}` (échec avant même
/// d'atteindre un handler ressource), mais tout ce qui est décidé *dans* un
/// handler ressource (scope insuffisant, ressource introuvable, paramètre de
/// recherche invalide) est un problème FHIR, pas OAuth2.
#[derive(Debug)]
pub enum FhirError {
    /// Scope requis (ex. `slots:read`) absent des claims du token porteur.
    InsufficientScope,
    /// Ressource introuvable — id inconnu, supprimé (`deleted_at`), ou hors du
    /// `cabinet_id` du token. Même statut dans les deux derniers cas : jamais
    /// de distinction observable entre « n'existe pas » et « appartient à un
    /// autre cabinet » (pas de fuite d'existence cross-tenant).
    NotFound,
    /// Paramètre de recherche malformé (ex. `from`/`to` non ISO 8601).
    InvalidParameter(String),
    /// Erreur interne (DB, ...) — jamais de détail exposé.
    Internal,
}

impl From<InteropError> for FhirError {
    /// Permet d'utiliser `require_scope(&claims, ...)?` (qui renvoie
    /// [`InteropError`]) directement dans un handler dont l'erreur est
    /// [`FhirError`] : le seul cas qu'il produit en pratique ici est
    /// `InsufficientScope` (le token a déjà été validé par l'extracteur
    /// `InteropClaims` avant d'atteindre le handler), mais on couvre les
    /// autres variantes fail-closed en `Internal` plutôt que de paniquer sur
    /// un `match` non exhaustif.
    fn from(err: InteropError) -> Self {
        match err {
            InteropError::InsufficientScope => FhirError::InsufficientScope,
            _ => FhirError::Internal,
        }
    }
}

impl IntoResponse for FhirError {
    fn into_response(self) -> Response {
        let (status, code, diagnostics): (StatusCode, &str, String) = match self {
            FhirError::InsufficientScope => (
                StatusCode::FORBIDDEN,
                "forbidden",
                "scope requis absent du token porteur".to_string(),
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
