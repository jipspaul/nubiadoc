//! Espace partenaire OAuth2 / FHIR (lot A1 — socle auth). Routes publiques
//! `/v1/interop/*`.
//!
//! Les erreurs du token endpoint et de l'extracteur bearer sont rendues au
//! format **RFC 6749** (`{"error": "invalid_client", ...}`), volontairement
//! distinct du contrat `{"code": ...}` / RFC 9457 `application/problem+json`
//! utilisé par le reste de l'API — les clients OAuth2 partenaires attendent
//! la forme standard.

pub mod appointment;
pub mod auth;
pub mod capability;
pub mod directory;
pub mod error;
pub mod oauth;
pub mod slot;
pub mod subscription;
