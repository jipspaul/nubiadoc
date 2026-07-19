//! Terminaison TLS mutuelle (mTLS) pour le listener MLLP (lot B5).
//!
//! Ce module fait exactement deux choses : (1) construire un
//! [`rustls::ServerConfig`] qui EXIGE et VÉRIFIE un certificat client contre
//! une chaîne de CA de confiance configurable, et (2) une fois la poignée de
//! main terminée, extraire l'empreinte SHA-256 du certificat client présenté.
//!
//! **Ce qu'il ne fait PAS** : résoudre un partenaire/tenant à partir de
//! l'empreinte (table de correspondance empreinte → partenaire), ni brancher
//! un vrai listener TCP sur le reste du pipeline applicatif. C'est le rôle
//! des lots B6/B7 (résolution partenaire/dispatch) et B10 (câblage dans
//! `api/src/main.rs`) — ce module se contente d'exposer une empreinte propre
//! et stable en tant que clé de recherche.
//!
//! ## Modèle de confiance
//!
//! [`MutualTlsConfig::trusted_client_cas`] accepte une **liste** de
//! certificats de CA (pas un seul). Cela permet deux topologies, au choix de
//! l'appelant, sans rien coder en dur ici :
//!
//! - **CA partagée** : tous les partenaires reçoivent un certificat signé
//!   par une seule CA « Nubia interop » ; un seul CA cert dans la liste.
//! - **CA épinglée par partenaire** : chaque partenaire apporte son propre
//!   certificat racine (ou intermédiaire) auto-signé/interne, et chacun est
//!   ajouté séparément à `trusted_client_cas`. `rustls::RootCertStore`
//!   accepte nativement plusieurs racines indépendantes : la vérification de
//!   chaîne réussit dès que le certificat client présenté chaîne jusqu'à
//!   *l'une* d'entre elles.
//!
//! Dans les deux cas, la **confiance** (« ce cert est signé par une autorité
//! que nous acceptons ») est strictement séparée de **l'identité** (« quel
//! partenaire/tenant est-ce précisément »). Ce module ne répond qu'à la
//! première question. La réponse à la seconde — mapper une empreinte de
//! certificat vers un partenaire — est déliberement laissée à un lot
//! ultérieur : le CN d'un certificat est un texte libre fourni par le
//! partenaire et donc usurpable, alors que l'empreinte SHA-256 du certificat
//! entier ([`peer_certificate_fingerprint`]) ne l'est pas.
//!
//! ## Choix du backend crypto : `ring`, pas `aws-lc-rs`
//!
//! `rustls` 0.23 supporte deux fournisseurs crypto interchangeables. Ce
//! module épingle explicitement `ring` :
//!
//! 1. **Déjà résolu dans le workspace.** `api/Cargo.lock` contient déjà
//!    `rustls 0.23.41` + `rustls-webpki 0.103` + `ring 0.17.14` (via la
//!    feature `rustls-tls` de `reqwest`, utilisée pour les appels HTTP
//!    sortants). Aucune trace d'`aws-lc-rs` dans le lock. Ajouter `ring` ici
//!    aligne ce crate sur un backend déjà présent plutôt que d'en introduire
//!    un second, incompatible et plus lourd à compiler deux fois.
//! 2. **Cross-compilation musl.** `.forgejo/workflows/deploy.yml` cross-compile
//!    le binaire API en `x86_64-unknown-linux-musl` via `cargo-zigbuild`
//!    (`zig cc` comme linker/compilateur C), sur un runner ARM64, sans QEMU.
//!    `ring` compile son cœur en C/asm mais a un historique de longue date
//!    de cross-compilation musl réussie via des toolchains `cc`-compatibles
//!    non natives (dont `zig cc`, largement utilisé dans l'écosystème
//!    `cargo-zigbuild` précisément pour ce genre de crate). `aws-lc-rs`
//!    vendorise et construit AWS-LC (CMake + son propre détecteur de
//!    toolchain assembleur) : c'est plus fragile sous cross-compilation
//!    musl non native, et les rapports d'échecs sous `zig cc`/musl sont plus
//!    fréquents dans l'écosystème que pour `ring`.
//!
//! **Ce choix n'a pas été vérifié en conditions réelles de CI de
//! cross-compilation** (pas de run `cargo zigbuild` exécuté par cet agent) —
//! seule la compilation native a été vérifiée ici. À valider par un humain
//! sur le prochain run du workflow de déploiement une fois ce lot mergé.
#![allow(clippy::result_large_err)]

use std::sync::Arc;

use rustls::server::{VerifierBuilderError, WebPkiClientVerifier};
use rustls::{RootCertStore, ServerConfig};
use rustls_pki_types::{CertificateDer, PrivateKeyDer};
use sha2::{Digest, Sha256};
use thiserror::Error;
use tokio::io::{AsyncRead, AsyncWrite};
use tokio_rustls::server::TlsStream;
use tokio_rustls::TlsAcceptor;

/// Identité TLS présentée par le serveur (chaîne de certificats + clé
/// privée correspondante). N'a pas besoin d'être fournie par un partenaire :
/// c'est le certificat serveur de Nubia lui-même, le même pour tous les
/// partenaires qui se connectent à ce listener MLLP.
pub struct ServerIdentity {
    /// Chaîne de certificats du serveur (feuille en premier, puis
    /// intermédiaires éventuels), au format DER.
    pub cert_chain: Vec<CertificateDer<'static>>,
    /// Clé privée correspondant au certificat feuille de `cert_chain`.
    pub private_key: PrivateKeyDer<'static>,
}

/// Configuration complète de la terminaison mTLS : identité serveur +
/// magasin de CA de confiance pour les certificats clients. Voir la
/// documentation de module pour le modèle de confiance.
pub struct MutualTlsConfig {
    /// Identité TLS du serveur.
    pub server_identity: ServerIdentity,
    /// CA (une ou plusieurs) auxquelles un certificat client doit chaîner
    /// pour être accepté. Voir « Modèle de confiance » dans la doc de module.
    pub trusted_client_cas: Vec<CertificateDer<'static>>,
}

/// Erreur de construction de la configuration TLS mutuelle : toujours une
/// erreur de configuration statique (cert/clé/CA malformés), jamais liée à
/// une connexion particulière. Distincte de [`TlsSessionError`], qui couvre
/// les échecs par-connexion (handshake).
#[derive(Debug, Error)]
pub enum TlsConfigError {
    /// Un des certificats de `trusted_client_cas` n'a pas pu être ajouté au
    /// magasin de confiance (DER malformé, extensions incohérentes, etc.).
    #[error("certificat de CA de confiance invalide : {0}")]
    InvalidTrustedCa(#[source] rustls::Error),
    /// Construction du vérificateur de certificat client échouée (ex :
    /// magasin de CA vide).
    #[error("construction du vérificateur de certificat client échouée : {0}")]
    ClientVerifierBuild(#[from] VerifierBuilderError),
    /// Le fournisseur crypto sélectionné ne supporte pas les versions de
    /// protocole TLS par défaut (ne devrait pas se produire avec `ring`).
    #[error("versions de protocole TLS incompatibles avec le fournisseur crypto : {0}")]
    ProtocolVersions(#[source] rustls::Error),
    /// La chaîne de certificats serveur ou sa clé privée est invalide
    /// (format DER incorrect, clé ne correspondant pas au certificat, etc.).
    #[error("certificat ou clé privée serveur invalide : {0}")]
    InvalidServerIdentity(#[source] rustls::Error),
}

/// Erreur de session TLS : couvre l'échec de la poignée de main (certificat
/// client absent, non fiable, expiré, SNI/protocole incompatible — `rustls`
/// remonte tous ces cas comme des `std::io::Error` au moment de
/// `accept()`), ainsi que l'incohérence défensive « handshake réussi mais
/// aucun certificat client retenu » alors que ce module configure toujours
/// la vérification client comme obligatoire.
#[derive(Debug, Error)]
pub enum TlsSessionError {
    /// Échec de la poignée de main TLS. Regroupe tous les cas côté
    /// protocole : certificat client absent, chaîne non fiable, certificat
    /// expiré, ou négociation de protocole/SNI incompatible — `rustls`
    /// remonte chacun d'entre eux comme un simple échec d'E/S côté
    /// `tokio-rustls`, sans distinction de variante côté API publique.
    #[error("échec de la poignée de main TLS mutuelle : {0}")]
    Handshake(#[from] std::io::Error),
    /// La session TLS s'est établie sans qu'aucun certificat client n'ait
    /// été retenu, alors que la vérification client est configurée comme
    /// obligatoire par [`build_acceptor`]. Ne devrait jamais se produire en
    /// pratique (protection défensive plutôt qu'un cas attendu).
    #[error("session TLS établie sans certificat client malgré une vérification obligatoire")]
    MissingPeerCertificate,
}

/// Construit un [`TlsAcceptor`] qui exige et vérifie un certificat client
/// (mTLS) pour chaque connexion entrante, contre `config.trusted_client_cas`.
///
/// Le [`TlsAcceptor`] retourné est indépendant de tout transport concret :
/// [`accept`] l'utilise avec n'importe quel `AsyncRead + AsyncWrite + Unpin`
/// (typiquement un `tokio::net::TcpStream` accepté par un listener MLLP,
/// mais un flux en mémoire fonctionne aussi bien pour les tests).
pub fn build_acceptor(config: MutualTlsConfig) -> Result<TlsAcceptor, TlsConfigError> {
    let provider = Arc::new(rustls::crypto::ring::default_provider());

    let mut roots = RootCertStore::empty();
    for ca in config.trusted_client_cas {
        roots.add(ca).map_err(TlsConfigError::InvalidTrustedCa)?;
    }

    let client_verifier =
        WebPkiClientVerifier::builder_with_provider(Arc::new(roots), provider.clone()).build()?;

    let server_config = ServerConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .map_err(TlsConfigError::ProtocolVersions)?
        .with_client_cert_verifier(client_verifier)
        .with_single_cert(
            config.server_identity.cert_chain,
            config.server_identity.private_key,
        )
        .map_err(TlsConfigError::InvalidServerIdentity)?;

    Ok(TlsAcceptor::from(Arc::new(server_config)))
}

/// Effectue la poignée de main mTLS côté serveur sur un flux déjà accepté
/// (ex : un `TcpStream` sorti de `TcpListener::accept()`), et retourne le
/// [`TlsStream`] résultant. Ce dernier implémente `AsyncRead`/`AsyncWrite`,
/// donc [`crate::mllp::read_frame`]/[`crate::mllp::write_frame`] s'y
/// branchent sans aucune adaptation.
///
/// Jamais de panique : tout échec de poignée de main (cert absent, chaîne
/// non fiable, certificat expiré, protocole incompatible) revient comme
/// [`TlsSessionError::Handshake`].
pub async fn accept<S>(acceptor: &TlsAcceptor, stream: S) -> Result<TlsStream<S>, TlsSessionError>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let stream = acceptor.accept(stream).await?;
    Ok(stream)
}

/// Calcule l'empreinte SHA-256 (hex minuscule, 64 caractères) du certificat
/// client (feuille) présenté lors d'une session mTLS déjà établie.
///
/// C'est volontairement l'empreinte du certificat entier, pas son CN : le CN
/// est un champ texte libre choisi par l'émetteur du certificat et donc
/// usurpable, alors que l'empreinte engage tout le contenu du certificat
/// (clé publique incluse). Cette empreinte est stable pour un même
/// certificat et pensée comme clé de recherche pour la résolution de
/// partenaire d'un lot ultérieur (B6/B7) — ce module ne fait aucune
/// résolution lui-même.
pub fn peer_certificate_fingerprint<S>(stream: &TlsStream<S>) -> Result<String, TlsSessionError> {
    let (_io, connection) = stream.get_ref();
    let peer_certs = connection
        .peer_certificates()
        .ok_or(TlsSessionError::MissingPeerCertificate)?;
    let leaf = peer_certs
        .first()
        .ok_or(TlsSessionError::MissingPeerCertificate)?;
    let digest = Sha256::digest(leaf.as_ref());
    Ok(hex::encode(digest))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::SocketAddr;

    use rcgen::{CertificateParams, DistinguishedName, DnType, Issuer, KeyPair};
    use rustls_pki_types::PrivatePkcs8KeyDer;
    use tokio::net::{TcpListener, TcpStream};
    use tokio_rustls::TlsConnector;

    /// Génère une CA de test auto-signée. Retourne son certificat DER, sa
    /// clé privée, et ses `CertificateParams` (nécessaires pour signer des
    /// certificats feuille avec `rcgen`).
    fn make_test_ca() -> (CertificateDer<'static>, KeyPair, CertificateParams) {
        let mut params = CertificateParams::new(vec![]).expect("params CA valides");
        let mut dn = DistinguishedName::new();
        dn.push(DnType::CommonName, "Nubia Test CA");
        params.distinguished_name = dn;
        params.is_ca = rcgen::IsCa::Ca(rcgen::BasicConstraints::Unconstrained);
        let key = KeyPair::generate().expect("génération de clé CA");
        let cert = params.clone().self_signed(&key).expect("auto-signature CA");
        (cert.der().clone(), key, params)
    }

    /// Génère un certificat feuille (client ou serveur) signé par la CA de
    /// test donnée.
    fn make_test_leaf(
        cn: &str,
        ca_params: &CertificateParams,
        ca_key: &KeyPair,
    ) -> (CertificateDer<'static>, PrivateKeyDer<'static>) {
        let mut params = CertificateParams::new(vec![cn.to_string()]).expect("params feuille");
        let mut dn = DistinguishedName::new();
        dn.push(DnType::CommonName, cn);
        params.distinguished_name = dn;
        let key = KeyPair::generate().expect("génération de clé feuille");
        let issuer = Issuer::new(ca_params.clone(), ca_key);
        let cert = params.signed_by(&key, &issuer).expect("signature feuille");
        (
            cert.der().clone(),
            PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key.serialize_der())),
        )
    }

    /// Vérificateur de certificat serveur factice côté client de test : ce
    /// module ne teste QUE l'authentification mTLS côté serveur (le sujet
    /// de ce lot), pas la vérification du certificat serveur par le client
    /// — accepter n'importe quel certificat serveur ici est donc correct
    /// pour ces tests, jamais utilisé en dehors de `#[cfg(test)]`.
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

    /// Démarre un vrai listener TCP loopback (`127.0.0.1:0`) et retourne son
    /// adresse + le `TcpListener`. Un vrai socket est nécessaire ici (pas
    /// `tokio::io::duplex`) : ce lot exerce une poignée de main TLS réelle,
    /// qui a besoin d'un transport authentique.
    async fn bind_loopback() -> (TcpListener, SocketAddr) {
        let listener = TcpListener::bind("127.0.0.1:0")
            .await
            .expect("bind loopback");
        let addr = listener.local_addr().expect("adresse locale");
        (listener, addr)
    }

    fn client_config_with_cert(
        provider: Arc<rustls::crypto::CryptoProvider>,
        client_cert: CertificateDer<'static>,
        client_key: PrivateKeyDer<'static>,
    ) -> rustls::ClientConfig {
        rustls::ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .expect("versions de protocole valides")
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(AcceptAnyServerCert))
            .with_client_auth_cert(vec![client_cert], client_key)
            .expect("configuration client mTLS valide")
    }

    fn client_config_without_cert(
        provider: Arc<rustls::crypto::CryptoProvider>,
    ) -> rustls::ClientConfig {
        rustls::ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .expect("versions de protocole valides")
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(AcceptAnyServerCert))
            .with_no_client_auth()
    }

    #[tokio::test]
    async fn successful_handshake_yields_correct_client_fingerprint() {
        let (ca_cert, ca_key, ca_params) = make_test_ca();
        let (server_cert, server_key) = make_test_leaf("nubia-server", &ca_params, &ca_key);
        let (client_cert, client_key) = make_test_leaf("partner-a-client", &ca_params, &ca_key);
        let expected_fingerprint = hex::encode(Sha256::digest(client_cert.as_ref()));

        let acceptor = build_acceptor(MutualTlsConfig {
            server_identity: ServerIdentity {
                cert_chain: vec![server_cert],
                private_key: server_key,
            },
            trusted_client_cas: vec![ca_cert],
        })
        .expect("configuration mTLS valide");

        let (listener, addr) = bind_loopback().await;
        let server_task = tokio::spawn(async move {
            let (tcp, _peer) = listener.accept().await.expect("accept TCP");
            let tls = accept(&acceptor, tcp).await.expect("handshake mTLS réussi");
            peer_certificate_fingerprint(&tls).expect("empreinte client extraite")
        });

        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let client_config = client_config_with_cert(provider, client_cert, client_key);
        let connector = TlsConnector::from(Arc::new(client_config));
        let tcp = TcpStream::connect(addr)
            .await
            .expect("connexion TCP client");
        let server_name =
            rustls_pki_types::ServerName::try_from("nubia-server").expect("nom de serveur valide");
        let _client_tls = connector
            .connect(server_name, tcp)
            .await
            .expect("handshake mTLS côté client réussi");

        let fingerprint = server_task.await.expect("tâche serveur terminée");
        assert_eq!(fingerprint, expected_fingerprint);
        assert_eq!(fingerprint.len(), 64, "SHA-256 hex = 64 caractères");
    }

    #[tokio::test]
    async fn client_with_no_certificate_is_rejected() {
        let (ca_cert, ca_key, ca_params) = make_test_ca();
        let (server_cert, server_key) = make_test_leaf("nubia-server", &ca_params, &ca_key);

        let acceptor = build_acceptor(MutualTlsConfig {
            server_identity: ServerIdentity {
                cert_chain: vec![server_cert],
                private_key: server_key,
            },
            trusted_client_cas: vec![ca_cert],
        })
        .expect("configuration mTLS valide");

        let (listener, addr) = bind_loopback().await;
        let server_task = tokio::spawn(async move {
            let (tcp, _peer) = listener.accept().await.expect("accept TCP");
            accept(&acceptor, tcp).await
        });

        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let client_config = client_config_without_cert(provider);
        let connector = TlsConnector::from(Arc::new(client_config));
        let tcp = TcpStream::connect(addr)
            .await
            .expect("connexion TCP client");
        let server_name =
            rustls_pki_types::ServerName::try_from("nubia-server").expect("nom de serveur valide");
        // Le client ne présente aucun certificat : le serveur doit rejeter la
        // poignée de main (peu importe que l'échec apparaisse d'abord côté
        // client ou côté serveur, seul le résultat serveur nous intéresse ici).
        let _ = connector.connect(server_name, tcp).await;

        let result = server_task.await.expect("tâche serveur terminée");
        assert!(
            matches!(result, Err(TlsSessionError::Handshake(_))),
            "handshake sans certificat client doit être rejeté, reçu : {result:?}"
        );
    }

    #[tokio::test]
    async fn client_certificate_from_untrusted_ca_is_rejected() {
        let (ca_cert, ca_key, ca_params) = make_test_ca();
        let (server_cert, server_key) = make_test_leaf("nubia-server", &ca_params, &ca_key);
        // Deuxième CA, jamais ajoutée à `trusted_client_cas` du serveur.
        let (_rogue_ca_cert, rogue_ca_key, rogue_ca_params) = make_test_ca();
        let (rogue_client_cert, rogue_client_key) =
            make_test_leaf("partner-imposter", &rogue_ca_params, &rogue_ca_key);

        let acceptor = build_acceptor(MutualTlsConfig {
            server_identity: ServerIdentity {
                cert_chain: vec![server_cert],
                private_key: server_key,
            },
            trusted_client_cas: vec![ca_cert], // seule la CA légitime est fiable
        })
        .expect("configuration mTLS valide");

        let (listener, addr) = bind_loopback().await;
        let server_task = tokio::spawn(async move {
            let (tcp, _peer) = listener.accept().await.expect("accept TCP");
            accept(&acceptor, tcp).await
        });

        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let client_config = client_config_with_cert(provider, rogue_client_cert, rogue_client_key);
        let connector = TlsConnector::from(Arc::new(client_config));
        let tcp = TcpStream::connect(addr)
            .await
            .expect("connexion TCP client");
        let server_name =
            rustls_pki_types::ServerName::try_from("nubia-server").expect("nom de serveur valide");
        let _ = connector.connect(server_name, tcp).await;

        let result = server_task.await.expect("tâche serveur terminée");
        assert!(
            matches!(result, Err(TlsSessionError::Handshake(_))),
            "certificat client signé par une CA non fiable doit être rejeté, reçu : {result:?}"
        );
    }

    #[tokio::test]
    async fn mllp_frames_round_trip_over_established_mtls_stream() {
        let (ca_cert, ca_key, ca_params) = make_test_ca();
        let (server_cert, server_key) = make_test_leaf("nubia-server", &ca_params, &ca_key);
        let (client_cert, client_key) = make_test_leaf("partner-b-client", &ca_params, &ca_key);

        let acceptor = build_acceptor(MutualTlsConfig {
            server_identity: ServerIdentity {
                cert_chain: vec![server_cert],
                private_key: server_key,
            },
            trusted_client_cas: vec![ca_cert],
        })
        .expect("configuration mTLS valide");

        let (listener, addr) = bind_loopback().await;
        let payload = b"MSH|^~\\&|A|B|C|D|20260719||ADT^A28|1|P|2.5\rPID|1\r".to_vec();
        let payload_for_server = payload.clone();

        let server_task = tokio::spawn(async move {
            let (tcp, _peer) = listener.accept().await.expect("accept TCP");
            let mut tls = accept(&acceptor, tcp).await.expect("handshake mTLS réussi");
            // Lit une trame MLLP envoyée par le client, PUIS renvoie la même
            // trame : prouve que `mllp::read_frame`/`write_frame` composent
            // avec le flux TLS sans aucune adaptation.
            let received =
                crate::mllp::read_frame(&mut tls, crate::mllp::MllpReadOptions::default())
                    .await
                    .expect("lecture de trame MLLP sur flux TLS");
            assert_eq!(received, payload_for_server);
            crate::mllp::write_frame(&mut tls, &received)
                .await
                .expect("écriture de trame MLLP sur flux TLS");
        });

        let provider = Arc::new(rustls::crypto::ring::default_provider());
        let client_config = client_config_with_cert(provider, client_cert, client_key);
        let connector = TlsConnector::from(Arc::new(client_config));
        let tcp = TcpStream::connect(addr)
            .await
            .expect("connexion TCP client");
        let server_name =
            rustls_pki_types::ServerName::try_from("nubia-server").expect("nom de serveur valide");
        let mut client_tls = connector
            .connect(server_name, tcp)
            .await
            .expect("handshake mTLS côté client réussi");

        crate::mllp::write_frame(&mut client_tls, &payload)
            .await
            .expect("écriture de trame MLLP côté client");
        let echoed =
            crate::mllp::read_frame(&mut client_tls, crate::mllp::MllpReadOptions::default())
                .await
                .expect("lecture de la trame renvoyée par le serveur");

        assert_eq!(echoed, payload);
        server_task.await.expect("tâche serveur terminée");
    }
}
