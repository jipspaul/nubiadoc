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
    // « dentiste » = profession Chirurgien-dentiste, rattachée à PLUSIEURS
    // spécialités (Omnipratique + Implantologie, migration 0039) : par design
    // (#3618) `parse` ne collapse PAS sur une spécialité arbitraire — specialty
    // reste null et la recherche reste à l'échelle de la profession, portée par
    // `q`. Cf. le test jumeau `suggest_dentiste_returns_profession`.
    assert!(
        v["query"]["specialty"].is_null(),
        "« dentiste » = profession multi-spécialités → pas de collapse arbitraire (#3618), obtenu : {}",
        v["query"]["specialty"]
    );
    assert_eq!(
        v["query"]["q"], "dentiste",
        "le terme profession reste porté par q (recherche à l'échelle profession, #3618)"
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

/// #6656 : « demain » → available=tomorrow, 200 (seul mot de date ignoré jusqu'ici).
#[tokio::test]
async fn parse_keywords_available_demain() {
    if !db_available() {
        return;
    }

    let response = app(state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/search/parse")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"q":"dentiste demain"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["query"]["available"], "tomorrow");
    assert!(v["interpretation"].as_str().unwrap().contains("demain"));
}

/// #6686 : « après-demain » ne doit PAS être capturé par le `contains("demain")`
/// de #6656 (« après-demain » contient « demain » comme sous-chaîne). Le
/// vocabulaire de `available` n'a pas de valeur dédiée pour J+2 : on attend
/// donc available=null plutôt qu'un faux « tomorrow ».
#[tokio::test]
async fn parse_keywords_apres_demain_is_not_tomorrow() {
    if !db_available() {
        return;
    }

    for q in [
        "dentiste après-demain",
        "dentiste apres-demain",
        "dentiste apres demain",
        "dentiste surlendemain",
    ] {
        let response = app(state(app_pool().await))
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/search/parse")
                    .header("content-type", "application/json")
                    .body(Body::from(format!(r#"{{"q":"{q}"}}"#)))
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
            v["query"]["available"].is_null(),
            "« {q} » ne doit pas être interprété comme tomorrow, obtenu : {}",
            v["query"]["available"]
        );
        assert!(
            !v["interpretation"]
                .as_str()
                .unwrap()
                .contains("disponible demain"),
            "« {q} » : l'interprétation ne doit pas affirmer « disponible demain », obtenu : {}",
            v["interpretation"]
        );
    }
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
/// #8610 : depuis #6997, `search_providers`/`search_slots` rejettent en 422
/// un `place` non résolu au lieu de l'ignorer — `query.place` doit donc
/// rester `null` (pas « Grenoble ») pour que le couple parse/providers reste
/// consommable tel quel par le front. Seule `interpretation` (texte libre)
/// garde la ville.
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
    assert!(
        v["query"]["place"].is_null(),
        "ville non résolue → place structuré doit être null, sans quoi search_providers la rejette en 422 (#8610) : {v}"
    );
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

/// #8615 : recherche par nom de praticien/cabinet (hors dictionnaire
/// spécialité/acte/profession) avec une préposition de lieu — la préposition
/// consommée par `detect_place` ne doit pas rester dans `q`, ni se cumuler
/// avec le « près de »/« à » reconstruit par `build_interpretation`
/// (ex. observé avant fix : « Marin à près de Lyon »).
#[tokio::test]
async fn parse_keywords_name_with_place_preposition_is_not_duplicated() {
    if !db_available() {
        return;
    }

    for (q, forbidden) in [
        ("Marin à Lyon", "à près de"),
        ("Dubois à Paris", "à près de"),
        ("ophtalmo près de Bastille", "de à"),
    ] {
        let response = app(state(app_pool().await))
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/search/parse")
                    .header("content-type", "application/json")
                    .body(Body::from(format!(r#"{{"q":"{q}"}}"#)))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        let interp = v["interpretation"].as_str().unwrap();
        assert!(
            !interp.contains(forbidden),
            "« {q} » : préposition dupliquée dans l'interprétation : {interp}"
        );
        let query_q = v["query"]["q"].as_str().unwrap_or("");
        assert!(
            !query_q
                .split_whitespace()
                .any(|w| matches!(w, "à" | "a" | "de" | "du")),
            "« {q} » : préposition orpheline restée dans q={query_q:?}"
        );
    }
}

/// #8610 : repro exacte de l'issue — « près de <quartier> » (lieu-dit parisien,
/// hors KNOWN_CITY_COORDS) doit lui aussi laisser `query.place` à `null`, pas
/// seulement la juxtaposition nue couverte par `parse_unknown_city_does_not_say_pres_de`.
/// Avant #8610, cette branche (préposition « près de »/« à ») ne passait pas
/// par le même filtre de résolvabilité, et `query.place="Bastille"` était
/// rejeté en 422 par `GET /v1/search/providers` (#6997) → écran d'erreur.
#[tokio::test]
async fn parse_unresolved_neighbourhood_via_preposition_has_null_place() {
    if !db_available() {
        return;
    }

    for q in [
        "Dentiste secteur 1 près de Bastille",
        "dentiste à Montmartre",
    ] {
        let response = app(state(app_pool().await))
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/search/parse")
                    .header("content-type", "application/json")
                    .body(Body::from(format!(r#"{{"q":"{q}"}}"#)))
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
            v["query"]["place"].is_null(),
            "« {q} » : place non résolu doit être null, sinon search_providers 422 (#8610), obtenu : {v}"
        );
    }
}

/// #6799 : code postal isolé (« dentiste 75002 ») → place="75002". Jusqu'ici
/// `detect_place` ne reconnaissait qu'un nom de ville ou une préposition
/// (« à X », « près de X ») : un code postal nu était silencieusement perdu.
#[tokio::test]
async fn parse_postal_code_is_detected_as_place() {
    if !db_available() {
        return;
    }

    let response = app(state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/search/parse")
                .header("content-type", "application/json")
                .body(Body::from(r#"{"q":"dentiste 75002"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["query"]["place"], "75002");
}

/// #6799 : nom de ville nu, sans préposition (« dentiste paris », « orthodontiste
/// Lyon ») → place résolu. Couvert par #7042 pour la juxtaposition simple ;
/// non-régression ici car c'est le repro exact de l'issue.
#[tokio::test]
async fn parse_bare_city_name_is_detected_as_place() {
    if !db_available() {
        return;
    }

    for (q, expected_place) in [
        ("dentiste paris demain", "paris"),
        ("orthodontiste Lyon", "Lyon"),
    ] {
        let response = app(state(app_pool().await))
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri("/v1/search/parse")
                    .header("content-type", "application/json")
                    .body(Body::from(format!(r#"{{"q":"{q}"}}"#)))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);

        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
        assert_eq!(
            v["query"]["place"], expected_place,
            "« {q} » doit résoudre place={expected_place}, obtenu : {}",
            v["query"]["place"]
        );
    }
}
