//! Routes messagerie interne cabinet + support. Extrait de
//! `lib.rs::build_router` (refactor taille).

use axum::{routing::get, Router};

use crate::{
    cabinet_conversation_convert, cabinet_messaging, cabinet_team_messages, support, AppState,
};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/cabinet/conversations",
            get(cabinet_messaging::list_cabinet_conversations),
        )
        .route(
            "/v1/cabinet/conversations/:id/messages",
            get(cabinet_messaging::get_cabinet_conversation_messages)
                .post(cabinet_messaging::send_cabinet_message),
        )
        .route(
            "/v1/cabinet/conversations/:id/read",
            axum::routing::post(cabinet_messaging::mark_cabinet_conversation_read),
        )
        .route(
            "/v1/cabinet/conversations/:id/convert-to-appointment",
            axum::routing::post(cabinet_conversation_convert::convert_conversation_to_appointment),
        )
        .route(
            "/v1/support/conversations",
            axum::routing::post(support::open_support_conversation),
        )
        .route(
            "/v1/cabinet/messages",
            get(cabinet_team_messages::list_cabinet_team_messages)
                .post(cabinet_team_messages::send_cabinet_team_message),
        )
}
