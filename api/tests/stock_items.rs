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

// ── Test 1a (#4479) : signe de delta incohérent avec reason → 422 ───────────

#[tokio::test]
async fn delta_sign_incoherent_with_reason_returns_422() {
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
            "reference": "GANTS-SIGN",
            "label": "Gants latex sign",
            "unit": "boite"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let item_id = created["item_id"].as_str().unwrap().to_string();

    // consumption positif → une "consommation" ne doit jamais AUGMENTER le stock.
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &practitioner_token,
        Some(json!({"delta": 9999, "reason": "consumption"})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // reception négatif → une "réception" ne doit jamais DIMINUER le stock.
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &practitioner_token,
        Some(json!({"delta": -5, "reason": "reception"})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // peremption positif → refusé, même logique que consumption.
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &practitioner_token,
        Some(json!({"delta": 3, "reason": "peremption"})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // adjustment reste libre dans les deux sens.
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &secretary_token,
        Some(json!({"delta": 5, "reason": "adjustment"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(resp["quantity_on_hand"], 5);

    // Rien de tout ceci n'a bougé le stock au-delà de l'unique adjustment accepté.
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
    let item = items
        .iter()
        .find(|i| i["id"] == item_id)
        .expect("item must exist");
    assert_eq!(item["quantity_on_hand"], 5);

    cleanup(&db, &f).await;
}

// ── Test 1b : consommation > stock disponible → 422 insufficient_stock (#4341) ──

#[tokio::test]
async fn consumption_exceeding_stock_returns_422_insufficient_stock() {
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
        Some(json!({"reference": "GANTS-NEG", "label": "Gants latex", "unit": "boite"})),
    )
    .await;
    let item_id = created["item_id"].as_str().unwrap().to_string();

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &token,
        Some(json!({"delta": 5, "reason": "reception"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(resp["quantity_on_hand"], 5);

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &token,
        Some(json!({"delta": -100, "reason": "consumption"})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(resp["code"], "insufficient_stock");

    // La quantité reste au dernier état valide (5), pas de mouvement fantôme.
    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/stock-items",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = list.as_array().unwrap();
    assert_eq!(
        items[0]["quantity_on_hand"], 5,
        "aucun mouvement négatif appliqué"
    );

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

// ── Test 2a (#4832) : GET des mouvements — ledger relisible ─────────────────

#[tokio::test]
async fn list_stock_movements_returns_ledger_with_reason_and_expiry() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/stock-items",
        &token,
        Some(json!({"reference": "GANTS-LEDGER", "label": "Gants latex", "unit": "boite"})),
    )
    .await;
    let item_id = created["item_id"].as_str().unwrap().to_string();

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &token,
        Some(json!({"delta": 10, "reason": "reception"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(resp["quantity_on_hand"], 10);

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &token,
        Some(json!({"delta": -1, "reason": "peremption", "expiry_date": "2027-01-01"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let peremption_movement_id = resp["movement_id"].as_str().unwrap().to_string();

    // #4832 : la route était POST-only (405 en GET) — le ledger doit
    // maintenant être relisible, du plus récent au plus ancien.
    let (status, movements) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let movements = movements.as_array().unwrap();
    assert_eq!(movements.len(), 2);

    let latest = &movements[0];
    assert_eq!(latest["id"], peremption_movement_id);
    assert_eq!(latest["delta"], -1);
    assert_eq!(latest["reason"], "peremption");
    assert_eq!(latest["expiry_date"], "2027-01-01");

    let earliest = &movements[1];
    assert_eq!(earliest["delta"], 10);
    assert_eq!(earliest["reason"], "reception");
    assert!(earliest.get("expiry_date").is_none());

    cleanup(&db, &f).await;
}

// ── Test 2b (#4832) : GET des mouvements hors tenant → 404 ──────────────────

#[tokio::test]
async fn list_stock_movements_from_other_cabinet_returns_404() {
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
        Some(json!({"reference": "GANTS-LEDGER-2", "label": "Gants latex", "unit": "boite"})),
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
        .bind(format!("stock-ledger-other+{other_user_id}@nubia.test"))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) \
             VALUES ($1, 'Cabinet Stock Ledger Other', 'dentaire')",
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
        "GET",
        &format!("/v1/cabinet/stock-items/{item_id}/movements"),
        &other_token,
        None,
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
