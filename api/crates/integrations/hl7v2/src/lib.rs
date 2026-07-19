//! `integrations-hl7v2` : parseur HL7 v2 (grammaire à délimiteurs pipe/`^`/`&`/`~`),
//! codec de trame MLLP, et générateur d'ACK/NACK.
//!
//! Bibliothèque pure et auditable : aucune dépendance réseau/TLS, DB, ou
//! tenancy — seulement `tokio` pour les traits `AsyncRead`/`AsyncWrite` du
//! codec MLLP. Un lot ultérieur (hors périmètre) branche ceci sur un
//! listener TCP réel et le pipeline tenant/service. Voir `api/AGENTS.md` pour
//! les règles du monorepo : zéro `unwrap()`/`panic!()` en dehors des tests,
//! `#![forbid(unsafe_code)]`.
#![forbid(unsafe_code)]

pub mod ack;
pub mod message;
pub mod mllp;
pub mod parser;

pub use ack::{build_ack, AckCode, AckParams};
pub use message::{EncodingChars, Message, Segment};
pub use mllp::{read_frame, write_frame, MllpError, MllpReadOptions};
pub use parser::{parse, parse_bytes, Hl7Error};
