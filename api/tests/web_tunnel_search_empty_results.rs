//! Test d'intégration — #6762 : `GET /:query_slug/:locality_slug` servait
//! une page « 0 praticien trouvé » en `index, follow` avec un canonical
//! auto-référent, alors qu'elle n'a aucun contenu propre à classer. Même
//! doctrine que `confirm_page` (`noindex, follow` : pas de contenu classable,
//! mais le maillage `.seo` reste suivi vers les pages voisines qui, elles,
//! ont des résultats).

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{web_tunnel, AppState, StubJobDispatcher, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-web-tunnel-search-empty";

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

async fn owner_pool() -> PgPool {
    let url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_owner@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

async fn tunnel() -> axum::Router {
    web_tunnel::router(
        AppState {
            db: app_pool().await,
            jwt_secret: JWT_SECRET.into(),
            mailer: Arc::new(StubMailer),
        },
        Arc::new(StubJobDispatcher),
    )
}

async fn body_text(response: axum::response::Response) -> String {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    String::from_utf8(bytes.to_vec()).unwrap()
}

async fn get(path: &str) -> axum::response::Response {
    tunnel()
        .await
        .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
        .await
        .unwrap()
}

/// Ville connue de `marketplace::KNOWN_CITY_COORDS` mais sans aucun
/// praticien inséré par ce test ni par le reste de la suite (vérifié : aucun
/// autre test n'y insère de provider) — reproduit le cas "ville réelle, 0
/// résultat" plutôt qu'une ville inconnue (déjà couverte par
/// `locality_not_found`, #7224).
#[tokio::test]
async fn search_page_with_zero_results_is_noindex_follow() {
    if !db_available() {
        return;
    }

    let response = get("/dentiste/strasbourg").await;
    assert_eq!(response.status(), StatusCode::OK);
    let html = body_text(response).await;
    assert!(
        html.contains(r#"<meta name="robots" content="noindex, follow">"#),
        "{html}"
    );
    assert!(
        html.contains("Aucun résultat pour cette recherche."),
        "{html}"
    );
}

/// Symétrique : dès qu'un praticien listé répond à la recherche, la page
/// garde le comportement par défaut `index, follow` (non régressé par #6762).
#[tokio::test]
async fn search_page_with_results_stays_index_follow() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();

    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet SEO Empty Test {suffix}"))
        .execute(&db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("seo-empty-pro-{suffix}@nubia.test"))
    .execute(&db)
    .await
    .unwrap();
    // Spécialité seedée « Omnipratique », rattachée à la profession
    // « Chirurgien-dentiste » — `q=dentiste` (requête émise par cette page
    // pour le query_slug `dentiste`) ne matche ni `display_name` ni le
    // libellé de spécialité, seulement celui de la profession jointe via
    // `specialty_id` (même fixture que
    // `search_providers_get::insert_provider_with_specialty`, #3417) ; sans
    // lui le provider restait invisible à la recherche et la page retombait
    // à tort en 0 résultat.
    let omnipratique_id: Uuid = "d2000000-0000-0000-0000-000000000001".parse().unwrap();
    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, user_id, display_name, specialty_id, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, $5, true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(user_id)
    .bind(format!("Dr SEO Empty {suffix}"))
    .bind(omnipratique_id)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "UPDATE provider SET geo = ST_SetSRID(ST_MakePoint(3.8767, 43.6108), 4326)::geography \
         WHERE id = $1",
    )
    .bind(provider_id)
    .execute(&db)
    .await
    .unwrap();

    let response = get("/dentiste/montpellier").await;
    assert_eq!(response.status(), StatusCode::OK);
    let html = body_text(response).await;
    assert!(
        html.contains(r#"<meta name="robots" content="index, follow">"#),
        "{html}"
    );

    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
}
