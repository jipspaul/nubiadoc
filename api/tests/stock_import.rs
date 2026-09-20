//! Tests d'intégration : import de lignes de facture (CSV) (#7183)
//! - POST /v1/stock/import

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-stock-import";

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
    .bind(format!("stock-import+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Stock Import Test', 'dentaire')",
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

// ── Import valide : crée l'article, réceptionne, crédite le stock principal ─

#[tokio::test]
async fn import_creates_item_and_credits_main_location() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);

    let csv = "ref;libellé;quantité;prix\nGANTS-IMP;Gants latex M;20;3.50";
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/stock/import",
        &token,
        Some(json!({"csv": csv})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let imported = resp["imported"].as_array().unwrap();
    assert_eq!(imported.len(), 1, "l'entête ne doit pas être comptée");
    assert_eq!(imported[0]["reference"], "GANTS-IMP");
    assert_eq!(imported[0]["quantity"], 20);
    assert_eq!(resp["errors"].as_array().unwrap().len(), 0);

    let item_id: Uuid = Uuid::parse_str(imported[0]["item_id"].as_str().unwrap()).unwrap();

    let item_row = sqlx::query(
        "SELECT quantity_on_hand, unit, unit_price_cents FROM stock_item WHERE id = $1",
    )
    .bind(item_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let quantity_on_hand: i32 = item_row.try_get("quantity_on_hand").unwrap();
    let unit: String = item_row.try_get("unit").unwrap();
    let unit_price_cents: Option<i32> = item_row.try_get("unit_price_cents").unwrap();
    assert_eq!(quantity_on_hand, 20);
    assert_eq!(unit, "unité");
    assert_eq!(unit_price_cents, Some(350));

    let location_row = sqlx::query(
        "SELECT sil.quantity FROM stock_item_location sil \
         JOIN stock_location sl ON sl.id = sil.location_id \
         WHERE sil.item_id = $1 AND sl.is_main",
    )
    .bind(item_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let location_quantity: i32 = location_row.try_get("quantity").unwrap();
    assert_eq!(
        location_quantity, 20,
        "la localisation principale doit être créditée par l'import"
    );

    cleanup(&db, &f).await;
}

// ── Rapport d'erreurs par ligne : une ligne invalide n'annule pas les autres ─

#[tokio::test]
async fn import_reports_per_line_errors_without_blocking_valid_lines() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);

    let csv = "\
VALID-1;Article valide;5;10\n\
BAD-QTY;Quantité invalide;abc;10\n\
;Référence vide;3;\n\
VALID-2;Second article;2;";
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/stock/import",
        &token,
        Some(json!({"csv": csv})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let imported = resp["imported"].as_array().unwrap();
    assert_eq!(imported.len(), 2);
    assert_eq!(imported[0]["reference"], "VALID-1");
    assert_eq!(imported[1]["reference"], "VALID-2");

    let errors = resp["errors"].as_array().unwrap();
    assert_eq!(errors.len(), 2);
    assert_eq!(errors[0]["line"], 2);
    assert_eq!(errors[0]["error"], "quantite_invalide");
    assert_eq!(errors[1]["line"], 3);
    assert_eq!(errors[1]["error"], "reference_vide");

    cleanup(&db, &f).await;
}

// ── Référence déjà existante : ajoute une réception plutôt qu'un doublon ────

#[tokio::test]
async fn import_existing_reference_adds_reception_instead_of_duplicate() {
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
        Some(json!({"reference": "EXIST-1", "label": "Déjà là", "unit": "boite"})),
    )
    .await;
    let existing_item_id: Uuid = created["item_id"].as_str().unwrap().parse().unwrap();

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/stock/import",
        &token,
        Some(json!({"csv": "EXIST-1;Nouveau libellé ignoré;7;"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let imported = resp["imported"].as_array().unwrap();
    assert_eq!(imported.len(), 1);
    assert_eq!(
        imported[0]["item_id"].as_str().unwrap().parse(),
        Ok(existing_item_id)
    );

    let count_row = sqlx::query("SELECT count(*)::int AS n FROM stock_item WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let n: i32 = count_row.try_get("n").unwrap();
    assert_eq!(
        n, 1,
        "aucun doublon d'article créé pour une référence existante"
    );

    let item_row = sqlx::query("SELECT quantity_on_hand, unit FROM stock_item WHERE id = $1")
        .bind(existing_item_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let quantity_on_hand: i32 = item_row.try_get("quantity_on_hand").unwrap();
    let unit: String = item_row.try_get("unit").unwrap();
    assert_eq!(quantity_on_hand, 7);
    assert_eq!(
        unit, "boite",
        "l'unité de l'article existant n'est pas écrasée par l'import"
    );

    cleanup(&db, &f).await;
}
