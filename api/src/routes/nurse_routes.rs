//! Routes du domaine infirmier (soins à domicile, app « type Uber » v1).
//! Extrait de `lib.rs::build_router` (refactor taille, cf. pharmacy_routes).

use axum::{
    routing::{get, patch, post},
    Router,
};

use crate::{nurse, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        // Annuaire + profil / disponibilité (slice 1).
        .route("/v1/search/nurses", get(nurse::directory::search_nurses))
        .route(
            "/v1/nurse/memberships",
            get(nurse::profile::list_nurse_memberships),
        )
        .route("/v1/nurse/profile", get(nurse::profile::get_nurse_profile))
        .route(
            "/v1/nurse/availability",
            patch(nurse::profile::patch_nurse_availability),
        )
        // Demandes de visite — côté patient.
        .route(
            "/v1/account/visit-requests",
            get(nurse::requests::list_account_visit_requests)
                .post(nurse::requests::create_visit_request),
        )
        .route(
            "/v1/account/visit-requests/estimate",
            post(nurse::pricing::estimate_visit_price),
        )
        .route(
            "/v1/account/visit-requests/:id",
            get(nurse::requests::get_account_visit_request),
        )
        .route(
            "/v1/account/visit-requests/:id/cancel",
            post(nurse::requests::cancel_account_visit_request),
        )
        // Offres + cycle de visite — côté infirmière.
        .route("/v1/nurse/offers", get(nurse::visits::list_nurse_offers))
        .route("/v1/nurse/visits", get(nurse::visits::get_active_visit))
        .route(
            "/v1/nurse/offers/:id/decline",
            post(nurse::visits::decline_offer),
        )
        .route(
            "/v1/nurse/visits/:id/accept",
            post(nurse::visits::accept_visit),
        )
        .route(
            "/v1/nurse/visits/:id/en-route",
            post(nurse::visits::en_route_visit),
        )
        .route(
            "/v1/nurse/visits/:id/arrived",
            post(nurse::visits::arrived_visit),
        )
        .route("/v1/nurse/visits/:id/done", post(nurse::visits::done_visit))
}
