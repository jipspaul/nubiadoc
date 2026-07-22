//! Routes documents + messagerie patient. Extrait de `lib.rs::build_router` (refactor taille).

use axum::{routing::get, Router};

use crate::{documents, messaging, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/documents",
            get(documents::list_documents).post(documents::upload_document),
        )
        .route("/v1/documents/:id", get(documents::get_document))
        .route(
            "/v1/documents/:id/download",
            get(documents::download_document),
        )
        .route(
            "/v1/conversations",
            get(messaging::list_conversations).post(messaging::create_conversation),
        )
        .route(
            "/v1/conversations/:id/messages",
            get(messaging::get_conversation_messages).post(messaging::send_message),
        )
        .route(
            "/v1/conversations/:id/read",
            axum::routing::post(messaging::mark_conversation_read),
        )
}
