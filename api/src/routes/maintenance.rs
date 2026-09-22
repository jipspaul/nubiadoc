//! Routes équipements/tickets de maintenance du cabinet (#7167).

use axum::{routing::get, Router};

use crate::{maintenance, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/cabinet/equipment",
            get(maintenance::list_equipment).post(maintenance::create_equipment),
        )
        .route(
            "/v1/cabinet/equipment/:id",
            axum::routing::patch(maintenance::patch_equipment)
                .delete(maintenance::delete_equipment),
        )
        .route(
            "/v1/cabinet/maintenance/tickets",
            get(maintenance::list_tickets).post(maintenance::create_ticket),
        )
        .route(
            "/v1/cabinet/maintenance/tickets/:id",
            axum::routing::patch(maintenance::patch_ticket),
        )
        .route(
            "/v1/cabinet/maintenance/tickets/:id/photos",
            get(maintenance::list_ticket_photos),
        )
        .route(
            "/v1/cabinet/maintenance/photos",
            axum::routing::post(maintenance::upload_maintenance_photo),
        )
        .route(
            "/v1/cabinet/maintenance/stats",
            get(maintenance::get_maintenance_stats),
        )
}
