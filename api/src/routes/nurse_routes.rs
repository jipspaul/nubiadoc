//! Routes du domaine infirmier (soins à domicile, app « type Uber » v1).
//! Extrait de `lib.rs::build_router` (refactor taille, cf. pharmacy_routes).
//!
//! Slice 1 : annuaire public + profil/disponibilité. Le cycle de vie des
//! demandes de visite (patient create/fan-out, offres infirmière, accept,
//! transitions) est ajouté dans la slice suivante.

use axum::{
    routing::{get, patch},
    Router,
};

use crate::{nurse, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route("/v1/search/nurses", get(nurse::directory::search_nurses))
        .route("/v1/nurse/profile", get(nurse::profile::get_nurse_profile))
        .route(
            "/v1/nurse/availability",
            patch(nurse::profile::patch_nurse_availability),
        )
}
