//! Tests d'intégration : GET /v1/search/slots

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

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

// ── Helpers de fixture ────────────────────────────────────────────────────────

/// Insère un provider listé (is_listed=true) avec son cabinet et son app_user.
/// Retourne le provider_id.
async fn insert_provider(db: &PgPool, suffix: &str) -> Uuid {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Slots Test {}", suffix))
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("slots-pro-{}@nubia.test", suffix))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(user_id)
    .bind(format!("Dr Slots {}", suffix))
    .execute(db)
    .await
    .unwrap();

    provider_id
}

// ── Test 1 : happy path — 2 slots open pour un provider → data groupé correctement ──

#[tokio::test]
async fn search_slots_happy_path_returns_grouped_slots() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string()).await;

    // 2 créneaux futurs open pour le même provider
    sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, starts_at, ends_at, status, online_booking) VALUES \
         ($1, $2, now() + interval '2 days', now() + interval '2 days 30 minutes', 'open', true), \
         ($3, $2, now() + interval '1 day',  now() + interval '1 day 30 minutes',  'open', true)",
    )
    .bind(Uuid::new_v4())
    .bind(provider_id)
    .bind(Uuid::new_v4())
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                // per_page=100 : isole du plafond de pagination par défaut (#3871),
                // le test cherche son propre provider dans data sans tester la pagination.
                .uri("/v1/search/slots?per_page=100")
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
    let data = v["data"].as_array().expect("data doit être un tableau");

    // Au moins une entrée provider dans la réponse (peut y en avoir d'autres)
    let entry = data
        .iter()
        .find(|e| e["provider_id"].as_str() == Some(&provider_id.to_string()))
        .expect("le provider inséré doit apparaître dans data");

    // Structure correcte
    assert!(
        entry["provider_id"].is_string(),
        "provider_id doit être une string"
    );
    assert!(
        entry["display_name"].is_string(),
        "display_name doit être une string"
    );
    assert!(
        entry["first_slot_at"].is_string(),
        "first_slot_at doit être une string"
    );
    let slots = entry["slots"]
        .as_array()
        .expect("slots doit être un tableau");
    assert_eq!(slots.len(), 2, "2 slots open attendus pour ce provider");

    // Tri ASC : first_slot_at == le plus ancien des deux slots
    let t0 = slots[0]["starts_at"].as_str().unwrap();
    let t1 = slots[1]["starts_at"].as_str().unwrap();
    assert!(t0 < t1, "slots doivent être triés ASC par starts_at");
    assert_eq!(
        entry["first_slot_at"].as_str().unwrap(),
        t0,
        "first_slot_at doit correspondre au premier slot"
    );

    // Structure d'un slot
    assert!(
        slots[0]["slot_id"].is_string(),
        "slot_id doit être une string"
    );
    assert!(
        slots[0]["starts_at"].is_string(),
        "starts_at doit être une string"
    );

    // Nettoyage
    sqlx::query("DELETE FROM availability_slot WHERE provider_id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : `near` malformé → 422 UNPROCESSABLE_ENTITY ──────────────────────

#[tokio::test]
async fn search_slots_near_malformed_returns_422() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    // "near=abc" ne contient pas de virgule → parsing lat échoue → 422
    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/slots?near=abc")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 3 : `bbox` malformé (3 parts au lieu de 4) → 422 ───────────────────

#[tokio::test]
async fn search_slots_bbox_malformed_returns_422() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    // bbox attend 4 valeurs : minLng,minLat,maxLng,maxLat → 3 ici → 422
    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/slots?bbox=2.0,48.0,3.0")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 4 (edge) : slot passé (starts_at < now()) exclu même si status='open' ──

#[tokio::test]
async fn search_slots_past_slot_excluded() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string()).await;

    // Slot open dans le passé — ne doit pas apparaître (filtre `starts_at > now()`).
    sqlx::query(
        "INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, status) \
         VALUES ($1, $2, now() - interval '1 day', now() - interval '23 hours', 'open')",
    )
    .bind(Uuid::new_v4())
    .bind(provider_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                // per_page=100 : isole du plafond de pagination par défaut (#3871),
                // le test cherche son propre provider dans data sans tester la pagination.
                .uri("/v1/search/slots?per_page=100")
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
    let data = v["data"].as_array().expect("data doit être un tableau");

    // Ce provider ne doit PAS apparaître : son seul slot est passé.
    let found = data
        .iter()
        .any(|e| e["provider_id"].as_str() == Some(&provider_id.to_string()));
    assert!(
        !found,
        "provider avec slot passé seulement ne doit pas apparaître dans data"
    );

    // Nettoyage
    sqlx::query("DELETE FROM availability_slot WHERE provider_id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 5bis (#3727) : `q` matche le libellé de PROFESSION comme /search/providers ──

#[tokio::test]
async fn search_slots_q_matches_profession_label() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string()).await;

    // Rattache le provider à une spécialité "Chirurgien-dentiste" de la profession "dentiste".
    let profession_id = Uuid::new_v4();
    let specialty_id = Uuid::new_v4();
    sqlx::query("INSERT INTO profession (id, label) VALUES ($1, 'dentiste')")
        .bind(profession_id)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO specialty (id, profession_id, label) VALUES ($1, $2, 'Chirurgien-dentiste')",
    )
    .bind(specialty_id)
    .bind(profession_id)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query("UPDATE provider SET specialty_id = $1 WHERE id = $2")
        .bind(specialty_id)
        .bind(provider_id)
        .execute(&db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, starts_at, ends_at, status, online_booking) \
         VALUES ($1, $2, now() + interval '1 day', now() + interval '1 day 30 minutes', 'open', true)",
    )
    .bind(Uuid::new_v4())
    .bind(provider_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    // `q=dentiste` : libellé de la PROFESSION, pas de la spécialité ni du display_name.
    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/search/slots?q=dentiste&per_page=100")
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
    let data = v["data"].as_array().expect("data doit être un tableau");

    let found = data
        .iter()
        .any(|e| e["provider_id"].as_str() == Some(&provider_id.to_string()));
    assert!(
        found,
        "q=dentiste (libellé profession) doit remonter le provider, comme /search/providers"
    );

    // Nettoyage
    sqlx::query("DELETE FROM availability_slot WHERE provider_id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM specialty WHERE id = $1")
        .bind(specialty_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM profession WHERE id = $1")
        .bind(profession_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 6 : page/per_page réellement appliqués, total stable (#3871) ────────

#[tokio::test]
async fn search_slots_pagination_applied_and_total_stable() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    // Marqueur unique dans display_name pour isoler ces 3 fixtures de tout
    // autre provider présent dans la base de test partagée.
    let marker = format!("ZzPag{}", Uuid::new_v4().simple());
    let mut provider_ids = Vec::with_capacity(3);
    // Insérés dans le désordre chronologique : si le tri par défaut
    // (next_slot_at ASC) n'était pas réellement appliqué avant #3871
    // (ORDER BY sl.starts_at ASC déjà en place), l'ordre resterait fortuit ;
    // ici on vérifie surtout que per_page/page bornent réellement `data`.
    for (i, days) in [(0, 3), (1, 1), (2, 2)] {
        let provider_id = insert_provider(&db, &format!("{marker}-{i}")).await;
        sqlx::query(
            "INSERT INTO availability_slot \
             (id, provider_id, starts_at, ends_at, status, online_booking) \
             VALUES ($1, $2, now() + ($3 || ' days')::interval, \
                     now() + ($3 || ' days')::interval + interval '30 minutes', 'open', true)",
        )
        .bind(Uuid::new_v4())
        .bind(provider_id)
        .bind(days.to_string())
        .execute(&db)
        .await
        .unwrap();
        provider_ids.push(provider_id);
    }

    let q = marker.to_lowercase();
    let pool = app_pool().await;
    let fetch = |uri: String| {
        let pool = pool.clone();
        async move {
            let state = AppState {
                db: pool,
                jwt_secret: "test-secret".into(),
                mailer: Arc::new(StubMailer),
            };
            let response = app(state)
                .oneshot(Request::builder().uri(uri).body(Body::empty()).unwrap())
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::OK);
            let body = axum::body::to_bytes(response.into_body(), usize::MAX)
                .await
                .unwrap();
            serde_json::from_slice::<serde_json::Value>(&body).unwrap()
        }
    };

    // Page 1/2 : 2 des 3 providers, mais total reflète les 3.
    let page1 = fetch(format!("/v1/search/slots?q={q}&per_page=2&page=1")).await;
    assert_eq!(
        page1["data"].as_array().unwrap().len(),
        2,
        "per_page=2 doit borner data à 2 entrées, pas les 3"
    );
    assert_eq!(
        page1["page"]["total"], 3,
        "total doit refléter les 3 providers"
    );
    assert_eq!(page1["page"]["per_page"], 2);

    // Page 2/2 : le provider restant.
    let page2 = fetch(format!("/v1/search/slots?q={q}&per_page=2&page=2")).await;
    assert_eq!(page2["data"].as_array().unwrap().len(), 1);
    assert_eq!(page2["page"]["total"], 3);

    // Page hors plage : data vide mais total stable à 3 (pas 0, même classe
    // que #3840/#3864 — vérifié ici pour la pagination au grain praticien).
    let page99 = fetch(format!("/v1/search/slots?q={q}&per_page=2&page=99")).await;
    assert_eq!(
        page99["data"].as_array().unwrap().len(),
        0,
        "page hors plage doit renvoyer data vide"
    );
    assert_eq!(
        page99["page"]["total"], 3,
        "total doit rester 3 sur une page hors plage, pas retomber à 0"
    );

    // Nettoyage.
    for provider_id in provider_ids {
        sqlx::query("DELETE FROM availability_slot WHERE provider_id = $1")
            .bind(provider_id)
            .execute(&db)
            .await
            .ok();
        sqlx::query("DELETE FROM provider WHERE id = $1")
            .bind(provider_id)
            .execute(&db)
            .await
            .ok();
    }
}

// ── Test 5 : slot `held` exclu — status != 'open' → absent de data ────────────

#[tokio::test]
async fn search_slots_held_slot_excluded() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_id = insert_provider(&db, &Uuid::new_v4().to_string()).await;

    // Un slot 'held' (réservation en cours) — ne doit PAS apparaître dans search/slots
    sqlx::query(
        "INSERT INTO availability_slot (id, provider_id, starts_at, ends_at, status) \
         VALUES ($1, $2, now() + interval '1 day', now() + interval '1 day 30 minutes', 'held')",
    )
    .bind(Uuid::new_v4())
    .bind(provider_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                // per_page=100 : isole du plafond de pagination par défaut (#3871),
                // le test cherche son propre provider dans data sans tester la pagination.
                .uri("/v1/search/slots?per_page=100")
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
    let data = v["data"].as_array().expect("data doit être un tableau");

    // Ce provider ne doit PAS apparaître : son seul slot est 'held'
    let found = data
        .iter()
        .any(|e| e["provider_id"].as_str() == Some(&provider_id.to_string()));
    assert!(
        !found,
        "provider avec slot held seulement ne doit pas apparaître dans data"
    );

    // Nettoyage
    sqlx::query("DELETE FROM availability_slot WHERE provider_id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(provider_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 6 : provider_id restreint réellement la liste (#3885) ───────────────

#[tokio::test]
async fn search_slots_provider_id_filters_to_single_provider() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let provider_a = insert_provider(&db, &format!("A-{}", Uuid::new_v4())).await;
    let provider_b = insert_provider(&db, &format!("B-{}", Uuid::new_v4())).await;

    for provider_id in [provider_a, provider_b] {
        sqlx::query(
            "INSERT INTO availability_slot \
             (id, provider_id, starts_at, ends_at, status, online_booking) \
             VALUES ($1, $2, now() + interval '1 day', now() + interval '1 day 30 minutes', 'open', true)",
        )
        .bind(Uuid::new_v4())
        .bind(provider_id)
        .execute(&db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/search/slots?provider_id={provider_a}"))
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
    let data = v["data"].as_array().expect("data doit être un tableau");

    assert!(
        data.iter()
            .any(|e| e["provider_id"].as_str() == Some(&provider_a.to_string())),
        "provider_id filtré doit apparaître dans data"
    );
    assert!(
        !data
            .iter()
            .any(|e| e["provider_id"].as_str() == Some(&provider_b.to_string())),
        "l'autre provider ne doit PAS apparaître quand provider_id restreint la recherche"
    );

    // Nettoyage
    for provider_id in [provider_a, provider_b] {
        sqlx::query("DELETE FROM availability_slot WHERE provider_id = $1")
            .bind(provider_id)
            .execute(&db)
            .await
            .ok();
        sqlx::query("DELETE FROM provider WHERE id = $1")
            .bind(provider_id)
            .execute(&db)
            .await
            .ok();
    }
}

// ── Test 7 : provider_id/date syntaxiquement invalides → 422 (#3885) ─────────

#[tokio::test]
async fn search_slots_invalid_provider_id_or_date_returns_422() {
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
                .uri("/v1/search/slots?provider_id=not-a-uuid")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let state2 = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };
    let response2 = app(state2)
        .oneshot(
            Request::builder()
                .uri("/v1/search/slots?date=not-a-date")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response2.status(), StatusCode::UNPROCESSABLE_ENTITY);
}
