//! `integrations-hl7v2` : parseur HL7 v2 (grammaire à délimiteurs pipe/`^`/`&`/`~`),
//! codec de trame MLLP, générateur d'ACK/NACK, et terminaison TLS mutuelle
//! (mTLS) pour le listener MLLP.
//!
//! Bibliothèque pure et auditable : pas de DB ni de tenancy — seulement
//! `tokio` (traits `AsyncRead`/`AsyncWrite` du codec MLLP) et `rustls` /
//! `tokio-rustls` (terminaison TLS, module [`tls`]). Un lot ultérieur (hors
//! périmètre) branche ceci sur un vrai listener TCP et le pipeline
//! tenant/service (résolution partenaire à partir de l'empreinte de
//! certificat, dispatch). Voir `api/AGENTS.md` pour les règles du monorepo :
//! zéro `unwrap()`/`panic!()` en dehors des tests, `#![forbid(unsafe_code)]`.
#![forbid(unsafe_code)]

pub mod ack;
pub mod message;
pub mod mllp;
pub mod parser;
pub mod tls;

pub use ack::{build_ack, AckCode, AckParams};
pub use message::{EncodingChars, Message, Segment};
pub use mllp::{read_frame, write_frame, MllpError, MllpReadOptions};
pub use parser::{parse, parse_bytes, Hl7Error};
pub use tls::{
    accept as accept_tls, build_acceptor, peer_certificate_fingerprint, MutualTlsConfig,
    ServerIdentity, TlsConfigError, TlsSessionError,
};
