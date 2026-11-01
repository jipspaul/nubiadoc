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

use nubia_api::{web_tunnel, AppState, StubJobDispatcher, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-web-tunnel-sitemap-noindex";

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
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

#[tokio::test]
async fn sitemap_never_lists_a_specialty_locality_page_that_is_itself_noindex() {
    if !db_available() {
        return;
    }
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
}
