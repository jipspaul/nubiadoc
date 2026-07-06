//! Tests d'intégration : POST /v1/cabinet/conversations/:id/messages + /read (#3238)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-cabinet-conv-write";

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

fn make_pro_token(cabinet_id: Uuid, role: &str) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub: Uuid::new_v4(),
            kind: "pro".into(),
            cabinet_id,
            role: role.into(),
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Fixture : cabinet + patient + conversation.
async fn insert_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet ConvWrite', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Conv', 'Write')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query("INSERT INTO conversation (id, cabinet_id, patient_id) VALUES ($1, $2, $3)")
        .bind(conversation_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    (cabinet_id, patient_id, conversation_id)
}

async fn cleanup_fixture(db: &PgPool, cabinet_id: Uuid, patient_id: Uuid, conversation_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM message WHERE conversation_id = $1")
        .bind(conversation_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM conversation WHERE id = $1")
        .bind(conversation_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

async fn state() -> AppState {
    AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn post(token: &str, uri: String, body: Option<&str>) -> (StatusCode, serde_json::Value) {
    let response = app(state().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(uri)
                .header("authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(match body {
                    Some(b) => Body::from(b.to_string()),
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
    let json = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, json)
}

// ── Test 1 : secrétaire envoie un message → 201 + sender_kind=secretary ──────

#[tokio::test]
async fn secretary_sends_message_201() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, patient_id, conversation_id) = insert_fixture(&owner).await;

    let token = make_pro_token(cabinet_id, "secretary");
    let (status, json) = post(
        &token,
        format!("/v1/cabinet/conversations/{conversation_id}/messages"),
        Some(r#"{"body":"Bonjour, votre RDV est confirmé."}"#),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED, "body: {json}");
    let message_id = json["message_id"].as_str().expect("message_id présent");

    // Vérifie le sender_kind en base.
    let mut tx = owner.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT sender_kind FROM message WHERE id = $1")
        .bind(Uuid::parse_str(message_id).unwrap())
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    let kind: String = row.try_get("sender_kind").unwrap();
    assert_eq!(kind, "secretary");
    drop(tx);

    cleanup_fixture(&owner, cabinet_id, patient_id, conversation_id).await;
}

// ── Test 2 : conversation d'un autre cabinet → 404 ───────────────────────────

#[tokio::test]
async fn cross_tenant_send_returns_404() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, patient_id, conversation_id) = insert_fixture(&owner).await;

    let token = make_pro_token(Uuid::new_v4(), "practitioner");
    let (status, _) = post(
        &token,
        format!("/v1/cabinet/conversations/{conversation_id}/messages"),
        Some(r#"{"body":"intrusion"}"#),
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup_fixture(&owner, cabinet_id, patient_id, conversation_id).await;
}

// ── Test 3 : body vide → 422 ──────────────────────────────────────────────────

#[tokio::test]
async fn empty_body_returns_422() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, patient_id, conversation_id) = insert_fixture(&owner).await;

    let token = make_pro_token(cabinet_id, "practitioner");
    let (status, _) = post(
        &token,
        format!("/v1/cabinet/conversations/{conversation_id}/messages"),
        Some(r#"{"body":"   "}"#),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixture(&owner, cabinet_id, patient_id, conversation_id).await;
}

// ── Test 4 : read → 204 et read_at posé sur les messages patient ─────────────

#[tokio::test]
async fn mark_read_204_sets_read_at() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, patient_id, conversation_id) = insert_fixture(&owner).await;

    // Insère un message patient non-lu.
    let message_id = Uuid::new_v4();
    {
        let mut tx = owner.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO message (id, cabinet_id, conversation_id, sender_kind, sender_id, \
             body_ciphertext, body_key_ref) \
             VALUES ($1, $2, $3, 'patient', $4, 'msg'::bytea, 'poc-stub')",
        )
        .bind(message_id)
        .bind(cabinet_id)
        .bind(conversation_id)
        .bind(Uuid::new_v4())
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let token = make_pro_token(cabinet_id, "secretary");
    let (status, _) = post(
        &token,
        format!("/v1/cabinet/conversations/{conversation_id}/read"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let mut tx = owner.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT read_at FROM message WHERE id = $1")
        .bind(message_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    let read_at: Option<chrono::DateTime<chrono::Utc>> = row.try_get("read_at").unwrap();
    assert!(read_at.is_some(), "read_at doit être posé après /read");
    drop(tx);

    cleanup_fixture(&owner, cabinet_id, patient_id, conversation_id).await;
}

// ── GET /v1/cabinet/conversations/:id/messages (#3366) ──────────────────────

async fn get(token: &str, uri: String) -> (StatusCode, serde_json::Value) {
    let response = app(state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(uri)
                .header("authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, json)
}

/// #3366 : ouvrir un fil côté cabinet renvoyait 405 (route GET absente).
/// Le fil doit lister les messages en clair (POC UTF-8) avec `sender`.
#[tokio::test]
async fn cabinet_reads_conversation_messages_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, patient_id, conversation_id) = insert_fixture(&db).await;

    let token = make_pro_token(cabinet_id, "secretary");

    // Un message envoyé par le cabinet, pour peupler le fil.
    let (status, sent) = post(
        &token,
        format!("/v1/cabinet/conversations/{conversation_id}/messages"),
        Some(r#"{"body":"Bonjour, votre devis est prêt."}"#),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    // La réponse du POST est un message complet (le front la parse en
    // MessageDto : id/body/sender/created_at).
    assert!(sent["id"].is_string(), "id présent dans la réponse du POST");
    assert_eq!(sent["body"], "Bonjour, votre devis est prêt.");
    assert_eq!(sent["sender"], "secretary");
    assert!(sent["created_at"].is_string());

    let (status, json) = get(
        &token,
        format!("/v1/cabinet/conversations/{conversation_id}/messages"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "GET fil cabinet doit répondre 200");
    let data = json["data"].as_array().expect("data[]");
    assert_eq!(data.len(), 1);
    assert_eq!(data[0]["body"], "Bonjour, votre devis est prêt.");
    assert_eq!(data[0]["sender"], "secretary");
    assert_eq!(data[0]["sender_kind"], "secretary");
    assert!(data[0]["created_at"].is_string());

    cleanup_fixture(&db, cabinet_id, patient_id, conversation_id).await;
}

/// Cross-tenant : le fil d'un autre cabinet est indistinguable d'un fil
/// inexistant (404).
#[tokio::test]
async fn cabinet_reads_messages_cross_tenant_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, patient_id, conversation_id) = insert_fixture(&db).await;

    let other_token = make_pro_token(Uuid::new_v4(), "practitioner");
    let (status, _) = get(
        &other_token,
        format!("/v1/cabinet/conversations/{conversation_id}/messages"),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup_fixture(&db, cabinet_id, patient_id, conversation_id).await;
}

/// #3373 : la liste cabinet doit exposer l'aperçu du dernier message —
/// sans lui, l'UI affichait « Aucun message » sous chaque fil actif.
#[tokio::test]
async fn cabinet_list_exposes_last_message_preview() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, patient_id, conversation_id) = insert_fixture(&db).await;

    let token = make_pro_token(cabinet_id, "practitioner");
    let (status, _) = post(
        &token,
        format!("/v1/cabinet/conversations/{conversation_id}/messages"),
        Some(r#"{"body":"Aperçu attendu dans la liste."}"#),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, json) = get(&token, "/v1/cabinet/conversations".to_string()).await;
    assert_eq!(status, StatusCode::OK);
    let conv = json["data"]
        .as_array()
        .expect("data[]")
        .iter()
        .find(|c| c["id"] == conversation_id.to_string())
        .expect("la conversation de la fixture doit être listée")
        .clone();
    assert_eq!(
        conv["last_message_preview"], "Aperçu attendu dans la liste.",
        "aperçu du dernier message présent (#3373)"
    );
    assert!(conv["last_message_at"].is_string());

    cleanup_fixture(&db, cabinet_id, patient_id, conversation_id).await;
}
