//! Tests d'intégration : messagerie patient ↔ pharmacie (lot B6, issue #3311)

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

const JWT_SECRET: &str = "test-jwt-secret-pharmacy-messaging";

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

fn patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp()}),
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

async fn seed(db: &PgPool) -> (Uuid, Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("pm-{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Jean', 'Demo')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Pharmacie PM', true)",
    )
    .bind(pharmacy_id)
    .execute(db)
    .await
    .unwrap();
    (user_id, account_id, pharmacy_id)
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
async fn full_thread_patient_and_pharmacy() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id, pharmacy_id) = seed(&db).await;
    let patient = patient_jwt(user_id, account_id);
    let pharma = pharma_jwt(pharmacy_id);

    // Le patient ouvre le fil avec sa pharmacie.
    let (status, conversation) = call(
        "POST",
        "/v1/conversations",
        &patient,
        Some(json!({"pharmacy_id": pharmacy_id, "subject": "Question posologie"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "body: {conversation}");
    let conversation_id = conversation["id"].as_str().unwrap().to_string();
    assert_eq!(conversation["pharmacy_id"], json!(pharmacy_id));

    // Idempotent : re-création → même fil.
    let (status, again) = call(
        "POST",
        "/v1/conversations",
        &patient,
        Some(json!({"pharmacy_id": pharmacy_id})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(again["id"], conversation["id"]);

    // Le patient écrit ; le triage est forcé normal côté officine.
    let (status, _) = call(
        "POST",
        &format!("/v1/conversations/{conversation_id}/messages"),
        &patient,
        Some(json!({"body": "Bonjour, dois-je prendre le traitement pendant les repas ? urgent"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    // La pharmacie voit le fil (nom minimisé) et le message.
    let (status, list) = call("GET", "/v1/pharmacy/conversations", &pharma, None).await;
    assert_eq!(status, StatusCode::OK);
    let item = list["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["id"] == conversation["id"])
        .expect("fil visible côté pharmacie")
        .clone();
    assert_eq!(item["patient_name"], "Jean D.");
    assert_eq!(item["unread_count"], 1);
    // #3854 : la liste pharmacie n'émettait jamais last_message_preview
    // (contrairement à la liste cabinet) → le front affichait "Aucun message"
    // sur TOUT fil, y compris avec des non-lus.
    assert!(
        item["last_message_preview"]
            .as_str()
            .expect("last_message_preview doit être présent")
            .contains("traitement"),
        "last_message_preview doit reprendre le corps du dernier message : {item}"
    );

    let (status, messages) = call(
        "GET",
        &format!("/v1/pharmacy/conversations/{conversation_id}/messages"),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let first = &messages["data"].as_array().unwrap()[0];
    assert_eq!(first["sender_kind"], "patient");
    // #3712 : MessageDto.fromJson (front) exige la clé `sender` (non-nullable) —
    // seul cet endpoint ne l'émettait pas, faisant planter le fil pharmacie
    // au décodage malgré un 200 valide.
    assert_eq!(first["sender"], "patient");
    assert!(
        first["body"].as_str().unwrap().contains("traitement"),
        "le corps du message est déchiffré côté pharmacie"
    );

    // La pharmacie répond puis marque lu.
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/conversations/{conversation_id}/messages"),
        &pharma,
        Some(json!({"body": "Oui, de préférence pendant les repas."})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/conversations/{conversation_id}/read"),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    // Le patient voit la réponse du pharmacien dans son fil.
    let (status, messages) = call(
        "GET",
        &format!("/v1/conversations/{conversation_id}/messages"),
        &patient,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {messages}");
    assert!(messages["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|m| m["sender"] == "pharmacist"));

    // Et la liste patient contient le fil avec le nom de la pharmacie.
    let (status, list) = call("GET", "/v1/conversations", &patient, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(list["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|c| c["id"] == conversation["id"] && c["cabinet_name"] == "Pharmacie PM"));
}

#[tokio::test]
async fn isolation_and_validation() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id, pharmacy_id) = seed(&db).await;
    let patient = patient_jwt(user_id, account_id);

    let (_, conversation) = call(
        "POST",
        "/v1/conversations",
        &patient,
        Some(json!({"pharmacy_id": pharmacy_id})),
    )
    .await;
    let conversation_id = conversation["id"].as_str().unwrap().to_string();

    // Une autre pharmacie ne voit pas le fil → 404.
    let other_pharmacy = Uuid::new_v4();
    sqlx::query("INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Autre', true)")
        .bind(other_pharmacy)
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = call(
        "GET",
        &format!("/v1/pharmacy/conversations/{conversation_id}/messages"),
        &pharma_jwt(other_pharmacy),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // cabinet_id ET pharmacy_id → 422 ; aucun des deux → 422.
    let (status, _) = call(
        "POST",
        "/v1/conversations",
        &patient,
        Some(json!({"cabinet_id": Uuid::new_v4(), "pharmacy_id": pharmacy_id})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = call("POST", "/v1/conversations", &patient, Some(json!({}))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Pharmacie non listée → 404.
    sqlx::query("UPDATE pharmacy SET is_listed = false WHERE id = $1")
        .bind(other_pharmacy)
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = call(
        "POST",
        "/v1/conversations",
        &patient,
        Some(json!({"pharmacy_id": other_pharmacy})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Message vide côté pharmacie → 422.
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/conversations/{conversation_id}/messages"),
        &pharma_jwt(pharmacy_id),
        Some(json!({"body": "   "})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}
