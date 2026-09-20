//! Tests d'intégration : localisations de stock, transfert entre salles
//! (#7183)
//! - GET/POST /v1/cabinet/stock-locations
//! - DELETE /v1/cabinet/stock-locations/:id
//! - GET /v1/cabinet/stock-items/:id/locations
//! - PATCH /v1/cabinet/stock-items/:id/locations/:location_id
//! - POST /v1/cabinet/stock-items/:id/transfer

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

const JWT_SECRET: &str = "test-secret-stock-locations";

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
    .bind(format!("stock-loc+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Stock Loc Test', 'dentaire')",
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
    sqlx::query("DELETE FROM stock_item_location WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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
    sqlx::query("DELETE FROM stock_location WHERE cabinet_id = $1")
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

// ── Création + liste : la principale est créée à la volée, en tête ──────────

#[tokio::test]
async fn create_and_list_stock_locations() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);

    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/stock-locations",
        &token,
        Some(json!({"name": "Salle 1"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert!(created["location_id"].as_str().is_some());

    let (status, dup) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/stock-locations",
        &token,
        Some(json!({"name": "Salle 1"})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(dup["code"], "stock_location_name_already_used");

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/stock-locations",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let locations = list.as_array().unwrap();
    assert_eq!(
        locations.len(),
        2,
        "la localisation principale est créée à la volée par le premier GET"
    );
    assert_eq!(locations[0]["name"], "Stock principal");
    assert_eq!(locations[0]["is_main"], true);
    assert_eq!(locations[1]["name"], "Salle 1");
    assert_eq!(locations[1]["is_main"], false);

    cleanup(&db, &f).await;
}

// ── Suppression : principale protégée, localisation vide supprimable ────────

#[tokio::test]
async fn delete_stock_location_rules() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);

    // L'import CSV crée l'article ET crédite la localisation principale
    // (contrairement à la réception manuelle, hors périmètre #7183).
    let (_, imported) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/stock/import",
        &token,
        Some(json!({"csv": "DEL-LOC;Article;5;"})),
    )
    .await;
    let item_id = imported["imported"][0]["item_id"]
        .as_str()
        .unwrap()
        .to_string();
    let (_, salle) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/stock-locations",
        &token,
        Some(json!({"name": "Salle Del"})),
    )
    .await;
    let salle_id = salle["location_id"].as_str().unwrap().to_string();

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/stock-locations",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let locations = list.as_array().unwrap();
    let main = locations.iter().find(|l| l["is_main"] == true).unwrap();
    let main_id = main["id"].as_str().unwrap().to_string();

    // La localisation principale ne peut pas être supprimée.
    let (status, resp) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/stock-locations/{main_id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(resp["code"], "stock_location_is_main");

    // Une localisation encore approvisionnée (transfert) ne peut pas être supprimée.
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/transfer"),
        &token,
        Some(json!({"from_location_id": main_id, "to_location_id": salle_id, "quantity": 3})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, resp) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/stock-locations/{salle_id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(resp["code"], "stock_location_in_use");

    // Une fois vidée (transfert retour), elle redevient supprimable.
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/transfer"),
        &token,
        Some(json!({"from_location_id": salle_id, "to_location_id": main_id, "quantity": 3})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/stock-locations/{salle_id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    cleanup(&db, &f).await;
}

// ── Transfert : déplace la quantité, ne touche pas quantity_on_hand ─────────

#[tokio::test]
async fn transfer_moves_quantity_between_locations() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);

    // L'import CSV crée l'article ET crédite la localisation principale
    // (contrairement à la réception manuelle, hors périmètre #7183).
    let (_, imported) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/stock/import",
        &token,
        Some(json!({"csv": "TRANSFER-1;Article;10;"})),
    )
    .await;
    let item_id = imported["imported"][0]["item_id"]
        .as_str()
        .unwrap()
        .to_string();

    let (_, salle) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/stock-locations",
        &token,
        Some(json!({"name": "Salle Transfert"})),
    )
    .await;
    let salle_id = salle["location_id"].as_str().unwrap().to_string();

    let (_, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/stock-locations",
        &token,
        None,
    )
    .await;
    let main_id = list
        .as_array()
        .unwrap()
        .iter()
        .find(|l| l["is_main"] == true)
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/transfer"),
        &token,
        Some(json!({"from_location_id": main_id, "to_location_id": salle_id, "quantity": 4})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(resp["from_quantity"], 6);
    assert_eq!(resp["to_quantity"], 4);

    // Quantité globale (quantity_on_hand) inchangée — seule sa répartition bouge.
    let (status, items) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/stock-items",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let item = items
        .as_array()
        .unwrap()
        .iter()
        .find(|i| i["id"] == item_id)
        .unwrap();
    assert_eq!(item["quantity_on_hand"], 10);

    let (status, per_location) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/stock-items/{item_id}/locations"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let per_location = per_location.as_array().unwrap();
    let main_loc = per_location.iter().find(|l| l["is_main"] == true).unwrap();
    assert_eq!(main_loc["quantity"], 6);
    let salle_loc = per_location
        .iter()
        .find(|l| l["location_id"] == salle_id)
        .unwrap();
    assert_eq!(salle_loc["quantity"], 4);

    // Transfert au-delà du disponible → 422 insufficient_stock, rien ne bouge.
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/transfer"),
        &token,
        Some(json!({"from_location_id": salle_id, "to_location_id": main_id, "quantity": 999})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(resp["code"], "insufficient_stock");

    // from == to → 422 validation_error.
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/stock-items/{item_id}/transfer"),
        &token,
        Some(json!({"from_location_id": main_id, "to_location_id": main_id, "quantity": 1})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Seuil par localisation : upsert via PATCH ────────────────────────────────

#[tokio::test]
async fn set_item_location_threshold() {
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
        Some(json!({"reference": "THRESH-1", "label": "Article", "unit": "boite"})),
    )
    .await;
    let item_id = created["item_id"].as_str().unwrap().to_string();

    let (_, salle) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/stock-locations",
        &token,
        Some(json!({"name": "Salle Seuil"})),
    )
    .await;
    let salle_id = salle["location_id"].as_str().unwrap().to_string();

    let (status, _) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/stock-items/{item_id}/locations/{salle_id}"),
        &token,
        Some(json!({"threshold": 2})),
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, per_location) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/stock-items/{item_id}/locations"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let salle_loc = per_location
        .as_array()
        .unwrap()
        .iter()
        .find(|l| l["location_id"] == salle_id)
        .unwrap();
    assert_eq!(salle_loc["threshold"], 2);
    assert_eq!(salle_loc["quantity"], 0);

    cleanup(&db, &f).await;
}
