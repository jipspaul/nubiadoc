//! `GET /v1/interop/fhir/metadata` — `CapabilityStatement` FHIR minimal.
//!
//! Stub statique et public (pas de JWT) : sert à un client partenaire pour
//! découvrir le serveur avant d'obtenir un token. Patient/Appointment/Slot/...
//! sont ajoutées par les lots suivants (A3/A4/A6) qui dépendent de ce socle —
//! seuls Practitioner/Organization/Location (lot A2, lecture seule) figurent
//! ici pour l'instant.

use axum::Json;
use serde_json::{json, Value};

/// Retourne un `CapabilityStatement` FHIR R4 minimal (`fhirVersion: "4.0.1"`).
pub async fn capability_statement() -> Json<Value> {
    Json(json!({
        "resourceType": "CapabilityStatement",
        "status": "active",
        "kind": "instance",
        "fhirVersion": "4.0.1",
        "format": ["json"],
        "rest": [
            {
                "mode": "server",
                // Lot A2 = annuaire lecture seule. Patient/Appointment/Slot/...
                // seront ajoutées ici par les lots qui implémentent ces ressources.
                "resource": [
                    { "type": "Practitioner", "interaction": [{ "code": "read" }, { "code": "search-type" }] },
                    { "type": "Organization", "interaction": [{ "code": "read" }] },
                    { "type": "Location", "interaction": [{ "code": "read" }] }
                ]
            }
        ]
    }))
}
