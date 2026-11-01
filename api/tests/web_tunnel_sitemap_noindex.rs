//! Test d'intégration — #8536 : `GET /sitemap.xml` déclarait les URLs
//! spécialité × localité (`static_urls`, `sitemap.rs`) sans jamais vérifier
//! qu'elles avaient un résultat, alors que `search_page` (#6762) pose
//! `noindex` dès que la recherche est vide — 42 % du sitemap observé en live
//! se contredisait avec la page qu'il référençait. Régression : toute URL
//! `/<spécialité>/<localité>` déclarée par le sitemap doit rester
//! `index, follow` sur la page qu'elle désigne.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{web_tunnel, AppState, StubJobDispatcher, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-web-tunnel-sitemap-noindex";

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

async fn get(app: &axum::Router, path: &str) -> axum::response::Response {
    app.clone()
        .oneshot(Request::builder().uri(path).body(Body::empty()).unwrap())
        .await
        .unwrap()
}

/// Chemins `/dentiste/...` ou `/orthodontiste/...` parmi les `<loc>` du
/// sitemap — pas les fiches praticien, qui ont leur propre doctrine
/// d'indexation.
fn static_specialty_paths(sitemap_xml: &str) -> Vec<String> {
    sitemap_xml
        .lines()
        .filter_map(|line| {
            let start = line.find("<loc>")? + "<loc>".len();
            let end = line.find("</loc>")?;
            Some(line[start..end].to_string())
        })
        .filter_map(|loc| {
            let path = format!("/{}", loc.splitn(4, '/').nth(3)?);
            (path.starts_with("/dentiste/") || path.starts_with("/orthodontiste/")).then_some(path)
        })
        .collect()
}

/// #8536 (CI) — root cause : la suite d'intégration ne seed pas de
/// praticien à Paris (`make reset migrate`, pas `make seed`, cf.
/// `rust-integration` dans `.forgejo/workflows/rust-ci.yml`) ; chaque test
/// qui a besoin de résultats de recherche insère sa propre fixture et la
/// nettoie ensuite (même pattern que
/// `web_tunnel_search_empty_results::search_page_with_results_stays_index_follow`).
/// Sans ce praticien, `has_results` (`sitemap.rs`) ne qualifiait AUCUNE paire
/// spécialité × localité et le test échouait sur son propre garde-fou
/// (`paths` vide) avant même d'atteindre la vérification de régression.
async fn insert_paris_dentiste_fixture(db: &PgPool, suffix: &str) -> Uuid {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Sitemap Noindex Test {suffix}"))
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("sitemap-noindex-pro-{suffix}@nubia.test"))
    .execute(db)
    .await
    .unwrap();
    // Spécialité seedée « Omnipratique », rattachée à la profession
    // « Chirurgien-dentiste » — même fixture que
    // `web_tunnel_search_empty_results::search_page_with_results_stays_index_follow`
    // (#3417) : `q=dentiste` ne matche que via le libellé de la profession
    // jointe, pas `display_name`/`specialty`.
    let omnipratique_id: Uuid = "d2000000-0000-0000-0000-000000000001".parse().unwrap();
    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, user_id, display_name, specialty_id, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, $5, true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(user_id)
    .bind(format!("Dr Sitemap Noindex {suffix}"))
    .bind(omnipratique_id)
    .execute(db)
    .await
    .unwrap();
    // Centre de Paris (`marketplace::KNOWN_CITY_COORDS`) : couvert à la fois
    // par le filtre `place=paris` (rayon 20 km) et par celui d'un
    // arrondissement proche (rayon 1 km) selon la localité testée.
    sqlx::query(
        "UPDATE provider SET geo = ST_SetSRID(ST_MakePoint(2.3522, 48.8566), 4326)::geography \
         WHERE id = $1",
    )
    .bind(provider_id)
    .execute(db)
    .await
    .unwrap();

    provider_id
}

#[tokio::test]
async fn sitemap_never_lists_a_specialty_locality_page_that_is_itself_noindex() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let provider_id = insert_paris_dentiste_fixture(&db, &suffix).await;

    let app = tunnel().await;

    let sitemap = body_text(get(&app, "/sitemap.xml").await).await;
    let paths = static_specialty_paths(&sitemap);
    assert!(
        !paths.is_empty(),
        "le sitemap devrait au moins déclarer /dentiste/paris"
    );

    for path in paths {
        let response = get(&app, &path).await;
        assert_eq!(response.status(), StatusCode::OK);
        let html = body_text(response).await;
        assert!(
            !html.contains(r#"content="noindex, follow""#),
            "{path} est déclarée indexable au sitemap mais se marque elle-même noindex"
        );
    }

    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
}
