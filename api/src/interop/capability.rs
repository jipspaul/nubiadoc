//! `GET /v1/interop/fhir/metadata` — `CapabilityStatement` FHIR minimal.
//!
//! Stub statique et public (pas de JWT) : sert à un client partenaire pour
//! découvrir le serveur avant d'obtenir un token. Les ressources concrètes
//! sont ajoutées au tableau `resource` par les lots qui les implémentent —
//! Practitioner/Organization/Location (lot A2, lecture seule) et Appointment
//! (lot A6). Patient/Slot/... suivront de la même façon.

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
                // Patient/... sera listée ici par le lot qui l'implémente.
                "resource": [
                    { "type": "Practitioner", "interaction": [{ "code": "read" }, { "code": "search-type" }] },
                    { "type": "Organization", "interaction": [{ "code": "read" }] },
                    { "type": "Location", "interaction": [{ "code": "read" }] },
                    {
                        "type": "Appointment",
                        "interaction": [
                            {"code": "read"},
                            {"code": "search-type"},
                            {"code": "create"},
                            {"code": "update"}
                        ]
                    },
                    { "type": "Slot", "interaction": [{ "code": "read" }, { "code": "search-type" }] },
                    { "type": "Schedule", "interaction": [{ "code": "read" }] }
                ]
            }
        ]
    }))
}
