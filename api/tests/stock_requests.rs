//! Tests d'intégration : demandes de stock cabinet → pharmacie (lot B5, issue #3310)

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

const JWT_SECRET: &str = "test-jwt-secret-stock-requests";

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

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600
}

fn pro_jwt(cabinet_id: Uuid, role: &str) -> String {
    encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "pro", "cabinet_id": cabinet_id,
                "role": role, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn pharma_jwt(pharmacy_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "pharma", "pharmacy_id": pharmacy_id,
                "role": "pharmacist", "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn seed(db: &PgPool) -> (Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet Stock')")
        .bind(cabinet_id)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Pharmacie Stock', true)",
    )
    .bind(pharmacy_id)
    .execute(db)
    .await
    .unwrap();
    (cabinet_id, pharmacy_id)
}

async fn call(
    method: &str,
    uri: &str,
    token: &str,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("Authorization", format!("Bearer {}", token));
    if body.is_some() {
        builder = builder.header("content-type", "application/json");
    }
    let response = app(AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        builder
            .body(match body {
                Some(v) => Body::from(v.to_string()),
                None => Body::empty(),
            })
            .unwrap(),
    )
    .await
    .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
    (status, v)
}

#[tokio::test]
async fn full_cycle_sent_accepted_fulfilled() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, pharmacy_id) = seed(&db).await;
    let pro = pro_jwt(cabinet_id, "secretary");
    let pharma = pharma_jwt(pharmacy_id);

    // Création par la secrétaire (rôle non clinique autorisé).
    let (status, request) = call(
        "POST",
        "/v1/cabinet/stock-requests",
        &pro,
        Some(json!({
            "pharmacy_id": pharmacy_id,
            "items": [
                {"label": "Compresses stériles", "qty": 10, "note": "boîtes de 100"},
                {"label": "Sérum physiologique", "qty": 5}
            ]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {request}");
    assert_eq!(request["status"], "sent");
    assert_eq!(request["cabinet_name"], "Cabinet Stock");
    let id = request["id"].as_str().unwrap().to_string();

    // Visible des deux bords.
    let (status, list) = call("GET", "/v1/cabinet/stock-requests", &pro, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(list["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["id"] == request["id"]));
    let (status, list) = call("GET", "/v1/pharmacy/stock-requests", &pharma, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(list["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|r| r["id"] == request["id"]));

    // accept → fulfill.
    let (status, request) = call(
        "POST",
        &format!("/v1/pharmacy/stock-requests/{id}/accept"),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(request["status"], "accepted");

    // Annulation après acceptation → 409.
    let (status, _) = call(
        "POST",
        &format!("/v1/cabinet/stock-requests/{id}/cancel"),
        &pro,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    let (status, request) = call(
        "POST",
        &format!("/v1/pharmacy/stock-requests/{id}/fulfill"),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(request["status"], "fulfilled");

    // fulfill deux fois → 409.
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/stock-requests/{id}/fulfill"),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn reject_with_note_and_cancel_flow() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, pharmacy_id) = seed(&db).await;
    let pro = pro_jwt(cabinet_id, "practitioner");
    let pharma = pharma_jwt(pharmacy_id);

    let (_, request) = call(
        "POST",
        "/v1/cabinet/stock-requests",
        &pro,
        Some(json!({"pharmacy_id": pharmacy_id,
                    "items": [{"label": "Anesthésique", "qty": 2}]})),
    )
    .await;
    let id = request["id"].as_str().unwrap().to_string();

    let (status, request) = call(
        "POST",
        &format!("/v1/pharmacy/stock-requests/{id}/reject"),
        &pharma,
        Some(json!({"note": "Rupture fournisseur"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(request["status"], "rejected");
    assert_eq!(request["response_note"], "Rupture fournisseur");

    // Annulation d'une demande encore `sent`.
    let (_, request2) = call(
        "POST",
        "/v1/cabinet/stock-requests",
        &pro,
        Some(json!({"pharmacy_id": pharmacy_id,
                    "items": [{"label": "Gants nitrile", "qty": 20}]})),
    )
    .await;
    let id2 = request2["id"].as_str().unwrap().to_string();
    let (status, request2) = call(
        "POST",
        &format!("/v1/cabinet/stock-requests/{id2}/cancel"),
        &pro,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(request2["status"], "cancelled");
}

#[tokio::test]
async fn resend_while_sent_then_blocked_after_accept() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, pharmacy_id) = seed(&db).await;
    let pro = pro_jwt(cabinet_id, "secretary");
    let pharma = pharma_jwt(pharmacy_id);

    let (_, request) = call(
        "POST",
        "/v1/cabinet/stock-requests",
        &pro,
        Some(json!({"pharmacy_id": pharmacy_id,
                    "items": [{"label": "Compresses stériles", "qty": 10}]})),
    )
    .await;
    let id = request["id"].as_str().unwrap().to_string();

    // Relance tant que `sent` : statut inchangé.
    let (status, resent) = call(
        "POST",
        &format!("/v1/cabinet/stock-requests/{id}/resend"),
        &pro,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(resent["status"], "sent");
    assert_eq!(resent["id"], request["id"]);

    // Une fois acceptée, la relance n'a plus de sens → 409.
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/stock-requests/{id}/accept"),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(
        "POST",
        &format!("/v1/cabinet/stock-requests/{id}/resend"),
        &pro,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn validation_and_isolation() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, pharmacy_id) = seed(&db).await;
    let pro = pro_jwt(cabinet_id, "secretary");

    // Items vides → 422.
    let (status, _) = call(
        "POST",
        "/v1/cabinet/stock-requests",
        &pro,
        Some(json!({"pharmacy_id": pharmacy_id, "items": []})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Quantité nulle → 422.
    let (status, _) = call(
        "POST",
        "/v1/cabinet/stock-requests",
        &pro,
        Some(json!({"pharmacy_id": pharmacy_id, "items": [{"label": "X", "qty": 0}]})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Pharmacie non listée → 404.
    sqlx::query("UPDATE pharmacy SET is_listed = false WHERE id = $1")
        .bind(pharmacy_id)
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = call(
        "POST",
        "/v1/cabinet/stock-requests",
        &pro,
        Some(json!({"pharmacy_id": pharmacy_id, "items": [{"label": "X", "qty": 1}]})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Une autre pharmacie ne peut pas répondre (RLS → 404).
    sqlx::query("UPDATE pharmacy SET is_listed = true WHERE id = $1")
        .bind(pharmacy_id)
        .execute(&db)
        .await
        .unwrap();
    let (_, request) = call(
        "POST",
        "/v1/cabinet/stock-requests",
        &pro,
        Some(json!({"pharmacy_id": pharmacy_id, "items": [{"label": "X", "qty": 1}]})),
    )
    .await;
    let id = request["id"].as_str().unwrap().to_string();
    let other_pharmacy = Uuid::new_v4();
    sqlx::query("INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Autre', true)")
        .bind(other_pharmacy)
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/stock-requests/{id}/accept"),
        &pharma_jwt(other_pharmacy),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Un token pharma ne peut pas émettre côté cabinet → 403.
    let (status, _) = call(
        "POST",
        "/v1/cabinet/stock-requests",
        &pharma_jwt(pharmacy_id),
        Some(json!({"pharmacy_id": pharmacy_id, "items": [{"label": "X", "qty": 1}]})),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}
