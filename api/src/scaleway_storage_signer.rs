//! [`StorageSigner`] réel — Object Storage Scaleway (compatible S3), #4717.
//!
//! Quoi : génère une URL GET présignée (SigV4, même algorithme que AWS S3 —
//! Scaleway Object Storage est explicitement compatible S3, cf.
//! `https://www.scaleway.com/en/docs/storage/object/api-cli/object-storage-signed-request/`).
//! Remplace `StubStorageSigner` (`https://storage.example.com/...`, domaine
//! fantôme jamais résolu en DNS public) précédemment câblé en dur en
//! production dans `build_router` (#4717 — export du passeport implantaire,
//! et potentiellement `documents.rs`, `cabinet_document_download.rs`,
//! `bank_deposit_slip.rs` qui partagent le même `Arc<dyn StorageSigner>`).
//!
//! Pas de SDK Rust officiel Scaleway pour Object Storage — signature SigV4
//! manuelle via `hmac`/`sha2` (déjà dépendances du crate), même pattern déjà
//! pratiqué dans ce backend pour les intégrations tierces sans SDK Rust
//! (cf. `core-crypto::scaleway::ScalewayKeyManager` pour KMS).
//!
//! Non testé contre l'Object Storage Scaleway réel (pas de credentials
//! disponibles dans cet environnement) — l'algorithme SigV4 est standard et
//! documenté publiquement (AWS `SigV4`, repris tel quel par Scaleway). À
//! valider en conditions réelles avant mise en production.

use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};

use crate::StorageSigner;

type HmacSha256 = Hmac<Sha256>;

const DEFAULT_ENDPOINT: &str = "s3.fr-par.scw.cloud";
const DEFAULT_REGION: &str = "fr-par";

/// Implémentation `StorageSigner` pour l'Object Storage Scaleway (API
/// compatible S3, presigned URL SigV4).
pub struct ScalewayStorageSigner {
    access_key: String,
    secret_key: String,
    bucket: String,
    region: String,
    endpoint: String,
    expires_in_secs: u64,
}

impl ScalewayStorageSigner {
    /// Construit depuis les variables d'environnement `SCW_ACCESS_KEY`,
    /// `SCW_SECRET_KEY`, `SCW_BUCKET` (obligatoires en prod), `SCW_REGION`
    /// (défaut `fr-par`) et `SCW_ENDPOINT` (défaut
    /// `s3.fr-par.scw.cloud`, surchargeable pour MinIO/tests).
    pub fn from_env() -> Self {
        Self {
            access_key: std::env::var("SCW_ACCESS_KEY").unwrap_or_default(),
            secret_key: std::env::var("SCW_SECRET_KEY").unwrap_or_default(),
            bucket: std::env::var("SCW_BUCKET").unwrap_or_default(),
            region: std::env::var("SCW_REGION").unwrap_or_else(|_| DEFAULT_REGION.to_string()),
            endpoint: std::env::var("SCW_ENDPOINT")
                .unwrap_or_else(|_| DEFAULT_ENDPOINT.to_string()),
            expires_in_secs: 900,
        }
    }

    fn hmac(key: &[u8], data: &[u8]) -> Vec<u8> {
        let mut mac = HmacSha256::new_from_slice(key).expect("HMAC accepte n'importe quelle clé");
        mac.update(data);
        mac.finalize().into_bytes().to_vec()
    }

    fn signing_key(&self, date_stamp: &str) -> Vec<u8> {
        let k_date = Self::hmac(
            format!("AWS4{}", self.secret_key).as_bytes(),
            date_stamp.as_bytes(),
        );
        let k_region = Self::hmac(&k_date, self.region.as_bytes());
        let k_service = Self::hmac(&k_region, b"s3");
        Self::hmac(&k_service, b"aws4_request")
    }
}

impl StorageSigner for ScalewayStorageSigner {
    fn sign(&self, storage_key: &str) -> Option<String> {
        // Credentials absents (dev/test non configuré) : pas d'URL fabriquée
        // pointant vers un domaine inexistant — fail-closed (`→ 410` côté
        // appelant, cf. `implant_passport.rs::export_implant_passport`).
        if self.access_key.is_empty() || self.secret_key.is_empty() || self.bucket.is_empty() {
            return None;
        }

        let now = chrono::Utc::now();
        let amz_date = now.format("%Y%m%dT%H%M%SZ").to_string();
        let date_stamp = now.format("%Y%m%d").to_string();
        let credential_scope = format!("{}/{}/s3/aws4_request", date_stamp, self.region);
        let credential = format!("{}/{}", self.access_key, credential_scope);

        let host = format!("{}.{}", self.bucket, self.endpoint);
        let encoded_key = storage_key
            .split('/')
            .map(urlencode_segment)
            .collect::<Vec<_>>()
            .join("/");
        let canonical_uri = format!("/{}", encoded_key);

        let mut query_params: Vec<(String, String)> = vec![
            (
                "X-Amz-Algorithm".to_string(),
                "AWS4-HMAC-SHA256".to_string(),
            ),
            ("X-Amz-Credential".to_string(), credential),
            ("X-Amz-Date".to_string(), amz_date.clone()),
            (
                "X-Amz-Expires".to_string(),
                self.expires_in_secs.to_string(),
            ),
            ("X-Amz-SignedHeaders".to_string(), "host".to_string()),
        ];
        query_params.sort();

        let canonical_query_string = query_params
            .iter()
            .map(|(k, v)| format!("{}={}", urlencode_qs(k), urlencode_qs(v)))
            .collect::<Vec<_>>()
            .join("&");

        let canonical_headers = format!("host:{}\n", host);
        let signed_headers = "host";
        let canonical_request = format!(
            "GET\n{}\n{}\n{}\n{}\nUNSIGNED-PAYLOAD",
            canonical_uri, canonical_query_string, canonical_headers, signed_headers
        );

        let hashed_canonical_request = hex::encode(Sha256::digest(canonical_request.as_bytes()));
        let string_to_sign = format!(
            "AWS4-HMAC-SHA256\n{}\n{}\n{}",
            amz_date, credential_scope, hashed_canonical_request
        );

        let signing_key = self.signing_key(&date_stamp);
        let signature = hex::encode(Self::hmac(&signing_key, string_to_sign.as_bytes()));

        Some(format!(
            "https://{}{}?{}&X-Amz-Signature={}",
            host, canonical_uri, canonical_query_string, signature
        ))
    }
}

fn urlencode_segment(s: &str) -> String {
    urlencode(s, false)
}

fn urlencode_qs(s: &str) -> String {
    urlencode(s, true)
}

/// Encodage pourcent conforme SigV4 (RFC 3986, `~` non encodé ; `/` préservé
/// uniquement dans le chemin, jamais dans la query string — cf. paramètre
/// `encode_slash`).
fn urlencode(s: &str, encode_slash: bool) -> String {
    let mut out = String::with_capacity(s.len());
    for byte in s.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char)
            }
            b'/' if !encode_slash => out.push('/'),
            _ => out.push_str(&format!("%{:02X}", byte)),
        }
    }
    out
}
