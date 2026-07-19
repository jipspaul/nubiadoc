//! Module applicatif HL7 v2 (lot B7) : branche la crate pure
//! `integrations-hl7v2` (parsing/ACK) sur la couche DB/tenancy (`sqlx`,
//! `core-tenancy`).
//!
//! Ce module n'est PAS un module Axum : HL7 v2 arrive en TCP brut (MLLP), pas
//! en HTTP. Le listener TCP + la terminaison mTLS (lot B5) + le branchement
//! `main.rs` sont hors périmètre (lot B10) — ici, uniquement la logique de
//! dispatch pure, appelable une fois qu'on dispose d'une empreinte de
//! certificat client et d'un message déjà parsé.
pub mod dispatch;
