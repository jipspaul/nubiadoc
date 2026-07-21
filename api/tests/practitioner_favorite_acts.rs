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
