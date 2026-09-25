//! Routes planning d'équipe / congés / pointage (DP-F27.b, #7144).

use axum::{
    routing::{get, patch, post},
    Router,
};

use crate::{staff, staff_leave, staff_timeclock, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/cabinet/staff/shifts",
            get(staff::list_shifts).post(staff::create_shift),
        )
        .route("/v1/cabinet/staff/shifts/pdf", get(staff::shifts_pdf))
        .route(
            "/v1/cabinet/staff/shifts/:id",
            patch(staff::patch_shift).delete(staff::delete_shift),
        )
        .route(
            "/v1/cabinet/staff/leave-requests",
            get(staff_leave::list_leave_requests).post(staff_leave::create_leave_request),
        )
        .route(
            "/v1/cabinet/staff/leave-requests/:id/decide",
            post(staff_leave::decide_leave_request),
        )
        .route(
            "/v1/cabinet/staff/leave-requests/:id/cancel",
            post(staff_leave::cancel_leave_request),
        )
        .route(
            "/v1/cabinet/staff/time-clock/code",
            get(staff_timeclock::time_clock_code),
        )
        .route(
            "/v1/cabinet/staff/time-clock/in",
            post(staff_timeclock::clock_in),
        )
        .route(
            "/v1/cabinet/staff/time-clock/out",
            post(staff_timeclock::clock_out),
        )
        .route(
            "/v1/cabinet/staff/time-clock/:id",
            patch(staff_timeclock::patch_time_clock_entry)
                .delete(staff_timeclock::delete_time_clock_entry),
        )
        .route(
            "/v1/cabinet/staff/time-clock",
            get(staff_timeclock::list_time_clock),
        )
}
