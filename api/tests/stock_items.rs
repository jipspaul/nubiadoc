//! Tests d'intégration : inventaire cabinet (#4144)
//! - GET/POST /v1/cabinet/stock-items
//! - POST /v1/cabinet/stock-items/{id}/movements

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

const JWT_SECRET: &str = "test-secret-stock-items";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
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
            "role": "practitioner",
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
    .bind(format!("stock+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Stock Test', 'dentaire')",
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
    sqlx::query("DELETE FROM stock_movement WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM stock_item WHERE cabinet_id = $1")
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

// ── Test 1 : réception de 10 puis consommation de 3 → quantity_on_hand = 7 ──
// Vérifie aussi que practitioner ET secretary peuvent tous deux appeler ces
// routes (ProSecretaryPlusClaims, tâche opérationnelle non clinique).

#[tokio::test]
async fn reception_then_consumption_updates_quantity_on_hand() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let secretary_token = make_secretary_token(f.user_id, f.cabinet_id);
    let practitioner_token = make_practitioner_token(f.user_id, f.cabinet_id);

    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/stock-items",
        &secretary_token,
        Some(json!({
            "reference": "GANTS-M",
            "label": "Gants latex M",
            "unit": "boite",
            "alert_threshold": 3
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let item_id = created["item_id"].as_str().unwrap().to_string();

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &practitioner_token,
        Some(json!({"delta": 10, "reason": "reception"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(resp["quantity_on_hand"], 10);

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &secretary_token,
        Some(json!({"delta": -3, "reason": "consumption"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(resp["quantity_on_hand"], 7);

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/stock-items",
        &secretary_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = list.as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["quantity_on_hand"], 7);

    cleanup(&db, &f).await;
}

// ── Test 2 : référence déjà utilisée dans ce cabinet → 409 ───────────────────

#[tokio::test]
async fn duplicate_reference_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/stock-items",
        &token,
        Some(json!({"reference": "GANTS-M", "label": "Gants latex M", "unit": "boite"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/stock-items",
        &token,
        Some(json!({"reference": "GANTS-M", "label": "Doublon", "unit": "boite"})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(resp["code"], "stock_reference_already_used");

    cleanup(&db, &f).await;
}

// ── Test 3 : mouvement hors tenant → 404 ─────────────────────────────────────

#[tokio::test]
async fn movement_from_other_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/stock-items",
        &token,
        Some(json!({"reference": "GANTS-M", "label": "Gants latex M", "unit": "boite"})),
    )
    .await;
    let item_id = created["item_id"].as_str().unwrap().to_string();

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
        .bind(format!("stock-other+{other_user_id}@nubia.test"))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) \
             VALUES ($1, 'Cabinet Stock Other', 'dentaire')",
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
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &other_token,
        Some(json!({"delta": 1, "reason": "adjustment"})),
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
