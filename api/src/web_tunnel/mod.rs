//! Pages publiques du tunnel de réservation (recherche, fiche, confirmation)
//! rendues en HTML côté serveur — #5356.
//!
//! Maquette `design/v2-screens/patient-web-tunnel-reservation.png` : « Une
//! application Flutter web est un canevas rendu côté client : le contenu
//! n'existe qu'après exécution du JS […] l'indexation par les moteurs de
//! recherche est au mieux partielle, souvent inexistante. » Ces 3 pages ne
//! peuvent donc pas vivre dans `front/apps/app_patient` (Flutter web) — voir
//! aussi #5355 (décision d'architecture : SSR, pas Flutter web).
//!
//! Routeur/port distincts de l'API versionnée `/v1/...`
//! (`api/AGENTS.md` règle 5 : « toute route [de l'API] monte sous `/v1/...`
//! ») — ces URL humaines (`/dentiste/paris-2e`) ne sont pas une API, elles
//! ne doivent PAS porter de préfixe de version. Même process/pool DB que
//! l'API (ADR-002/012 : monolithe modulaire, pas de second conteneur — même
//! pattern que le listener MLLP dans `main.rs`), et mêmes fonctions de
//! requête que l'API publique (`marketplace::search_providers`/
//! `get_provider`) : aucune logique métier dupliquée (#5355).

mod confirm_page;
mod html;
mod locality;
mod provider_page;
mod search_page;
mod slug;

use axum::extract::Request;
use axum::http::StatusCode;
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::Router;

use crate::AppState;

/// Les catch-all `/:slug` et `/:query_slug/:locality_slug` ci-dessous
/// capturent n'importe quel chemin à 1 ou 2 segments, y compris
/// `/v1/<inconnu>` (préfixe de l'API versionnée, cf. module doc) — un chemin
/// `/v1/...` sans route d'API correspondante doit répondre 404, pas être
/// rendu par le tunnel public (#6556).
async fn reject_v1_prefix(request: Request, next: Next) -> Response {
    let first_segment = request.uri().path().trim_start_matches('/').split('/').next();
    if first_segment == Some("v1") {
        return StatusCode::NOT_FOUND.into_response();
    }
    next.run(request).await
}

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/reservation/confirmer", get(confirm_page::confirm_page))
        .route("/:query_slug/:locality_slug", get(search_page::search_page))
        .route("/:slug", get(provider_page::provider_page))
        .route_layer(middleware::from_fn(reject_v1_prefix))
        .with_state(state)
}

#[cfg(test)]
mod tests {
    use axum::body::Body;
    use axum::http::{Request, StatusCode};
    use axum::routing::get;
    use axum::Router;
    use tower::ServiceExt;

    use super::reject_v1_prefix;

    async fn dummy() -> &'static str {
        "ok"
    }

    fn guarded_router() -> Router {
        Router::new()
            .route("/:query_slug/:locality_slug", get(dummy))
            .route("/:slug", get(dummy))
            .route_layer(axum::middleware::from_fn(reject_v1_prefix))
    }

    #[tokio::test]
    async fn rejects_two_segment_v1_paths_with_404() {
        for path in ["/v1/nonexistent", "/v1/queue", "/v1/patients"] {
            let response = guarded_router()
                .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::NOT_FOUND, "path: {path}");
        }
    }

    #[tokio::test]
    async fn rejects_one_segment_v1_path_with_404() {
        let response = guarded_router()
            .oneshot(Request::builder().uri("/v1").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn does_not_affect_legitimate_tunnel_paths() {
        let response = guarded_router()
            .oneshot(
                Request::builder()
                    .uri("/dentiste/paris-2e")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
    }
}
