//! Routes rendez-vous patient. Extrait de `lib.rs::build_router` (refactor taille).

use axum::{routing::get, Router};

use crate::{
    appointments_actions, appointments_checkin, appointments_create, appointments_preparation,
    appointments_read, appointments_read_extras, consultation_clinique_read, AppState,
};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/appointments",
            get(appointments_read::list_appointments).post(appointments_create::create_appointment),
        )
        .route(
            "/v1/appointments/:id",
            get(appointments_read::get_appointment).patch(appointments_actions::patch_appointment),
        )
        .route(
            "/v1/appointments/:id/cancel",
            axum::routing::post(appointments_actions::cancel_appointment),
        )
        .route(
            "/v1/appointments/:id/checkin",
            axum::routing::post(appointments_checkin::checkin_appointment),
        )
        .route(
            "/v1/appointments/:id/callback-request",
            axum::routing::post(appointments_checkin::callback_appointment),
        )
        .route(
            "/v1/appointments/:id/directions",
            get(appointments_read_extras::get_appointment_directions),
        )
        .route(
            "/v1/appointments/:id/preparation",
            get(appointments_preparation::get_appointment_preparation),
        )
        .route(
            "/v1/appointments/:id/queue",
            get(appointments_read_extras::get_appointment_queue),
        )
        .route(
            "/v1/appointments/:id/consultation-clinique",
            get(consultation_clinique_read::get_patient_consultation_clinique),
        )
}
