//! Tests d'intégration : `BrevoMailer` (#4035).
//!
//! Vérifie qu'un appel `send_invite`/`send_password_reset` déclenche
//! effectivement un POST vers l'API transactionnelle du provider (mock HTTP
//! wiremock — pas d'appel réseau vers l'API Brevo réelle).
//!
//! `Mailer::send_invite` est synchrone et fire-and-forget (l'envoi part dans
//! un `tokio::spawn` séparé) : un court délai après l'appel laisse le temps
//! à la requête HTTP mockée d'arriver avant de vérifier.

use nubia_api::{BrevoMailer, Mailer};
use serde_json::Value;
use wiremock::matchers::{header, method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

async fn wait_for_request() {
    tokio::time::sleep(std::time::Duration::from_millis(300)).await;
}

#[tokio::test]
async fn send_invite_posts_to_brevo_transactional_api() {
    let mock_server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/v3/smtp/email"))
        .and(header("api-key", "test-brevo-key"))
        .respond_with(ResponseTemplate::new(201))
        .expect(1)
        .mount(&mock_server)
        .await;

    let mailer = BrevoMailer::with_base_url(
        "test-brevo-key",
        "no-reply@nubia.test",
        "Nubia Test",
        "https://app.nubia.test",
        mock_server.uri(),
    );

    mailer.send_invite("collaborateur@nubia.test", "raw-invite-token-123");
    wait_for_request().await;

    let requests = mock_server.received_requests().await.unwrap();
    assert_eq!(requests.len(), 1, "un seul POST attendu vers l'API Brevo");

    let body: Value = serde_json::from_slice(&requests[0].body).unwrap();
    assert_eq!(body["to"][0]["email"], "collaborateur@nubia.test");
    assert_eq!(body["sender"]["email"], "no-reply@nubia.test");
    let html = body["htmlContent"].as_str().unwrap();
    assert!(
        html.contains("raw-invite-token-123"),
        "le token d'invitation doit apparaître dans le lien envoyé"
    );
}

#[tokio::test]
async fn send_password_reset_posts_to_brevo_transactional_api() {
    let mock_server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/v3/smtp/email"))
        .respond_with(ResponseTemplate::new(201))
        .expect(1)
        .mount(&mock_server)
        .await;

    let mailer = BrevoMailer::with_base_url(
        "test-brevo-key",
        "no-reply@nubia.test",
        "Nubia Test",
        "https://app.nubia.test",
        mock_server.uri(),
    );

    mailer.send_password_reset("patient@nubia.test", "reset-token-456");
    wait_for_request().await;

    let requests = mock_server.received_requests().await.unwrap();
    assert_eq!(requests.len(), 1);

    let body: Value = serde_json::from_slice(&requests[0].body).unwrap();
    assert_eq!(body["to"][0]["email"], "patient@nubia.test");
    let html = body["htmlContent"].as_str().unwrap();
    assert!(html.contains("reset-token-456"));
}

/// Un échec HTTP (provider indisponible) ne doit jamais faire paniquer
/// l'appelant : `send_invite` est synchrone et ne peut pas propager d'erreur.
#[tokio::test]
async fn send_invite_does_not_panic_when_provider_unreachable() {
    // Aucun serveur mock démarré : le port choisi n'écoute rien.
    let mailer = BrevoMailer::with_base_url(
        "test-brevo-key",
        "no-reply@nubia.test",
        "Nubia Test",
        "https://app.nubia.test",
        "http://127.0.0.1:1".to_string(), // port réservé, jamais accepté
    );

    mailer.send_invite("collaborateur@nubia.test", "token");
    wait_for_request().await;
    // Si on arrive ici sans panic, le test passe.
}
