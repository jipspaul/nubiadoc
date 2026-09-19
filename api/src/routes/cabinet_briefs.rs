//! Routes briefs du cabinet (#7192) — jour/semaine/prothèses à poser, JSON +
//! export PDF.

use axum::{routing::get, Router};

use crate::{cabinet_briefs, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route("/v1/cabinet/briefs/day", get(cabinet_briefs::day_brief))
        .route(
            "/v1/cabinet/briefs/day.pdf",
            get(cabinet_briefs::day_brief_pdf),
        )
        .route("/v1/cabinet/briefs/week", get(cabinet_briefs::week_brief))
        .route(
            "/v1/cabinet/briefs/week.pdf",
            get(cabinet_briefs::week_brief_pdf),
        )
        .route(
            "/v1/cabinet/briefs/prostheses",
            get(cabinet_briefs::prostheses_brief),
        )
        .route(
            "/v1/cabinet/briefs/prostheses.pdf",
            get(cabinet_briefs::prostheses_brief_pdf),
        )
}
