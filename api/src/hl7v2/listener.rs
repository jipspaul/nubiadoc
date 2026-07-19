//! Lot B10 — intégration déploiement : câble le codec MLLP (B1-B4), la
//! terminaison mTLS (B5) et le dispatch (B7) sur un vrai `TcpListener`,
//! démarré comme second `tokio::task` dans le même binaire que l'API Axum
//! (cf. ADR-002, ADR-012 : monolithe modulaire, pas un second conteneur).
//!
//! Chargement des certificats depuis des fichiers PEM (chemins en variables
//! d'environnement) : c'était explicitement hors périmètre du lot B5
//! ("opérationnel/config, laissé à B10"), donc géré ici.
//!
//! Zéro `unwrap()`/`panic!()` dans la boucle de connexion : une connexion qui
//! échoue (handshake TLS, trame malformée, partenaire inconnu) est journalisée
//! et abandonnée, jamais un crash du listener entier. Les erreurs de
//! configuration au démarrage (fichiers de certs manquants/invalides) restent
//! des `.expect()` — même convention que le reste de `main.rs` pour les
//! erreurs de configuration irrécupérables au boot.

use std::io::BufReader;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use integrations_hl7v2::{
    accept_tls, build_acceptor, parse_bytes, peer_certificate_fingerprint, read_frame, write_frame,
    MllpReadOptions, MutualTlsConfig, ServerIdentity,
};
use rustls_pki_types::{CertificateDer, PrivateKeyDer};
use sqlx::PgPool;
use tokio::net::{TcpListener, TcpStream};
use tokio_rustls::TlsAcceptor;

use crate::hl7v2::dispatch::{dispatch, DispatchStatus};

/// Port MLLP par défaut (port IANA enregistré pour HL7).
const DEFAULT_MLLP_PORT: u16 = 2575;

/// État partagé exposé à la route de santé dédiée
/// (`GET /v1/interop/hl7v2/health`) — le healthcheck HTTP existant
/// (`/v1/health`) ne couvre que le serveur Axum, pas ce second listener TCP.
#[derive(Clone, Default)]
pub struct Hl7v2ListenerStatus {
    ready: Arc<AtomicBool>,
}

impl Hl7v2ListenerStatus {
    pub fn is_ready(&self) -> bool {
        self.ready.load(Ordering::Relaxed)
    }

    fn set_ready(&self) {
        self.ready.store(true, Ordering::Relaxed);
    }
}

fn load_certs(path: &Path) -> Vec<CertificateDer<'static>> {
    let file = std::fs::File::open(path)
        .unwrap_or_else(|e| panic!("MLLP: lecture du fichier de certificat {path:?} : {e}"));
    rustls_pemfile::certs(&mut BufReader::new(file))
        .collect::<Result<Vec<_>, _>>()
        .unwrap_or_else(|e| panic!("MLLP: parsing PEM du certificat {path:?} : {e}"))
}

fn load_private_key(path: &Path) -> PrivateKeyDer<'static> {
    let file = std::fs::File::open(path)
        .unwrap_or_else(|e| panic!("MLLP: lecture du fichier de clé privée {path:?} : {e}"));
    rustls_pemfile::private_key(&mut BufReader::new(file))
        .unwrap_or_else(|e| panic!("MLLP: parsing PEM de la clé privée {path:?} : {e}"))
        .unwrap_or_else(|| panic!("MLLP: aucune clé privée trouvée dans {path:?}"))
}

/// Construit la configuration mTLS depuis les fichiers PEM désignés par les
/// variables d'environnement `MLLP_TLS_CERT_PATH`, `MLLP_TLS_KEY_PATH`,
/// `MLLP_TLS_CLIENT_CA_PATH` (cette dernière peut contenir plusieurs CA
/// concaténées — un ou plusieurs partenaires, cf. modèle de confiance du
/// lot B5). Erreur de configuration au démarrage = `.expect()`, comme les
/// autres variables obligatoires de `main.rs`.
fn mtls_config_from_env() -> MutualTlsConfig {
    let cert_path = std::env::var("MLLP_TLS_CERT_PATH")
        .expect("MLLP_TLS_CERT_PATH doit être défini (chemin du certificat serveur MLLP)");
    let key_path = std::env::var("MLLP_TLS_KEY_PATH")
        .expect("MLLP_TLS_KEY_PATH doit être défini (chemin de la clé privée serveur MLLP)");
    let ca_path = std::env::var("MLLP_TLS_CLIENT_CA_PATH").expect(
        "MLLP_TLS_CLIENT_CA_PATH doit être défini (chemin du/des CA de confiance partenaires)",
    );

    MutualTlsConfig {
        server_identity: ServerIdentity {
            cert_chain: load_certs(Path::new(&cert_path)),
            private_key: load_private_key(Path::new(&key_path)),
        },
        trusted_client_cas: load_certs(Path::new(&ca_path)),
    }
}

/// Démarre le listener MLLP et ne retourne jamais en fonctionnement normal
/// (boucle d'acceptation infinie) — prévu pour être couru dans un
/// `tokio::select!` aux côtés de `axum::serve` (cf. `main.rs`).
///
/// Si les variables d'environnement TLS ne sont pas configurées, le listener
/// MLLP est **désactivé silencieusement** (pas de panique) plutôt que de
/// bloquer le démarrage de l'API sur une fonctionnalité encore optionnelle en
/// production — le healthcheck dédié reflète cet état (`ready = false` pour
/// toujours, jamais consulté si la fonctionnalité n'est pas déployée).
pub async fn serve(pool: PgPool, status: Hl7v2ListenerStatus) {
    let Ok(port) = std::env::var("MLLP_PORT")
        .ok()
        .map(|v| v.parse::<u16>())
        .transpose()
    else {
        tracing::error!("MLLP_PORT invalide (doit être un entier) — listener MLLP désactivé");
        return;
    };
    let port = port.unwrap_or(DEFAULT_MLLP_PORT);

    if std::env::var("MLLP_TLS_CERT_PATH").is_err() {
        tracing::info!(
            "MLLP_TLS_CERT_PATH absent — listener MLLP désactivé (fonctionnalité optionnelle)"
        );
        return;
    }

    let mtls_config = mtls_config_from_env();
    let acceptor = build_acceptor(mtls_config)
        .expect("MLLP: configuration mTLS invalide (certificats/CA malformés)");

    let bind = format!("0.0.0.0:{port}");
    let listener = TcpListener::bind(&bind)
        .await
        .unwrap_or_else(|e| panic!("MLLP: impossible de binder {bind} : {e}"));
    tracing::info!(addr = %bind, "listener MLLP démarré");
    status.set_ready();

    loop {
        let (stream, peer_addr) = match listener.accept().await {
            Ok(pair) => pair,
            Err(e) => {
                tracing::warn!(error = %e, "MLLP: échec d'acceptation TCP, connexion ignorée");
                continue;
            }
        };
        let acceptor = acceptor.clone();
        let pool = pool.clone();
        tokio::spawn(async move {
            handle_connection(acceptor, stream, pool, peer_addr).await;
        });
    }
}

/// Traite une connexion MLLP entière (poignée de main TLS, puis zéro ou
/// plusieurs messages jusqu'à fermeture de la connexion par le partenaire).
/// Ne panique jamais : toute erreur (handshake, trame, parsing) journalise et
/// termine seulement CETTE connexion, jamais le listener.
async fn handle_connection(
    acceptor: TlsAcceptor,
    stream: TcpStream,
    pool: PgPool,
    peer_addr: std::net::SocketAddr,
) {
    let mut tls_stream = match accept_tls(&acceptor, stream).await {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!(peer = %peer_addr, error = %e, "MLLP: échec de la poignée de main mTLS");
            return;
        }
    };

    let fingerprint = match peer_certificate_fingerprint(&tls_stream) {
        Ok(fp) => fp,
        Err(e) => {
            tracing::warn!(peer = %peer_addr, error = %e, "MLLP: extraction d'empreinte échouée");
            return;
        }
    };

    tracing::info!(peer = %peer_addr, fingerprint = %fingerprint, "MLLP: connexion mTLS établie");

    let read_options = MllpReadOptions::default();
    loop {
        let frame = match read_frame(&mut tls_stream, read_options).await {
            Ok(bytes) => bytes,
            Err(e) => {
                tracing::info!(peer = %peer_addr, error = %e, "MLLP: fin de connexion ou trame invalide");
                return;
            }
        };

        let message = match parse_bytes(&frame) {
            Ok(m) => m,
            Err(e) => {
                tracing::warn!(peer = %peer_addr, error = %e, "MLLP: message HL7 v2 illisible, connexion abandonnée");
                return;
            }
        };

        let outcome = dispatch(&pool, &fingerprint, &message).await;
        match &outcome.status {
            DispatchStatus::Accepted { cabinet_id, .. } => {
                tracing::info!(peer = %peer_addr, cabinet_id = %cabinet_id, "MLLP: message accepté");
            }
            DispatchStatus::Duplicate { cabinet_id, .. } => {
                tracing::info!(peer = %peer_addr, cabinet_id = %cabinet_id, "MLLP: message dupliqué (déjà traité)");
            }
            DispatchStatus::Rejected(reason) => {
                tracing::warn!(peer = %peer_addr, reason = ?reason, "MLLP: message rejeté");
            }
        }

        if let Err(e) = write_frame(&mut tls_stream, outcome.ack.as_bytes()).await {
            tracing::warn!(peer = %peer_addr, error = %e, "MLLP: échec d'écriture de l'ACK, connexion abandonnée");
            return;
        }

        // Respire un instant avant la prochaine lecture pour éviter une boucle
        // chaude si l'émetteur reste connecté sans jamais rien envoyer d'autre
        // (read_frame a déjà son propre timeout interne, ceci est une garde
        // supplémentaire contre un cas dégénéré rare : trames vides répétées).
        tokio::time::sleep(Duration::from_millis(0)).await;
    }
}
