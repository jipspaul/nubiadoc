//! Routes agenda/planning cabinet. Extrait de `lib.rs::build_router` (refactor taille).

use axum::{
    routing::{delete, get, patch, post, put},
    Router,
};

use crate::{
    appointment_motifs, appointment_series, appointments_checkin, provider_unavailability,
    scheduling, AppState,
};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route("/v1/cabinet/agenda", get(scheduling::get_cabinet_agenda))
        .route(
            "/v1/cabinet/waiting-room",
            get(scheduling::get_waiting_room),
        )
        .route(
            "/v1/cabinet/appointments",
            get(scheduling::get_cabinet_appointments).post(scheduling::create_cabinet_appointment),
        )
        .route(
            "/v1/cabinet/appointments/series",
            post(appointment_series::create_appointment_series),
        )
        .route(
            "/v1/cabinet/appointments/:id/confirm",
            post(scheduling::confirm_appointment),
        )
        .route(
            "/v1/cabinet/appointments/:id/checkin",
            post(appointments_checkin::cabinet_checkin_appointment),
        )
        .route(
            "/v1/cabinet/appointments/:id/start",
            post(scheduling::start_consultation),
        )
        .route(
            "/v1/cabinet/appointments/:id/no-show",
            post(scheduling::no_show_appointment),
        )
        .route(
            "/v1/cabinet/appointments/:id",
            patch(scheduling::patch_cabinet_appointment),
        )
        .route(
            "/v1/cabinet/waiting-room/call-next",
            post(scheduling::call_next_patient),
        )
        .route(
            "/v1/cabinet/appointment-motifs",
            get(appointment_motifs::list_appointment_motifs)
                .post(appointment_motifs::create_appointment_motif),
        )
        .route(
            "/v1/cabinet/appointment-motifs/:id",
            patch(appointment_motifs::update_appointment_motif)
                .delete(appointment_motifs::delete_appointment_motif),
        )
        .route(
            "/v1/cabinet/waiting-list",
            get(scheduling::get_waiting_list),
        )
        .route(
            "/v1/cabinet/waiting-list/:id/offer",
            post(scheduling::offer_waiting_list_slot),
        )
        .route(
            "/v1/cabinet/slots",
            get(scheduling::list_cabinet_slots).post(scheduling::create_cabinet_slot),
        )
        .route(
            "/v1/cabinet/slots/:id",
            patch(scheduling::patch_cabinet_slot).delete(scheduling::delete_cabinet_slot),
        )
        .route(
            "/v1/cabinet/slots/:id/online",
            put(scheduling::put_cabinet_slot_online),
        )
        .route(
            "/v1/cabinet/unavailability",
            get(provider_unavailability::list_unavailability)
                .post(provider_unavailability::create_unavailability),
        )
        .route(
            "/v1/cabinet/unavailability/:id",
            delete(provider_unavailability::delete_unavailability),
        )
}
