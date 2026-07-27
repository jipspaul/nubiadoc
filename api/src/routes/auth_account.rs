//! Routes auth + compte pro/patient. Extrait de `lib.rs::build_router` (refactor taille).

use axum::{
    routing::{get, patch, post, put},
    Router,
};

use crate::{auth, medical_questionnaire, pharmacy, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route("/v1/auth/register", post(auth::register::register))
        .route("/v1/auth/login", post(auth::login::login))
        .route("/v1/auth/refresh", post(auth::refresh::refresh))
        .route("/v1/auth/logout", post(auth::logout::logout))
        .route(
            "/v1/auth/select-context",
            post(auth::select_context::select_context),
        )
        .route(
            "/v1/auth/select-pharmacy-context",
            post(auth::select_pharmacy_context::select_pharmacy_context),
        )
        .route(
            "/v1/pharmacies",
            get(pharmacy::directory::search_pharmacies),
        )
        .route("/v1/auth/mfa/enroll", post(auth::mfa_enroll::mfa_enroll))
        .route("/v1/auth/mfa/verify", post(auth::mfa_verify::mfa_verify))
        .route(
            "/v1/auth/password/forgot",
            post(auth::forgot_password::forgot_password),
        )
        .route(
            "/v1/auth/password/reset",
            post(auth::reset_password::reset_password),
        )
        .route("/v1/me", get(auth::me))
        .route("/v1/pro/register", post(auth::pro_register))
        .route(
            "/v1/pro/verification",
            get(auth::get_pro_verification).post(auth::pro_verification),
        )
        .route(
            "/v1/cabinet",
            get(auth::get_cabinet).patch(auth::patch_cabinet),
        )
        .route("/v1/cabinet/provider", patch(auth::patch_cabinet_provider))
        .route(
            "/v1/cabinet/provider/listing",
            put(auth::put_cabinet_provider_listing),
        )
        .route(
            "/v1/cabinet/members",
            get(auth::get_cabinet_members).post(auth::post_cabinet_members),
        )
        .route(
            "/v1/cabinet/members/:user_id",
            patch(auth::patch_cabinet_member).delete(auth::delete_cabinet_member),
        )
        .route(
            "/v1/account",
            get(auth::get_account).patch(auth::patch_account),
        )
        .route(
            "/v1/account/coverage",
            get(auth::get_account_coverage).patch(auth::patch_account_coverage),
        )
        .route("/v1/account/coverage/card", post(auth::post_coverage_card))
        .route(
            "/v1/account/medical-questionnaire",
            get(medical_questionnaire::get_medical_questionnaire)
                .post(medical_questionnaire::create_medical_questionnaire)
                .patch(medical_questionnaire::patch_medical_questionnaire),
        )
        .route(
            "/v1/account/referring-doctor",
            get(auth::get_account_referring_doctor)
                .put(auth::put_account_referring_doctor)
                .delete(auth::delete_account_referring_doctor),
        )
        .route(
            "/v1/account/notification-preferences",
            get(auth::get_account_notification_preferences)
                .patch(auth::patch_account_notification_preferences),
        )
        .route(
            "/v1/account/dependents",
            get(auth::get_account_dependents).post(auth::post_account_dependents),
        )
        .route(
            "/v1/account/dependents/:id",
            get(auth::get_account_dependent_by_id)
                .patch(auth::patch_account_dependent)
                .delete(auth::delete_account_dependent),
        )
}
