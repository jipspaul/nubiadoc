//! Routes tâches internes du cabinet (#7211). Le raccourci
//! `POST /v1/appointments/:id/tasks` vit ici aussi (même module handler,
//! `cabinet_tasks::create_appointment_task`) bien que son préfixe soit
//! `/v1/appointments` : regroupé avec le reste de la feature tâches plutôt
//! qu'avec `routes/appointments.rs` (routes patient `PatientAccountClaims`),
//! puisque ce raccourci est un accès staff `ProSecretaryPlusClaims`.

use axum::{routing::get, Router};

use crate::{cabinet_tasks, AppState};

pub fn add(router: Router<AppState>) -> Router<AppState> {
    router
        .route(
            "/v1/cabinet/tasks",
            get(cabinet_tasks::list_cabinet_tasks).post(cabinet_tasks::create_cabinet_task),
        )
        .route(
            "/v1/cabinet/tasks/:id",
            axum::routing::patch(cabinet_tasks::patch_cabinet_task),
        )
        .route(
            "/v1/cabinet/tasks/:id/complete",
            axum::routing::post(cabinet_tasks::complete_cabinet_task),
        )
        .route(
            "/v1/appointments/:id/tasks",
            axum::routing::post(cabinet_tasks::create_appointment_task),
        )
}
