//! Tests d'intégration : GET/POST /v1/cabinet/practitioners/me/favorite-acts
//! + DELETE .../favorite-acts/:ccam_code (#4112)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-favorite-acts";
const CCAM_CODE_A: &str = "HBQK002";
const CCAM_CODE_B: &str = "HBGD036";

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

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900
}

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub, "kind": "pro", "cabinet_id": cabinet_id,
            "role": "practitioner", "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub, "kind": "pro", "cabinet_id": cabinet_id,
            "role": "secretary", "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
}

async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("fav-prac+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet Favorites Test')")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(Uuid::new_v4())
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        user_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner_favorite_act WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : POST crée un favori, GET le liste ───────────────────────────────

#[tokio::test]
async fn create_and_list_favorite_acts() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);
    let state = make_state(app_pool().await);

    let post_resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"ccam_code": CCAM_CODE_A}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(post_resp.status(), StatusCode::OK);
    let post_bytes = axum::body::to_bytes(post_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let post_body: serde_json::Value = serde_json::from_slice(&post_bytes).unwrap();
    assert_eq!(post_body["ccam_code"], CCAM_CODE_A);
    assert_eq!(post_body["position"], 1);

    let get_resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(get_resp.status(), StatusCode::OK);
    let get_bytes = axum::body::to_bytes(get_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let get_body: serde_json::Value = serde_json::from_slice(&get_bytes).unwrap();
    let data = get_body["data"].as_array().unwrap();
    assert_eq!(data.len(), 1);
    assert_eq!(data[0]["ccam_code"], CCAM_CODE_A);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : doublon → 409 ────────────────────────────────────────────────────

#[tokio::test]
async fn create_favorite_act_duplicate_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);
    let state = make_state(app_pool().await);

    let body = json!({"ccam_code": CCAM_CODE_A}).to_string();
    let first = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(body.clone()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::OK);

    let second = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::CONFLICT);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : code CCAM inexistant → 422 ───────────────────────────────────────

#[tokio::test]
async fn create_favorite_act_unknown_code_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"ccam_code": "CODE_INEXISTANT"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 4 : DELETE retire un favori, absent ensuite ─────────────────────────

#[tokio::test]
async fn delete_favorite_act_removes_it() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);
    let state = make_state(app_pool().await);

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"ccam_code": CCAM_CODE_A}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    let delete_resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/v1/cabinet/practitioners/me/favorite-acts/{}",
                    CCAM_CODE_A
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(delete_resp.status(), StatusCode::NO_CONTENT);

    let get_resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let get_bytes = axum::body::to_bytes(get_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let get_body: serde_json::Value = serde_json::from_slice(&get_bytes).unwrap();
    assert_eq!(get_body["data"].as_array().unwrap().len(), 0);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 5 : DELETE d'un favori inexistant → 404 ─────────────────────────────

#[tokio::test]
async fn delete_favorite_act_not_found_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/v1/cabinet/practitioners/me/favorite-acts/{}",
                    CCAM_CODE_A
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 6 : secrétaire → 403 sur les trois routes ───────────────────────────

#[tokio::test]
async fn secretary_forbidden_on_favorite_acts_routes() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);
    let state = make_state(app_pool().await);

    let get_resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(get_resp.status(), StatusCode::FORBIDDEN);

    let post_resp = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"ccam_code": CCAM_CODE_A}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(post_resp.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 7 : sans q, les favoris remontent en tête (#4112) ───────────────────

#[tokio::test]
async fn search_ccam_acts_surfaces_favorites_first_when_q_empty() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);
    let state = make_state(app_pool().await);

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"ccam_code": CCAM_CODE_B}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/ccam/acts")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let data = body["data"].as_array().unwrap();
    assert_eq!(
        data[0]["code"], CCAM_CODE_B,
        "le favori doit être le premier résultat quand q est vide"
    );

    cleanup_fixtures(&db, &f).await;
}

// ── Test 8 : page remplie par les favoris -> next_cursor quand même émis (#8550) ─

/// Avant #8550, quand `limit <= nombre de favoris` du praticien, la page est
/// remplie entièrement par les favoris (`:280-299`) sans jamais exécuter la
/// requête de continuation du catalogue (`:374` ancien `if remaining > 0`),
/// laissant `next_cursor = null` malgré `total` > `limit` : le catalogue
/// devenait définitivement inatteignable passé les favoris.
#[tokio::test]
async fn search_ccam_acts_emits_next_cursor_when_page_filled_by_favorites() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);
    let state = make_state(app_pool().await);

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"ccam_code": CCAM_CODE_A}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    // `limit=1` == nombre de favoris du praticien : la page 1 est remplie
    // uniquement par le favori, sans toucher à la continuation du catalogue.
    let resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/ccam/acts?limit=1")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let page1: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let data1 = page1["data"].as_array().unwrap();
    assert_eq!(data1.len(), 1, "page 1 : {page1}");
    assert_eq!(data1[0]["code"], CCAM_CODE_A);
    let total = page1["page"]["total"].as_i64().unwrap();
    assert!(
        total > 1,
        "le référentiel CCAM doit contenir plus d'un acte actif : {page1}"
    );
    let cursor = page1["page"]["next_cursor"]
        .as_str()
        .expect("data.len() < total -> next_cursor doit être présent (#8550)")
        .to_string();

    // Le curseur émis doit permettre d'atteindre la suite du catalogue.
    let resp2 = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/ccam/acts?limit=5&cursor={cursor}"))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp2.status(), StatusCode::OK);
    let bytes2 = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let page2: serde_json::Value = serde_json::from_slice(&bytes2).unwrap();
    let data2 = page2["data"].as_array().unwrap();
    assert!(
        !data2.is_empty(),
        "le curseur de la page 1 doit rester exploitable : {page2}"
    );
    assert_eq!(page2["page"]["total"], serde_json::json!(total));

    cleanup_fixtures(&db, &f).await;
}

// ── Test 9 : le favori n'est pas ré-émis sur la page suivante du curseur (#8554) ─

/// `#8550` a corrigé l'émission du curseur quand la page 1 est remplie par
/// les favoris, mais a exposé un doublon : la requête catalogue exclut les
/// favoris déjà rendus via `favorite_codes` (`ccam_acts.rs:~380`), construite
/// à partir de `rows` — vide dès qu'un `cursor` est fourni (`rows` n'est
/// peuplé des favoris qu'en page 1, `:280`). L'exclusion devient alors un
/// no-op et le favori réapparaît à sa place alphabétique sur la page
/// suivante.
#[tokio::test]
async fn search_ccam_acts_does_not_repeat_favorite_on_next_cursor_page() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);
    let state = make_state(app_pool().await);

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioners/me/favorite-acts")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"ccam_code": CCAM_CODE_A}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    // `limit=1` == nombre de favoris : page 1 = uniquement le favori, le
    // curseur émis doit reprendre le catalogue SANS le favori.
    let resp1 = app(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/ccam/acts?limit=1")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let bytes1 = axum::body::to_bytes(resp1.into_body(), usize::MAX)
        .await
        .unwrap();
    let page1: serde_json::Value = serde_json::from_slice(&bytes1).unwrap();
    assert_eq!(page1["data"][0]["code"], CCAM_CODE_A);
    let total = page1["page"]["total"].as_i64().unwrap();
    let cursor = page1["page"]["next_cursor"].as_str().unwrap().to_string();

    // Déroule le curseur jusqu'au bout, en comptant les occurrences de
    // CCAM_CODE_A : il ne doit apparaître qu'une seule fois sur l'ensemble
    // de la chaîne, et le total de lignes rendues doit égaler `total`.
    let mut next_cursor = Some(cursor);
    let mut rendered = 1i64; // la page 1 (le favori)
    let mut occurrences_of_favorite = 1i64;
    while let Some(c) = next_cursor.take() {
        let resp = app(state.clone())
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(format!("/v1/ccam/acts?limit=5&cursor={c}"))
                    .header("Authorization", format!("Bearer {}", token))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        let page: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        let data = page["data"].as_array().unwrap();
        rendered += data.len() as i64;
        occurrences_of_favorite += data
            .iter()
            .filter(|row| row["code"] == CCAM_CODE_A)
            .count() as i64;
        next_cursor = page["page"]["next_cursor"].as_str().map(str::to_string);
    }

    assert_eq!(
        occurrences_of_favorite, 1,
        "le favori {CCAM_CODE_A} ne doit être rendu qu'une seule fois sur toute la pagination"
    );
    assert_eq!(
        rendered, total,
        "le nombre total de lignes rendues sur la pagination doit égaler `total`"
    );

    cleanup_fixtures(&db, &f).await;
}
