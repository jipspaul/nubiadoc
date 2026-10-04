//! Régression #6920 : un `POST` mal adressé (404 route inexistante, 405
//! méthode non supportée) avec un corps > 32 KiB ne doit plus faire tomber
//! la connexion — sinon un reverse-proxy (Caddy) la voit comme une panne
//! amont et répond 502 à la place de la vraie réponse 404/405 de l'API.
//!
//! Test au niveau TCP brut (pas `tower::ServiceExt::oneshot`, qui court-
//! circuite la couche transport où se manifeste le bug) : on écrit tout le
//! corps avant de lire la réponse (comme Caddy), puis on réutilise la MÊME
//! connexion keep-alive pour une seconde requête — si le serveur avait
//! laissé tomber le corps non lu sans le draine, la connexion serait déjà
//! fermée/désynchronisée et cette seconde requête échouerait.

use nubia_api::{app, AppState, StubMailer};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

fn make_app() -> axum::Router {
    let db = sqlx::PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: "test-drain-unread-body-secret".into(),
        mailer: Arc::new(StubMailer),
    };
    app(state)
}

async fn spawn_server() -> std::net::SocketAddr {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, make_app()).await.unwrap();
    });
    addr
}

/// Écrit une requête `POST <path>` avec un corps de `body_len` octets, lit la
/// réponse jusqu'à la fin des en-têtes + son corps (`Content-Length`), puis
/// renvoie `(status_line, stream)` pour permettre de rejouer une requête sur
/// la même connexion.
async fn post_large_body_and_read_response(
    stream: &mut TcpStream,
    path: &str,
    body_len: usize,
) -> String {
    let body = vec![b'A'; body_len];
    let request = format!(
        "POST {path} HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/octet-stream\r\nContent-Length: {body_len}\r\nConnection: keep-alive\r\n\r\n"
    );
    stream.write_all(request.as_bytes()).await.unwrap();
    stream.write_all(&body).await.unwrap();

    read_response_status_and_drain(stream).await
}

async fn read_response_status_and_drain(stream: &mut TcpStream) -> String {
    let mut buf = Vec::new();
    let mut chunk = [0u8; 4096];
    let headers_end = loop {
        let n = stream.read(&mut chunk).await.unwrap();
        assert!(n > 0, "connexion fermée avant la fin des en-têtes");
        buf.extend_from_slice(&chunk[..n]);
        if let Some(pos) = find_headers_end(&buf) {
            break pos;
        }
    };
    let header_str = String::from_utf8_lossy(&buf[..headers_end]).to_string();
    let status_line = header_str.lines().next().unwrap().to_string();

    let content_length: usize = header_str
        .lines()
        .find_map(|l| l.to_lowercase().strip_prefix("content-length:").map(str::trim).map(str::to_string))
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);

    let mut body_read = buf.len() - (headers_end + 4);
    while body_read < content_length {
        let n = stream.read(&mut chunk).await.unwrap();
        assert!(n > 0, "connexion fermée avant la fin du corps de la réponse");
        body_read += n;
    }

    status_line
}

fn find_headers_end(buf: &[u8]) -> Option<usize> {
    buf.windows(4).position(|w| w == b"\r\n\r\n")
}

#[tokio::test]
async fn post_oversized_body_to_unknown_route_stays_404_and_keeps_connection_alive() {
    let addr = spawn_server().await;
    let mut stream = TcpStream::connect(addr).await.unwrap();

    let status = post_large_body_and_read_response(&mut stream, "/v1/pas-une-route-qa65", 65_008).await;
    assert!(status.contains("404"), "status inattendu: {status}");

    // La connexion doit être réutilisable (le corps a été drainé, pas de
    // RST/fermeture en cours de route) : une seconde requête sur le même
    // socket doit aboutir à une réponse HTTP valide.
    let status2 = post_large_body_and_read_response(&mut stream, "/v1/pas-une-route-qa65", 1_008).await;
    assert!(status2.contains("404"), "status inattendu sur la 2e requête: {status2}");
}

#[tokio::test]
async fn post_oversized_body_to_method_mismatch_route_stays_405_and_keeps_connection_alive() {
    let addr = spawn_server().await;
    let mut stream = TcpStream::connect(addr).await.unwrap();

    let status = post_large_body_and_read_response(&mut stream, "/v1/me", 65_008).await;
    assert!(status.contains("405"), "status inattendu: {status}");

    let status2 = post_large_body_and_read_response(&mut stream, "/v1/me", 1_008).await;
    assert!(status2.contains("405"), "status inattendu sur la 2e requête: {status2}");
}
