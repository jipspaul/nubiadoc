//! `GET /v1/interop/fhir/metadata` — `CapabilityStatement` FHIR minimal.
//!
//! Stub statique et public (pas de JWT) : sert à un client partenaire pour
//! découvrir le serveur avant d'obtenir un token. Les ressources concrètes
//! (Patient/Appointment/Slot/...) sont ajoutées par les lots suivants qui
//! dépendent de ce socle — le tableau `resource` reste vide en lot A1.

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
                // Lot A1 = socle auth uniquement. Patient/Appointment/Slot/...
                // seront listées ici par les lots qui implémentent ces ressources.
                "resource": []
            }
        ]
    }))
}
