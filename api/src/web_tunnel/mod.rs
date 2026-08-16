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

use axum::routing::get;
use axum::Router;

use crate::AppState;

pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/reservation/confirmer", get(confirm_page::confirm_page))
        .route("/:query_slug/:locality_slug", get(search_page::search_page))
        .route("/:slug", get(provider_page::provider_page))
        .with_state(state)
}
