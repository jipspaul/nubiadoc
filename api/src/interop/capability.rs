//! `GET /v1/interop/fhir/metadata` — `CapabilityStatement` FHIR minimal.
//!
//! Stub statique et public (pas de JWT) : sert à un client partenaire pour
//! découvrir le serveur avant d'obtenir un token. Les ressources concrètes
//! sont ajoutées au tableau `resource` par les lots qui les implémentent —
//! Practitioner/Organization/Location (lot A2, lecture seule), Appointment
//! (lot A6) et Subscription (lot A7, notifications). Patient/Slot/... suivront
//! de la même façon.

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
                // Point d'entrée OAuth (RFC 6749 §4.4, client_credentials
                // uniquement — pas de flow authorize) : cf. api/src/interop/oauth.rs.
                "security": {
                    "service": [
                        {
                            "coding": [
                                {
                                    "system": "http://terminology.hl7.org/CodeSystem/restful-security-service",
                                    "code": "SMART-on-FHIR"
                                }
                            ]
                        }
                    ],
                    "extension": [
                        {
                            "url": "http://fhir-registry.smarthealthit.org/StructureDefinition/oauth-uris",
                            "extension": [
                                { "url": "token", "valueUri": "/v1/interop/oauth/token" }
                            ]
                        }
                    ]
                },
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
                            {"code": "patch"}
                        ]
                    },
                    { "type": "Slot", "interaction": [{ "code": "read" }, { "code": "search-type" }] },
                    { "type": "Schedule", "interaction": [{ "code": "read" }] },
                    { "type": "Patient", "interaction": [{ "code": "read" }, { "code": "search-type" }] },
                    { "type": "Subscription", "interaction": [{ "code": "create" }, { "code": "read" }] }
                ]
            }
        ]
    }))
}
