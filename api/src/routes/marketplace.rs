//! Routes annuaire/recherche/réservation marketplace + avis + liste d'attente
//! patient. Extrait de `lib.rs::build_router` (refactor taille).

use axum::{routing::get, Router};

use crate::{
    bookings, cabinet_info, ccam_acts, marketplace, ngap_acts, practitioner_favorite_acts, reviews,
    waiting_list, AppState,
};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route("/v1/professions", get(marketplace::list_professions))
        .route("/v1/specialties", get(marketplace::list_specialties))
        .route("/v1/acts", get(marketplace::list_acts))
        .route("/v1/ccam/acts", get(ccam_acts::search_ccam_acts))
        .route(
            "/v1/cabinet/practitioners/me/favorite-acts",
            get(practitioner_favorite_acts::list_favorite_acts)
                .post(practitioner_favorite_acts::create_favorite_act),
        )
        .route(
            "/v1/cabinet/practitioners/me/favorite-acts/:ccam_code",
            axum::routing::delete(practitioner_favorite_acts::delete_favorite_act),
        )
        .route("/v1/ngap/acts", get(ngap_acts::search_ngap_acts))
        .route("/v1/search/suggest", get(marketplace::suggest_search))
        .route(
            "/v1/search/parse",
            axum::routing::post(marketplace::parse_search),
        )
        .route("/v1/search/providers", get(marketplace::search_providers))
        .route("/v1/search/slots", get(marketplace::search_slots))
        .route("/v1/providers/:id", get(marketplace::get_provider))
        .route(
            "/v1/providers/:id/availability",
            get(marketplace::get_provider_availability),
        )
        .route(
            "/v1/slots/:id/hold",
            axum::routing::post(marketplace::hold_slot),
        )
        .route(
            "/v1/bookings",
            axum::routing::post(bookings::create_booking),
        )
        .route("/v1/cabinets/:id/info", get(cabinet_info::get_cabinet_info))
        .route("/v1/reviews", axum::routing::post(reviews::create_review))
        .route(
            "/v1/providers/:id/reviews",
            get(reviews::list_provider_reviews),
        )
        .route("/v1/cabinet/reviews", get(reviews::list_cabinet_reviews))
        .route(
            "/v1/cabinet/reviews/:id",
            axum::routing::patch(reviews::moderate_review),
        )
        .route(
            "/v1/waiting-list",
            axum::routing::post(waiting_list::create_waiting_list_entry),
        )
        .route(
            "/v1/account/waiting-list",
            get(waiting_list::list_waiting_list_entries),
        )
        .route(
            "/v1/waiting-list/:id/cancel",
            axum::routing::post(waiting_list::cancel_waiting_list_entry),
        )
}
