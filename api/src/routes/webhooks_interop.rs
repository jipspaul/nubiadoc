//! Routes webhooks (Stripe/Yousign/GoCardless) + interop FHIR.
//! Extrait de `lib.rs::build_router` (refactor taille).

use axum::{routing::get, Router};

use crate::{interop, webhooks, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/webhooks/stripe",
            axum::routing::post(webhooks::stripe::stripe_webhook),
        )
        .route(
            "/v1/webhooks/yousign",
            axum::routing::post(webhooks::yousign::yousign_webhook),
        )
        .route(
            "/v1/webhooks/gocardless",
            axum::routing::post(webhooks::gocardless::gocardless_webhook),
        )
        .route(
            "/v1/interop/oauth/token",
            axum::routing::post(interop::oauth::issue_token),
        )
        .route(
            "/v1/interop/fhir/metadata",
            get(interop::capability::capability_statement),
        )
        .route("/v1/interop/fhir/Slot/:id", get(interop::slot::get_slot))
        .route("/v1/interop/fhir/Slot", get(interop::slot::search_slots))
        .route(
            "/v1/interop/fhir/Schedule/:id",
            get(interop::slot::get_schedule),
        )
        .route(
            "/v1/interop/fhir/Practitioner",
            get(interop::directory::search_practitioners),
        )
        .route(
            "/v1/interop/fhir/Practitioner/:id",
            get(interop::directory::get_practitioner),
        )
        .route(
            "/v1/interop/fhir/Organization/:id",
            get(interop::directory::get_organization),
        )
        .route(
            "/v1/interop/fhir/Location/:id",
            get(interop::directory::get_location),
        )
        .route(
            "/v1/interop/fhir/Appointment",
            get(interop::appointment::search_appointments)
                .post(interop::appointment::create_appointment),
        )
        .route(
            "/v1/interop/fhir/Appointment/:id",
            get(interop::appointment::get_appointment)
                .patch(interop::appointment::update_appointment_status),
        )
        .route(
            "/v1/interop/fhir/Subscription",
            axum::routing::post(interop::subscription::create_subscription),
        )
        .route(
            "/v1/interop/fhir/Subscription/:id",
            get(interop::subscription::get_subscription),
        )
}
