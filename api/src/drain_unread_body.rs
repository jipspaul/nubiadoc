//! #6920 : un `POST`/`PATCH`/`PUT` adressé à une route inexistante (404, via
//! le fallback du `Router`) ou à une méthode non supportée (405, via le
//! fallback par défaut du `MethodRouter` — `api/src/lib.rs::build_router`
//! monte 132 routes d'écriture, aucune ne lit le corps dans ces deux cas) ne
//! traverse jamais d'extracteur `Json<…>` : le corps de la requête n'est
//! jamais lu. Passé ~32 KiB, hyper réinitialise le flux HTTP/2 restant avant
//! que Caddy ait fini d'envoyer, et Caddy traduit ça en `502` à corps vide
//! (la vraie réponse 404/405 de l'API n'est jamais vue par le client — cf.
//! `via`/`allow` absents de la réponse observée dans l'issue).
//!
//! On ne peut pas corriger ça en inspectant le statut de la réponse après
//! coup : quand `axum` décide de répondre sans lire le corps, celui-ci est
//! déjà abandonné (donc le flux déjà réinitialisé) avant qu'on reprenne la
//! main. La seule option est d'intercepter l'abandon lui-même : on remplace
//! le corps entrant par ce wrapper, qui, s'il est détruit sans avoir été lu
//! jusqu'au bout, le draine en tâche de fond au lieu de le laisser tomber —
//! borné en temps pour ne pas transformer un client malveillant qui n'envoie
//! jamais la fin du corps en fuite de tâches.

use axum::body::{Bytes, HttpBody};
use axum::extract::Request;
use axum::middleware::Next;
use axum::response::Response;
use http_body::{Frame, SizeHint};
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::Duration;

const DRAIN_TIMEOUT: Duration = Duration::from_secs(5);

pub async fn drain_unread_body(request: Request, next: Next) -> Response {
    let (parts, body) = request.into_parts();
    let body = axum::body::Body::new(DrainOnDrop(Some(body)));
    next.run(Request::from_parts(parts, body)).await
}

/// Enveloppe un `Body` : identique en tout point tant qu'il est lu
/// normalement, mais draine le reste en arrière-plan si on le détruit avant
/// la fin du flux plutôt que de simplement le laisser tomber.
struct DrainOnDrop(Option<axum::body::Body>);

impl HttpBody for DrainOnDrop {
    type Data = Bytes;
    type Error = axum::Error;

    fn poll_frame(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
    ) -> Poll<Option<Result<Frame<Self::Data>, Self::Error>>> {
        let this = self.get_mut();
        let Some(inner) = this.0.as_mut() else {
            return Poll::Ready(None);
        };
        let poll = Pin::new(inner).poll_frame(cx);
        if let Poll::Ready(None) = poll {
            // Flux entièrement lu par la voie normale : rien à draine au `Drop`.
            this.0 = None;
        }
        poll
    }

    fn is_end_stream(&self) -> bool {
        self.0.as_ref().is_none_or(HttpBody::is_end_stream)
    }

    fn size_hint(&self) -> SizeHint {
        self.0.as_ref().map_or_else(SizeHint::default, HttpBody::size_hint)
    }
}

impl Drop for DrainOnDrop {
    fn drop(&mut self) {
        let Some(mut body) = self.0.take() else {
            return;
        };
        tokio::spawn(async move {
            let _ = tokio::time::timeout(DRAIN_TIMEOUT, async {
                loop {
                    let frame =
                        std::future::poll_fn(|cx| Pin::new(&mut body).poll_frame(cx)).await;
                    match frame {
                        Some(Ok(_)) => continue,
                        _ => break,
                    }
                }
            })
            .await;
        });
    }
}
