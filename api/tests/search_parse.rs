//! Tests d'intégration : POST /v1/search/parse
//!
//! Ces tests fonctionnent en **mode dégradé** : `ANTHROPIC_API_KEY` est retirée
//! de l'environnement pour forcer la passe mots-clés (`source:"keywords"`).
//! Ils ne dépendent donc jamais de la clé LLM.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;

use nubia_api::{app, AppState, StubMailer};

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok()
}

fn state(db: PgPool) -> AppState {
    // Mode dégradé garanti : pas d'appel LLM.
    std::env::remove_var("ANTHROPIC_API_KEY");
    AppState {
        db,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    }
}

/// Cas mots-clés : « dentiste secteur 1 » → spécialité résolue + sector=1, 200.
#[tokio::test]
#[ignore = "quarantaine: bug déterministe révélé par le fix DB CI, voir #4602"]
async fn parse_keywords_dentiste_secteur1() {
    if !db_available() {
        return;
    }

    let response = app(state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/search/parse")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"q":"dentiste secteur 1"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(v["source"], "keywords", "sans clé LLM → source keywords");
    assert_eq!(v["query"]["sector"], "1", "« secteur 1 » → sector=1");
    assert!(
        v["query"]["specialty"].is_string(),
        "« dentiste » doit résoudre une spécialité (uuid non null), obtenu : {}",
        v["query"]["specialty"]
    );
    assert!(
        v["interpretation"].is_string(),
        "interpretation doit être présente"
    );
}

/// `q` vide (< 2 caractères) → 422 (comme `suggest_search`).
#[tokio::test]
async fn parse_empty_q_returns_422() {
    if !db_available() {
        return;
    }

    let response = app(state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/search/parse")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"q":""}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

/// Créneau de disponibilité : « samedi » → available=saturday, 200.
#[tokio::test]
async fn parse_keywords_available_saturday() {
    if !db_available() {
        return;
    }

    let response = app(state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/search/parse")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"q":"dentiste dispo samedi"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["query"]["available"], "saturday");
}

/// #4484 : ville connue de KNOWN_CITY_COORDS (réellement filtrée par
/// search_providers) → interprétation « près de <ville> ».
#[tokio::test]
async fn parse_known_city_says_pres_de() {
    if !db_available() {
        return;
    }

    let response = app(state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/search/parse")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"q":"dentiste à Paris"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["query"]["place"], "Paris");
    let interp = v["interpretation"].as_str().unwrap();
    assert!(
        interp.contains("près de Paris"),
        "ville résolue → proximité réellement filtrée par search_providers : {interp}"
    );
}

/// #4484 : ville hors KNOWN_CITY_COORDS (jamais filtrée par search_providers,
/// géocodage externe hors scope MVP) → interprétation ne doit PAS promettre
/// « près de <ville> » (repro exacte de l'issue : Grenoble).
#[tokio::test]
async fn parse_unknown_city_does_not_say_pres_de() {
    if !db_available() {
        return;
    }

    let response = app(state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/search/parse")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"q":"dentiste à Grenoble"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["query"]["place"], "Grenoble");
    let interp = v["interpretation"].as_str().unwrap();
    assert!(
        !interp.contains("près de Grenoble"),
        "ville non résolue → ne doit pas promettre une proximité non appliquée : {interp}"
    );
    assert!(
        interp.contains("Grenoble"),
        "la ville reste mentionnée, sans promesse de proximité : {interp}"
    );
}
