//! Tests d'intégration : GET/POST /v1/cabinet/messages (messagerie interne
//! d'équipe, #4156).

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

const JWT_SECRET: &str = "test-secret-cabinet-team-messages";

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

fn make_pro_token(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: role.into(),
            exp: exp(),
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_patient_token(sub: Uuid, account_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        account_id: Uuid,
        exp: u64,
    }
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "patient".into(),
            account_id,
            exp: exp(),
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
}

/// Insère cabinet + app_user (secretary, pas de fiche practitioner/provider).
async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("team-msg+{}@nubia.test", user_id))
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
         VALUES ($1, 'Cabinet Team Messages Test', 'dentaire')",
    )
    .bind(cabinet_id)
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
    sqlx::query("DELETE FROM cabinet_messages WHERE cabinet_id = $1")
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

// ── Test 1 : POST puis GET → message présent avec sender_name = email ────────

#[tokio::test]
async fn post_then_get_returns_message_with_sender_email_fallback() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_pro_token(f.user_id, f.cabinet_id, "secretary");

    let post_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/messages")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({ "body": "Réunion d'équipe à 12h30." }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(post_resp.status(), StatusCode::CREATED);
    let post_bytes = axum::body::to_bytes(post_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let posted: serde_json::Value = serde_json::from_slice(&post_bytes).unwrap();
    let message_id = posted["id"].as_str().unwrap().to_string();

    let get_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/messages")
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
    let v: serde_json::Value = serde_json::from_slice(&get_bytes).unwrap();
    let data = v["data"].as_array().unwrap();
    let item = data
        .iter()
        .find(|m| m["id"] == message_id)
        .expect("message présent dans le fil");
    assert_eq!(item["body"], "Réunion d'équipe à 12h30.");
    // Pas de fiche provider pour cette secrétaire → repli sur l'email.
    assert!(item["sender_name"].as_str().unwrap().contains("team-msg+"));

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : body vide → 422, rien inséré ─────────────────────────────────────

#[tokio::test]
async fn post_empty_body_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_pro_token(f.user_id, f.cabinet_id, "secretary");

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/messages")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({ "body": "   " }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let count: i64 =
        sqlx::query("SELECT count(*) AS n FROM cabinet_messages WHERE cabinet_id = $1")
            .bind(f.cabinet_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap()
            .try_get("n")
            .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(count, 0);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : patient → 403 sur GET et POST ────────────────────────────────────

#[tokio::test]
async fn patient_token_forbidden() {
    if !db_available() {
        return;
    }
    let token = make_patient_token(Uuid::new_v4(), Uuid::new_v4());

    let get_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/messages")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(get_resp.status(), StatusCode::FORBIDDEN);

    let post_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/messages")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({ "body": "Salut" }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(post_resp.status(), StatusCode::FORBIDDEN);
}

// ── Test 4bis (#4416) : un COLLÈGUE (autre user) voit le message dans le fil ──
// Repro exacte de l'issue : secrétaire poste, praticien (autre app_user, même
// cabinet) lit — avant le fix, GET renvoyait toujours {"data":[]} pour
// quiconque (INNER JOIN app_user sous RLS self-only éliminait tout).

#[tokio::test]
async fn colleague_sees_message_in_shared_thread() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let sender_token = make_pro_token(f.user_id, f.cabinet_id, "secretary");

    // Second membre du même cabinet — le "collègue" qui va lire le fil.
    let colleague_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(colleague_id)
    .bind(format!("team-msg-colleague+{}@nubia.test", colleague_id))
    .execute(&db)
    .await
    .unwrap();
    let colleague_token = make_pro_token(colleague_id, f.cabinet_id, "practitioner");

    let post_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/messages")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", sender_token))
                .body(Body::from(
                    json!({ "body": "QA-teamproof-marker-777" }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(post_resp.status(), StatusCode::CREATED);

    let get_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/messages")
                .header("Authorization", format!("Bearer {}", colleague_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(get_resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(get_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let data = v["data"].as_array().unwrap();
    let item = data
        .iter()
        .find(|m| m["body"] == "QA-teamproof-marker-777")
        .expect("le message du collègue doit être visible dans le fil partagé");
    // Le collègue n'a pas de fiche provider et l'email de l'émetteur n'est
    // pas visible sous RLS depuis ce viewer → fallback littéral, pas de 500.
    assert_eq!(item["sender_name"], "Membre du cabinet");

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(colleague_id)
        .execute(&db)
        .await
        .ok();
    cleanup_fixtures(&db, &f).await;
}

// ── Test 4 : isolation tenant — un cabinet ne voit pas les messages de l'autre ─

#[tokio::test]
async fn cross_tenant_isolation() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f1 = insert_fixtures(&db).await;
    let f2 = insert_fixtures(&db).await;
    let token1 = make_pro_token(f1.user_id, f1.cabinet_id, "secretary");
    let token2 = make_pro_token(f2.user_id, f2.cabinet_id, "secretary");

    let post_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/messages")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token1))
                .body(Body::from(
                    json!({ "body": "Message cabinet 1" }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(post_resp.status(), StatusCode::CREATED);

    let get_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/messages")
                .header("Authorization", format!("Bearer {}", token2))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(get_resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(get_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["data"].as_array().unwrap().len(), 0);

    cleanup_fixtures(&db, &f1).await;
    cleanup_fixtures(&db, &f2).await;
}
