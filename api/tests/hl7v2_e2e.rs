//! Lot B11 — test end-to-end du listener HL7v2 (MLLP + mTLS + dispatch réel).
//!
//! Démarre `hl7v2::listener::serve` (lot B10) sur un port de test avec de
//! vrais certificats jetables (`rcgen`), se connecte comme un vrai partenaire
//! (TLS mutuel + trame MLLP réelle sur un socket TCP loopback, pas
//! `tokio::io::duplex`), et vérifie que la boucle complète — poignée de main
//! mTLS, extraction d'empreinte, résolution partenaire/cabinet (lots B6+fix),
//! dédup, audit, ACK — fonctionne de bout en bout.
//!
//! **Portée actuelle** : les lots B8 (mapping ADT) et B9 (mapping SIU) ne
//! sont pas encore câblés — `dispatch::stub_process` renvoie `AA` pour tout
//! message ADT/SIU reconnu sans encore créer de ligne `patient`/`appointment`.
//! Ce test vérifie donc le pipeline transport/auth/résolution/ACK, pas les
//! effets métier. À étendre (assertions sur les lignes DB) une fois B8/B9
//! livrés.
//!
//! Gated par `db_available()` (même convention que les autres tests interop) :
//! nécessite `APP_DATABASE_URL`/`DATABASE_URL` pointant vers une base migrée
//! jusqu'à la migration `hl7v2_partner_facility_map_find_cabinet` incluse —
//! absent dans le sandbox de développement utilisé pour écrire ce lot (pas de
//! Postgres+PostGIS+pgTAP local disponible, cf. notes de session), donc non
//! exécuté ici ; à vérifier en CI réelle.

use std::io::Write;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;

use integrations_hl7v2::{read_frame, write_frame, MllpReadOptions};
use rcgen::{CertificateParams, DistinguishedName, DnType, Issuer, KeyPair};
use rustls_pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use tokio::net::TcpStream;
use tokio_rustls::TlsConnector;
use uuid::Uuid;

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

async fn owner_pool() -> PgPool {
    let url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_owner@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

// ── Génération de certificats jetables (même pattern que hl7v2::tls tests) ─

fn make_test_ca() -> (CertificateDer<'static>, KeyPair, CertificateParams, String) {
    let mut params = CertificateParams::new(vec![]).expect("params CA valides");
    let mut dn = DistinguishedName::new();
    dn.push(DnType::CommonName, "Nubia Test CA (B11 e2e)");
    params.distinguished_name = dn;
    params.is_ca = rcgen::IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
    let key = KeyPair::generate().expect("génération de clé CA");
    let cert = params.clone().self_signed(&key).expect("auto-signature CA");
    let pem = cert.pem();
    (cert.der().clone(), key, params, pem)
}

fn make_test_leaf(
    cn: &str,
    ca_params: &CertificateParams,
    ca_key: &KeyPair,
) -> (
    CertificateDer<'static>,
    PrivateKeyDer<'static>,
    String,
    String,
) {
    let mut params = CertificateParams::new(vec![cn.to_string()]).expect("params feuille");
    let mut dn = DistinguishedName::new();
    dn.push(DnType::CommonName, cn);
    params.distinguished_name = dn;
    let key = KeyPair::generate().expect("génération de clé feuille");
    let issuer = Issuer::new(ca_params.clone(), ca_key);
    let cert = params.signed_by(&key, &issuer).expect("signature feuille");
    let cert_pem = cert.pem();
    let key_pem = key.serialize_pem();
    (
        cert.der().clone(),
        PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key.serialize_der())),
        cert_pem,
        key_pem,
    )
}

fn fingerprint_of(cert_der: &CertificateDer<'static>) -> String {
    hex::encode(Sha256::digest(cert_der.as_ref()))
}

fn write_temp_pem(dir: &std::path::Path, name: &str, pem: &str) -> std::path::PathBuf {
    let path = dir.join(name);
    let mut f = std::fs::File::create(&path).expect("création fichier PEM temporaire");
    f.write_all(pem.as_bytes()).expect("écriture PEM");
    path
}

#[derive(Debug)]
struct AcceptAnyServerCert;

impl rustls::client::danger::ServerCertVerifier for AcceptAnyServerCert {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &rustls_pki_types::ServerName<'_>,
        _ocsp_response: &[u8],
        _now: rustls_pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }
    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }
    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

/// Construit un ADT^A28 minimal avec les MSH-4/6/10 demandés.
fn build_adt_a28(sending_facility: &str, receiving_facility: &str, control_id: &str) -> Vec<u8> {
    format!(
        "MSH|^~\\&|SIH|{sending_facility}|NUBIA|{receiving_facility}|20260720101500||ADT^A28|{control_id}|P|2.5\r\
PID|1||123456^^^{sending_facility}^PI||DUPONT^JEAN||19800101|M\r"
    )
    .into_bytes()
}

async fn send_and_read_ack(
    connector: &TlsConnector,
    addr: SocketAddr,
    server_name: rustls_pki_types::ServerName<'static>,
    message: &[u8],
) -> String {
    let tcp = TcpStream::connect(addr).await.expect("connexion TCP");
    let mut tls = connector
        .connect(server_name, tcp)
        .await
        .expect("poignée de main mTLS côté client");
    write_frame(&mut tls, message)
        .await
        .expect("écriture trame MLLP");
    let ack = read_frame(&mut tls, MllpReadOptions::default())
        .await
        .expect("lecture ACK MLLP");
    String::from_utf8(ack).expect("ACK doit être de l'UTF-8 valide")
}

#[tokio::test]
async fn hl7v2_e2e_known_facility_pair_returns_aa_ack() {
    if !db_available() {
        eprintln!("APP_DATABASE_URL/DATABASE_URL absent — test ignoré (voir doc de module)");
        return;
    }

    let pool = owner_pool().await;
    let tmp = tempfile_dir();

    // ── Certs jetables : CA + serveur + client ──────────────────────────
    let (_ca_der, ca_key, ca_params, ca_pem) = make_test_ca();
    let (server_cert_der, _server_key, server_cert_pem, server_key_pem) =
        make_test_leaf("nubia-mllp-test-server", &ca_params, &ca_key);
    let (client_cert_der, client_key, _client_cert_pem, _client_key_pem) =
        make_test_leaf("eai-test-partner", &ca_params, &ca_key);
    let _ = server_cert_der;

    let cert_path = write_temp_pem(&tmp, "server.pem", &server_cert_pem);
    let key_path = write_temp_pem(&tmp, "server_key.pem", &server_key_pem);
    let ca_path = write_temp_pem(&tmp, "ca.pem", &ca_pem);

    let fingerprint = fingerprint_of(&client_cert_der);

    // ── Seed : partenaire actif + mapping vers un cabinet de test ───────
    let cabinet_id = Uuid::new_v4();
    let partner_id = Uuid::new_v4();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'B11 e2e test cabinet') ON CONFLICT (id) DO NOTHING")
        .bind(cabinet_id)
        .execute(&pool)
        .await
        .expect("seed cabinet");
    sqlx::query(
        "INSERT INTO hl7v2_partner (id, display_name, cert_fingerprint_sha256, status) \
         VALUES ($1, 'B11 e2e test partner', $2, 'active')",
    )
    .bind(partner_id)
    .bind(&fingerprint)
    .execute(&pool)
    .await
    .expect("seed hl7v2_partner");
    sqlx::query(
        "INSERT INTO hl7v2_partner_facility_map (partner_id, sending_facility, receiving_facility, cabinet_id) \
         VALUES ($1, 'SIH_E2E', 'NUBIA_E2E', $2)",
    )
    .bind(partner_id)
    .bind(cabinet_id)
    .execute(&pool)
    .await
    .expect("seed hl7v2_partner_facility_map");

    // ── Démarre le listener MLLP réel sur un port de test ───────────────
    let port = pick_free_port().await;
    // SAFETY: cargo nextest exécute chaque test dans son propre process
    // (isolation par test) — muter l'environnement ici n'affecte aucun
    // autre test.
    std::env::set_var("MLLP_PORT", port.to_string());
    std::env::set_var("MLLP_TLS_CERT_PATH", &cert_path);
    std::env::set_var("MLLP_TLS_KEY_PATH", &key_path);
    std::env::set_var("MLLP_TLS_CLIENT_CA_PATH", &ca_path);
    // Lot B8 : le listener charge un LocalKeyManager (chiffrement INS) au
    // démarrage — 32 octets fixes encodés en base64, suffisant pour ce test
    // (aucune assertion ici ne porte sur le contenu de l'INS déchiffré).
    std::env::set_var(
        "KMS_MASTER_KEY",
        base64::Engine::encode(&base64::engine::general_purpose::STANDARD, [7u8; 32]),
    );

    let status = nubia_api::hl7v2::listener::Hl7v2ListenerStatus::default();
    // Le listener tourne avec le pool applicatif (rôle nubia_app, RLS
    // active) — jamais le pool owner, comme le reste de l'API (`AppState.db`).
    let listener_pool = app_pool().await;
    tokio::spawn(nubia_api::hl7v2::listener::serve(listener_pool, status));
    // Laisse le temps au listener de binder avant de s'y connecter.
    tokio::time::sleep(Duration::from_millis(200)).await;

    let addr: SocketAddr = format!("127.0.0.1:{port}").parse().unwrap();
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let client_config = rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .expect("versions de protocole valides")
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(AcceptAnyServerCert))
        .with_client_auth_cert(vec![client_cert_der], client_key)
        .expect("config client mTLS valide");
    let connector = TlsConnector::from(Arc::new(client_config));
    let server_name = rustls_pki_types::ServerName::try_from("nubia-mllp-test-server")
        .expect("nom de serveur valide");

    // ── Couple facility connu : A28 → AA ─────────────────────────────────
    let control_id = format!("E2E-{}", Uuid::new_v4());
    let msg = build_adt_a28("SIH_E2E", "NUBIA_E2E", &control_id);
    let ack = send_and_read_ack(&connector, addr, server_name.clone(), &msg).await;
    assert!(ack.contains("MSA|AA|"), "attendu un ACK AA, obtenu : {ack}");
    assert!(
        ack.contains(&control_id),
        "l'ACK doit échoer le control-id d'origine : {ack}"
    );

    // ── Couple facility inconnu : même partenaire, mauvais MSH-6 → AR ───
    let control_id_2 = format!("E2E-{}", Uuid::new_v4());
    let bad_msg = build_adt_a28("SIH_E2E", "WRONG_RECEIVING_FACILITY", &control_id_2);
    let ack_2 = send_and_read_ack(&connector, addr, server_name, &bad_msg).await;
    assert!(
        ack_2.contains("MSA|AR|"),
        "attendu un ACK AR pour un couple facility inconnu, obtenu : {ack_2}"
    );

    // ── Nettoyage ────────────────────────────────────────────────────────
    sqlx::query("DELETE FROM hl7v2_partner_facility_map WHERE partner_id = $1")
        .bind(partner_id)
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM hl7v2_message_log WHERE partner_id = $1")
        .bind(partner_id)
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM hl7v2_partner WHERE id = $1")
        .bind(partner_id)
        .execute(&pool)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&pool)
        .await
        .ok();
}

fn tempfile_dir() -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("hl7v2-e2e-{}", Uuid::new_v4()));
    std::fs::create_dir_all(&dir).expect("création répertoire temporaire pour les certs de test");
    dir
}

async fn pick_free_port() -> u16 {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind éphémère pour choisir un port libre");
    listener.local_addr().expect("adresse locale").port()
}
