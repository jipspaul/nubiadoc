//! Routes secrétariats cabinet. Extrait de `lib.rs::build_router` (refactor taille).

use axum::{routing::get, Router};

use crate::{cabinet_secretariats, provider_secretariat, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/cabinet/providers/:id/secretariats",
            get(provider_secretariat::get_provider_secretariats)
                .put(provider_secretariat::put_provider_secretariats),
        )
        .route(
            "/v1/cabinet/secretariats",
            get(cabinet_secretariats::list_secretariats)
                .post(cabinet_secretariats::create_secretariat),
        )
        .route(
            "/v1/cabinet/secretariats/:id",
            axum::routing::patch(cabinet_secretariats::patch_secretariat)
                .delete(cabinet_secretariats::delete_secretariat),
        )
        .route(
            "/v1/cabinet/secretariats/:id/members",
            axum::routing::post(cabinet_secretariats::add_secretariat_member),
        )
        .route(
            "/v1/cabinet/secretariats/:id/members/:user_id",
            axum::routing::delete(cabinet_secretariats::remove_secretariat_member),
        )
        .route(
            "/v1/cabinet/secretariats/:id/staff",
            axum::routing::post(cabinet_secretariats::provision_staff),
        )
}
