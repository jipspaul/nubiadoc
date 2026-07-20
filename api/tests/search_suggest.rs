//! Tests d'intégration : GET /v1/search/suggest

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

/// Happy path : "dent" correspond au motif "dent manquante" de l'acte "Pose d'implant".
#[tokio::test]
async fn suggest_match_dent_returns_results() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/suggest?q=dent")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(
        v["specialties"].is_array(),
        "specialties doit être un tableau"
    );
    assert!(v["acts"].is_array(), "acts doit être un tableau");
    assert!(
        v["professions"].is_array(),
        "professions doit être un tableau"
    );

    let total = v["specialties"].as_array().unwrap().len() + v["acts"].as_array().unwrap().len();
    assert!(total >= 1, "au moins 1 résultat attendu pour 'dent'");

    // score fixé à 1.0
    if let Some(item) = v["acts"].as_array().unwrap().first() {
        assert_eq!(item["score"].as_f64().unwrap(), 1.0);
    }
}

/// Requête trop courte (1 char) → 422 Unprocessable Entity.
#[tokio::test]
async fn suggest_too_short_returns_422() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/suggest?q=x")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

/// q absent (aucun query param) → 422 (champ obligatoire manquant dans le désérialiseur Query).
#[tokio::test]
async fn suggest_missing_q_returns_422() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    // Aucun ?q= → Axum QueryRejection FailedToDeserializeQueryString → 422.
    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/suggest")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

/// q exactement 2 chars (limite basse valide) → 200 + structure correcte.
#[tokio::test]
async fn suggest_q_exactly_two_chars_returns_200() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/suggest?q=ab")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(
        v["specialties"].is_array(),
        "specialties doit être un tableau"
    );
    assert!(v["acts"].is_array(), "acts doit être un tableau");
}

/// Terme inconnu → 200 avec listes vides.
#[tokio::test]
async fn suggest_unknown_term_returns_empty() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/suggest?q=zzztermeinconnu")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["specialties"].as_array().unwrap().len(), 0);
    assert_eq!(v["acts"].as_array().unwrap().len(), 0);
    assert_eq!(v["professions"].as_array().unwrap().len(), 0);
}

/// Régression #3788 : "dentiste" est une PROFESSION (pas une spécialité) —
/// le terme de recherche n°1 de la plateforme doit produire une suggestion.
#[tokio::test]
async fn suggest_dentiste_returns_profession() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/suggest?q=dentiste")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let professions = v["professions"].as_array().unwrap();
    assert!(
        !professions.is_empty(),
        "q=dentiste doit proposer au moins la profession Chirurgien-dentiste"
    );
    assert!(professions.iter().any(|p| p["label"]
        .as_str()
        .unwrap()
        .to_lowercase()
        .contains("dentiste")));
}

/// Régression #3796 : "detartrage" (sans accent) doit matcher l'acte
/// "Détartrage" — comme /ccam/acts le fait déjà (repli d'accents).
#[tokio::test]
async fn suggest_detartrage_without_accent_matches_act() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/suggest?q=detartrage")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let acts = v["acts"].as_array().unwrap();
    assert!(
        !acts.is_empty(),
        "q=detartrage (sans accent) doit matcher au moins un acte (Détartrage)"
    );
}
