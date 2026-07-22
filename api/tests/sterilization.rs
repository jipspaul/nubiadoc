//! Tests d'intégration : traçabilité stérilisation (#4138)
//! - GET/POST /v1/cabinet/sterilization-cycles
//! - POST /v1/cabinet/sterilization-cycles/{id}/pouches

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

const JWT_SECRET: &str = "test-secret-sterilization";

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

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": "secretary",
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    user_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("steril+{user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Sterilization Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM sterilized_pouch WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM sterilization_cycle WHERE cabinet_id = $1")
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

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn call(
    state: AppState,
    method: &str,
    uri: &str,
    token: &str,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("Authorization", format!("Bearer {token}"));
    let body = match body {
        Some(v) => {
            builder = builder.header("Content-Type", "application/json");
            Body::from(v.to_string())
        }
        None => Body::empty(),
    };
    let response = app(state)
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

// ── Test 1 : cycle non conforme → association d'une pochette reste possible ──

#[tokio::test]
async fn pouch_can_be_added_to_non_conforme_cycle() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);

    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/sterilization-cycles",
        &token,
        Some(json!({
            "autoclave_ref": "Autoclave-1",
            "cycle_number": 12,
            "test_kind": "bowie_dick",
            "test_result": "virage incomplet",
            "status": "non_conforme"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let cycle_id = created["cycle_id"].as_str().unwrap().to_string();

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/sterilization-cycles/{cycle_id}/pouches"),
        &token,
        Some(json!({"code": "DM-000042"})),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::CREATED,
        "la traçabilité doit rester possible même sur un cycle non conforme"
    );
    assert!(resp["pouch_id"].is_string());

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/sterilization-cycles",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let cycles = list.as_array().unwrap();
    assert_eq!(cycles.len(), 1);
    assert_eq!(cycles[0]["status"], "non_conforme");

    cleanup(&db, &f).await;
}

// ── Test 2 : scan hors tenant → 404 ──────────────────────────────────────────

#[tokio::test]
async fn scan_from_other_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/sterilization-cycles",
        &token,
        Some(json!({
            "autoclave_ref": "Autoclave-1",
            "cycle_number": 1,
            "test_kind": "helix",
            "test_result": "virage complet",
            "status": "conforme"
        })),
    )
    .await;
    let cycle_id = created["cycle_id"].as_str().unwrap().to_string();

    let other_cabinet_id = Uuid::new_v4();
    let other_user_id = Uuid::new_v4();
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(other_cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(other_user_id)
        .bind(format!("steril-other+{other_user_id}@nubia.test"))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) \
             VALUES ($1, 'Cabinet Sterilization Other', 'dentaire')",
        )
        .bind(other_cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }
    let other_token = make_secretary_token(other_user_id, other_cabinet_id);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/sterilization-cycles/{cycle_id}/pouches"),
        &other_token,
        Some(json!({"code": "DM-999999"})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(other_cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM cabinet WHERE id = $1")
            .bind(other_cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_user_id)
        .execute(&db)
        .await
        .ok();

    cleanup(&db, &f).await;
}
