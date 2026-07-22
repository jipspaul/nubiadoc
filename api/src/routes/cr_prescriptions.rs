//! Routes stérilisation, prescriptions, modèles de prescription/CR.
//! Extrait de `lib.rs::build_router` (refactor taille).

use axum::{routing::get, Router};

use crate::{
    cr_templates, lab_work_orders, prescription_renew, prescription_send, prescription_templates,
    prescriptions, sterilization, stock_items, AppState,
};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/cabinet/sterilization-cycles",
            get(sterilization::list_sterilization_cycles)
                .post(sterilization::create_sterilization_cycle),
        )
        .route(
            "/v1/cabinet/sterilization-cycles/:id/pouches",
            axum::routing::post(sterilization::add_sterilized_pouch),
        )
        .route(
            "/v1/cabinet/stock-items",
            get(stock_items::list_stock_items).post(stock_items::create_stock_item),
        )
        .route(
            "/v1/cabinet/stock-items/:id/movements",
            axum::routing::post(stock_items::add_stock_movement),
        )
        .route(
            "/v1/cabinet/prescriptions",
            axum::routing::post(prescriptions::create_prescription),
        )
        .route(
            "/v1/cabinet/prescriptions/:id",
            get(prescriptions::get_prescription),
        )
        .route(
            "/v1/cabinet/prescriptions/:id/sign",
            axum::routing::post(prescriptions::sign_prescription),
        )
        .route(
            "/v1/cabinet/prescriptions/:id/send",
            axum::routing::post(prescription_send::send_prescription),
        )
        .route(
            "/v1/cabinet/prescriptions/:id/renew",
            axum::routing::post(prescription_renew::renew_prescription),
        )
        .route(
            "/v1/cabinet/prescriptions/:id/apply-template",
            axum::routing::post(prescription_templates::apply_prescription_template),
        )
        .route(
            "/v1/cabinet/prescription-templates",
            get(prescription_templates::list_prescription_templates)
                .post(prescription_templates::create_prescription_template),
        )
        .route(
            "/v1/cabinet/cr-templates",
            get(cr_templates::list_cr_templates).post(cr_templates::create_cr_template),
        )
        .route(
            "/v1/cabinet/cr-templates/:id",
            axum::routing::patch(cr_templates::patch_cr_template)
                .delete(cr_templates::delete_cr_template),
        )
        .route(
            "/v1/cabinet/lab-work-orders",
            get(lab_work_orders::list_lab_work_orders).post(lab_work_orders::create_lab_work_order),
        )
        .route(
            "/v1/cabinet/lab-work-orders/:id",
            axum::routing::patch(lab_work_orders::patch_lab_work_order),
        )
}
