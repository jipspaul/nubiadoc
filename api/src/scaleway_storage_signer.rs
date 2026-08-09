//! `StorageSigner` implémentation Scaleway Object Storage — #4717.
//!
//! Quoi : génère une URL présignée (AWS SigV4, l'API Object Storage de
//! Scaleway est compatible S3) pour télécharger un objet du bucket
//! configuré, consommée par tous les call sites `Extension<Arc<dyn
//! StorageSigner>>` (`implant_passport.rs`, `documents.rs`,
//! `cabinet_document_download.rs`, `bank_deposit_slip.rs`).
//!
//! Quand : construit une fois au boot (`ScalewayStorageSigner::from_env()`),
//! injecté dans le routeur de production — même pattern que
//! `BrevoMailer`/`TwilioSmsSender`/`YousignClient`.
//!
//! Pourquoi une implémentation SigV4 maison plutôt qu'un SDK AWS/S3 : pas de
//! SDK Rust officiel Scaleway (même choix déjà documenté dans
//! `core-crypto/src/scaleway.rs`), et les SDK S3 génériques (`aws-sdk-s3`)
//! ajoutent une dépendance lourde pour la seule opération nécessaire ici
//! (une présignature GET, calcul HMAC-SHA256 déjà utilisé ailleurs dans ce
//! dépôt pour les webhooks — `hmac`/`sha2`, cf. `webhooks/stripe.rs`). Le
//! contrat SigV4 "presigned URL" (query-string, `X-Amz-Signature` etc.) est
//! celui documenté par AWS (stable depuis plus d'une décennie) et par
//! Scaleway (`https://www.scaleway.com/en/docs/object-storage/api-cli/generating-aws4-authentication/`).
//!
//! Modes d'échec : `sign` ne panique jamais. Configuration absente
//! (`SCW_ACCESS_KEY`/`SCW_SECRET_KEY`/`SCW_BUCKET` vides) → `None` (`→ 410`
//! côté handler), même contrat que le stub qu'il remplace.

use chrono::Utc;
use hmac::{Hmac, Mac};
use sha2::{Digest, Sha256};

use crate::StorageSigner;

const DEFAULT_SCW_REGION: &str = "fr-par";
const DEFAULT_SCW_ENDPOINT: &str = "s3.fr-par.scw.cloud";
/// Durée de validité du lien présigné (2 heures — cohérent avec un
/// téléchargement patient déclenché depuis un clic dans l'app, jamais un
/// lien partagé/stocké côté client).
const EXPIRES_SECONDS: i64 = 7200;

type HmacSha256 = Hmac<Sha256>;

/// Implémentation `StorageSigner` pour Scaleway Object Storage (S3-compatible).
pub struct ScalewayStorageSigner {
    access_key: String,
    secret_key: String,
    bucket: String,
    region: String,
    endpoint: String,
}

impl ScalewayStorageSigner {
    /// Construit depuis les variables d'environnement `SCW_ACCESS_KEY`,
    /// `SCW_SECRET_KEY`, `SCW_BUCKET`, `SCW_REGION` (défaut `fr-par`) et
    /// `SCW_S3_ENDPOINT` (défaut `s3.fr-par.scw.cloud`). Fallback permissif
    /// (chaîne vide) si absentes : ne panique jamais au boot — `sign`
    /// retournera alors `None` (même pattern que `BrevoMailer::from_env`).
    pub fn from_env() -> Self {
        let region =
            std::env::var("SCW_REGION").unwrap_or_else(|_| DEFAULT_SCW_REGION.to_string());
        let endpoint = std::env::var("SCW_S3_ENDPOINT")
            .unwrap_or_else(|_| DEFAULT_SCW_ENDPOINT.to_string());
        Self::new(
            std::env::var("SCW_ACCESS_KEY").unwrap_or_default(),
            std::env::var("SCW_SECRET_KEY").unwrap_or_default(),
            std::env::var("SCW_BUCKET").unwrap_or_default(),
            region,
            endpoint,
        )
    }

    /// Constructeur explicite (utilisé par `from_env` et testable
    /// directement avec des identifiants/endpoint de test).
    pub fn new(
        access_key: impl Into<String>,
        secret_key: impl Into<String>,
        bucket: impl Into<String>,
        region: impl Into<String>,
        endpoint: impl Into<String>,
    ) -> Self {
        Self {
            access_key: access_key.into(),
            secret_key: secret_key.into(),
            bucket: bucket.into(),
            region: region.into(),
            endpoint: endpoint.into(),
        }
    }

    fn hmac(key: &[u8], data: &[u8]) -> Vec<u8> {
        // `new_from_slice` n'échoue que pour une clé de taille invalide pour
        // l'algo sous-jacent — jamais le cas pour HMAC-SHA256 (accepte
        // toute taille de clé). `expect` documenté, pas un `unwrap` aveugle.
        let mut mac = HmacSha256::new_from_slice(key).expect("clé HMAC de taille invalide");
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
        if self.access_key.is_empty() || self.secret_key.is_empty() || self.bucket.is_empty() {
            return None;
        }

        let now = Utc::now();
        let amz_date = now.format("%Y%m%dT%H%M%SZ").to_string();
        let date_stamp = now.format("%Y%m%d").to_string();
        let credential_scope = format!("{}/{}/s3/aws4_request", date_stamp, self.region);
        let credential = format!("{}/{}", self.access_key, credential_scope);

        // Chemin de l'objet — un seul segment `storage_key`, déjà normalisé
        // par les appelants (`format!("{domain}/{id}.pdf")`), pas
        // d'échappement supplémentaire requis (caractères `[A-Za-z0-9/_-.]`).
        let canonical_uri = format!("/{}/{}", self.bucket, storage_key);
        let host = &self.endpoint;

        let mut query_params: Vec<(String, String)> = vec![
            ("X-Amz-Algorithm".to_string(), "AWS4-HMAC-SHA256".to_string()),
            ("X-Amz-Credential".to_string(), credential),
            ("X-Amz-Date".to_string(), amz_date.clone()),
            ("X-Amz-Expires".to_string(), EXPIRES_SECONDS.to_string()),
            ("X-Amz-SignedHeaders".to_string(), "host".to_string()),
        ];
        query_params.sort();

        let canonical_query_string = query_params
            .iter()
            .map(|(k, v)| format!("{}={}", urlencode(k), urlencode(v)))
            .collect::<Vec<_>>()
            .join("&");

        let canonical_headers = format!("host:{}\n", host);
        let signed_headers = "host";
        let payload_hash = "UNSIGNED-PAYLOAD";

        let canonical_request = format!(
            "GET\n{}\n{}\n{}\n{}\n{}",
            canonical_uri, canonical_query_string, canonical_headers, signed_headers, payload_hash
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

/// Encodage URI-safe minimal (RFC 3986) pour les valeurs de query-string
/// SigV4 — `urlencoding`/équivalent n'est pas une dépendance existante de
/// ce dépôt, implémentation directe suffisante pour l'alphabet restreint
/// des valeurs signées ici (clés d'identifiants, dates, entiers).
fn urlencode(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for byte in input.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(byte as char)
            }
            _ => out.push_str(&format!("%{:02X}", byte)),
        }
    }
    out
}
