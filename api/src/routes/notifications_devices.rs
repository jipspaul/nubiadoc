//! Routes avatar/consentements/passeport implantaire/devices/notifications/rappels.
//! Extrait de `lib.rs::build_router` (refactor taille).

use axum::{routing::get, Router};

use crate::{
    auth, devices, implant_passport, notifications, recall_campaigns, reminders, AppState,
};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/account/avatar",
            get(auth::get_account_avatar).put(auth::put_account_avatar),
        )
        .route("/v1/account/consents", get(auth::get_account_consents))
        .route(
            "/v1/account/consents/:purpose",
            axum::routing::put(auth::put_account_consent),
        )
        .route(
            "/v1/implant-passport",
            get(implant_passport::list_implant_passport),
        )
        .route(
            "/v1/implant-passport/export",
            get(implant_passport::export_implant_passport),
        )
        .route("/v1/devices", axum::routing::post(devices::register_device))
        // Alias BR10 : le front appelle `/v1/device-tokens` → même handler.
        .route(
            "/v1/device-tokens",
            axum::routing::post(devices::register_device),
        )
        .route(
            "/v1/devices/:token",
            axum::routing::delete(devices::unregister_device),
        )
        .route("/v1/notifications", get(notifications::list_notifications))
        .route(
            "/v1/me/notification-preferences",
            get(notifications::get_me_notification_preferences)
                .patch(notifications::patch_me_notification_preferences),
        )
        .route(
            "/v1/notifications/read-all",
            axum::routing::post(notifications::mark_all_notifications_read),
        )
        .route(
            "/v1/notifications/:id/read",
            axum::routing::post(notifications::mark_notification_read),
        )
        .route("/v1/reminders", get(reminders::list_reminders))
        .route(
            "/v1/cabinet/recall-campaigns",
            axum::routing::post(recall_campaigns::create_recall_campaign),
        )
}
