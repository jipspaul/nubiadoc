//! Routes rendez-vous patient. Extrait de `lib.rs::build_router` (refactor taille).

use axum::{routing::get, Router};

use crate::{appointments, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/appointments",
            get(appointments::list_appointments).post(appointments::create_appointment),
        )
        .route(
            "/v1/appointments/:id",
            get(appointments::get_appointment).patch(appointments::patch_appointment),
        )
        .route(
            "/v1/appointments/:id/cancel",
            axum::routing::post(appointments::cancel_appointment),
        )
        .route(
            "/v1/appointments/:id/checkin",
            axum::routing::post(appointments::checkin_appointment),
        )
        .route(
            "/v1/appointments/:id/callback-request",
            axum::routing::post(appointments::callback_appointment),
        )
        .route(
            "/v1/appointments/:id/directions",
            get(appointments::get_appointment_directions),
        )
        .route(
            "/v1/appointments/:id/preparation",
            get(appointments::get_appointment_preparation),
        )
        .route(
            "/v1/appointments/:id/queue",
            get(appointments::get_appointment_queue),
        )
}
