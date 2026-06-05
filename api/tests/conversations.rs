//! Tests d'intégration : GET + POST /v1/conversations

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

const JWT_SECRET: &str = "test-jwt-secret-conversations";

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

fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── Test 1 : liste vide — patient sans conversation ───────────────────────────

#[tokio::test]
async fn conversations_empty_returns_200_with_empty_data() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("conv-empty+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Vide')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/conversations")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(v["data"], json!([]), "data doit être vide");
    assert!(
        v["page"]["next_cursor"].is_null(),
        "next_cursor doit être null"
    );
    assert_eq!(v["page"]["limit"], 20);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : happy-path — patient avec une conversation et un message non lu ──

#[tokio::test]
async fn conversations_with_unread_message_returns_correct_data() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let conv_id = Uuid::new_v4();
    let msg_id = Uuid::new_v4();

    // Entités plateforme (hors RLS cabinet).
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("conv-happy+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'Messagerie')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("conv-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // Entités tenant (GUC requis pour FORCE RLS).
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet Conv Test {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
            .bind(prac_id)
            .bind(cabinet_id)
            .bind(prac_user_id)
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Bob', 'Messagerie', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(account_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query("INSERT INTO conversation (id, cabinet_id, patient_id) VALUES ($1, $2, $3)")
            .bind(conv_id)
            .bind(cabinet_id)
            .bind(patient_id)
            .execute(&mut *tx)
            .await
            .unwrap();

        // Message du praticien, non lu.
        sqlx::query(
            "INSERT INTO message \
             (id, cabinet_id, conversation_id, sender_kind, sender_id, \
              body_ciphertext, body_key_ref) \
             VALUES ($1, $2, $3, 'practitioner', $4, '\\xDEAD'::bytea, 'key-ref-test')",
        )
        .bind(msg_id)
        .bind(cabinet_id)
        .bind(conv_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/conversations")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    let data = &v["data"];
    assert_eq!(
        data.as_array().unwrap().len(),
        1,
        "doit avoir 1 conversation"
    );

    let conv = &data[0];
    assert_eq!(conv["id"], conv_id.to_string(), "id correct");
    assert_eq!(
        conv["cabinet_id"],
        cabinet_id.to_string(),
        "cabinet_id correct"
    );
    assert!(conv["cabinet_name"].is_string(), "cabinet_name présent");
    assert!(
        conv["last_message_at"].is_string(),
        "last_message_at présent"
    );
    assert_eq!(conv["unread_count"], 1, "unread_count = 1 (message non lu)");

    // Cleanup (FORCE RLS).
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM message WHERE id = $1")
            .bind(msg_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM conversation WHERE id = $1")
            .bind(conv_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM patient WHERE id = $1")
            .bind(patient_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM practitioner WHERE id = $1")
            .bind(prac_id)
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
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}

/// Crée un cabinet avec un praticien listé, retourne `cabinet_id`.
async fn setup_listed_cabinet(db: &PgPool) -> Uuid {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("conv-pro+{}@nubia.test", cabinet_id))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Conv Test {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) \
         VALUES (gen_random_uuid(), $1, $2, 'Dr Test', true, true)",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    cabinet_id
}

/// Crée un compte patient, retourne `(user_id, account_id)`.
async fn setup_patient(db: &PgPool) -> (Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("conv-patient+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Conv')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();

    (user_id, account_id)
}

// ── Test 1 : cabinet listé → 201 + conversation_id ───────────────────────────

#[tokio::test]
async fn conversations_create_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = setup_listed_cabinet(&db).await;
    let (user_id, account_id) = setup_patient(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/conversations")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::from(json!({ "cabinet_id": cabinet_id }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert!(
        v["conversation_id"].is_string(),
        "conversation_id doit être présent"
    );
    assert_eq!(v["existing"], false, "existing doit être false");

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM conversation WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
            .bind(cabinet_id)
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
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : re-POST même cabinet → 200 + même conversation_id + existing:true ─

#[tokio::test]
async fn conversations_create_idempotent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = setup_listed_cabinet(&db).await;
    let (user_id, account_id) = setup_patient(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let make_request = || {
        Request::builder()
            .method("POST")
            .uri("/v1/conversations")
            .header("content-type", "application/json")
            .header(
                "Authorization",
                format!("Bearer {}", make_patient_jwt(user_id, account_id)),
            )
            .body(Body::from(json!({ "cabinet_id": cabinet_id }).to_string()))
            .unwrap()
    };

    let router = app(state);

    let r1 = router.clone().oneshot(make_request()).await.unwrap();
    assert_eq!(r1.status(), StatusCode::CREATED);
    let b1 = axum::body::to_bytes(r1.into_body(), usize::MAX)
        .await
        .unwrap();
    let v1: serde_json::Value = serde_json::from_slice(&b1).unwrap();
    let conv_id = v1["conversation_id"].as_str().unwrap().to_string();

    let r2 = router.oneshot(make_request()).await.unwrap();
    assert_eq!(r2.status(), StatusCode::OK);
    let b2 = axum::body::to_bytes(r2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&b2).unwrap();

    assert_eq!(
        v2["conversation_id"].as_str().unwrap(),
        conv_id,
        "conversation_id doit être identique"
    );
    assert_eq!(v2["existing"], true, "existing doit être true au 2e appel");

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM conversation WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
            .bind(cabinet_id)
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
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3 : cabinet inexistant → 404 ─────────────────────────────────────────

#[tokio::test]
async fn conversations_cabinet_not_found_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user_id, account_id) = setup_patient(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/conversations")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::from(
                    json!({ "cabinet_id": Uuid::new_v4() }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    // Cleanup
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}
