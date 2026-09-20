//! Routes conformité ARS/DMSM (#7170) : échéancier `compliance_item` et
//! déclarations `custom_device_declaration`.

use axum::{routing::get, Router};

use crate::{compliance, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/cabinet/compliance-items",
            get(compliance::list_compliance_items).post(compliance::create_compliance_item),
        )
        .route(
            "/v1/cabinet/compliance-items/:id",
            axum::routing::patch(compliance::patch_compliance_item)
                .delete(compliance::delete_compliance_item),
        )
        .route(
            "/v1/cabinet/compliance-items/:id/complete",
            axum::routing::post(compliance::complete_compliance_item),
        )
        .route(
            "/v1/patients/:id/custom-device-declarations",
            axum::routing::post(compliance::create_custom_device_declaration),
        )
}
