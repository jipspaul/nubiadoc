//! Handlers `GET/PUT /v1/me/dashboard-layout` — préférence de mise en page du
//! dashboard par utilisateur (liste ordonnée de widgets visibles), par app et
//! par rôle, avec valeurs par défaut. Même schéma d'auth/RLS que les
//! préférences de notification (`notifications.rs::get_me_notification_preferences`).

use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use crate::{
    auth::{AppError, MeClaims},
    AppState,
};

/// Catalogue des identifiants de widgets valides pour une `app` donnée
/// (`claims.kind` : `patient`/`pro`/`pharma`/`nurse`). Sert à la fois de
/// validation en écriture et de source pour les défauts.
fn known_widgets(app: &str) -> &'static [&'static str] {
    match app {
        "patient" => &[
            "next_appointment",
            "todo",
            "treatment_progress",
            "quick_access",
            "messages",
            "documents",
        ],
        "pro" => &[
            "kpi_tiles",
            "next_patient",
            "today_schedule",
            "pending_actions",
            "prostheses_today",
            "today_notes",
            "week_summary",
            "opportunities",
        ],
        "pharma" => &["orders_today", "quotes_pending", "stock_alerts"],
        "nurse" => &["visits_today", "visit_requests"],
        _ => &[],
    }
}

/// Widgets visibles par défaut avant toute personnalisation, par app et par
/// rôle — un `secretary` n'a pas les mêmes priorités qu'un `practitioner`
/// dans l'app `pro`.
fn default_widgets(app: &str, role: Option<&str>) -> Vec<String> {
    let ids: &[&str] = match (app, role) {
        ("patient", _) => &[
            "next_appointment",
            "todo",
            "treatment_progress",
            "quick_access",
        ],
        ("pro", Some("secretary")) => &[
            "today_schedule",
            "pending_actions",
            "opportunities",
            "today_notes",
        ],
        ("pro", _) => &[
            "kpi_tiles",
            "next_patient",
            "today_schedule",
            "pending_actions",
            "prostheses_today",
            "today_notes",
        ],
        ("pharma", _) => &["orders_today", "quotes_pending", "stock_alerts"],
        ("nurse", _) => &["visits_today", "visit_requests"],
        _ => &[],
    };
    ids.iter().map(|s| s.to_string()).collect()
}

/// Réponse de `GET/PUT /v1/me/dashboard-layout`.
#[derive(Serialize)]
pub struct MeDashboardLayoutResponse {
    pub widgets: Vec<String>,
}

/// `GET /v1/me/dashboard-layout` — layout courant du porteur du token.
///
/// Si aucune ligne dans `user_dashboard_layout` → défauts (`default_widgets`,
/// selon `claims.kind`/`claims.role`). RLS scoped par `app.current_user_id`
/// (migration 0293).
pub async fn get_me_dashboard_layout(
    State(state): State<AppState>,
    claims: MeClaims,
) -> Result<Json<MeDashboardLayoutResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row =
        sqlx::query("SELECT layout FROM user_dashboard_layout WHERE app_user_id = $1 AND app = $2")
            .bind(claims.sub)
            .bind(&claims.kind)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let widgets = match row {
        Some(r) => {
            let layout: serde_json::Value = r.try_get("layout").map_err(|_| AppError::Internal)?;
            serde_json::from_value(layout).map_err(|_| AppError::Internal)?
        }
        None => default_widgets(&claims.kind, claims.role.as_deref()),
    };

    tracing::info!(user_id = %claims.sub, app = %claims.kind, "dashboard layout queried");

    Ok(Json(MeDashboardLayoutResponse { widgets }))
}

/// Corps de la requête `PUT /v1/me/dashboard-layout`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PutMeDashboardLayoutBody {
    widgets: Vec<String>,
}

/// `PUT /v1/me/dashboard-layout` — remplace le layout du porteur du token.
///
/// Chaque identifiant de `widgets` doit appartenir au catalogue de l'app du
/// token (`claims.kind`), sans doublon — sinon `422 ValidationError`.
/// Upsert (une ligne par `(app_user_id, app)`). RLS scoped par
/// `app.current_user_id` (migration 0293).
pub async fn put_me_dashboard_layout(
    State(state): State<AppState>,
    claims: MeClaims,
    Json(body): Json<PutMeDashboardLayoutBody>,
) -> Result<Json<MeDashboardLayoutResponse>, AppError> {
    let catalog = known_widgets(&claims.kind);
    if catalog.is_empty() {
        return Err(AppError::ValidationError);
    }

    let mut seen = std::collections::HashSet::with_capacity(body.widgets.len());
    for widget_id in &body.widgets {
        if !catalog.contains(&widget_id.as_str()) || !seen.insert(widget_id.as_str()) {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO user_dashboard_layout (app_user_id, app, layout) \
         VALUES ($1, $2, $3) \
         ON CONFLICT (app_user_id, app) \
         DO UPDATE SET layout = $3, updated_at = now()",
    )
    .bind(claims.sub)
    .bind(&claims.kind)
    .bind(serde_json::json!(body.widgets))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(user_id = %claims.sub, app = %claims.kind, "dashboard layout updated");

    Ok(Json(MeDashboardLayoutResponse {
        widgets: body.widgets,
    }))
}

#[cfg(test)]
mod tests {
    use super::{default_widgets, known_widgets};

    #[test]
    fn known_widgets_is_empty_for_unknown_app() {
        assert!(known_widgets("unknown").is_empty());
    }

    #[test]
    fn default_widgets_differ_by_role_for_pro_app() {
        let practitioner_default = default_widgets("pro", Some("practitioner"));
        let secretary_default = default_widgets("pro", Some("secretary"));
        assert_ne!(practitioner_default, secretary_default);
        assert!(practitioner_default.contains(&"kpi_tiles".to_string()));
        assert!(secretary_default.contains(&"today_schedule".to_string()));
    }

    #[test]
    fn default_widgets_are_all_in_the_app_catalog() {
        for app in ["patient", "pro", "pharma", "nurse"] {
            let catalog = known_widgets(app);
            for widget_id in default_widgets(app, None) {
                assert!(
                    catalog.contains(&widget_id.as_str()),
                    "{widget_id} absent du catalogue de {app}"
                );
            }
        }
    }

    #[test]
    fn default_widgets_is_empty_for_unknown_app() {
        assert!(default_widgets("unknown", None).is_empty());
    }
}
