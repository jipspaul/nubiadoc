//! Tests d'intégration : GET + POST /v1/conversations
//! + GET /v1/conversations/:id/messages
//! + POST /v1/conversations/:id/read

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

/// Crée un cabinet (sans praticien listé nécessaire), retourne `cabinet_id`.
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

/// Lie un patient (account_id) à un cabinet, retourne `patient_id`.
async fn setup_patient_link(db: &PgPool, cabinet_id: Uuid, account_id: Uuid) -> Uuid {
    let patient_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Alice', 'Conv', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    patient_id
}

// ── Test 1 : cabinet existant → 201 + id + cabinet_id + subject + created_at ──

#[tokio::test]
async fn conversations_create_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = setup_listed_cabinet(&db).await;
    let (user_id, account_id) = setup_patient(&db).await;
    let patient_id = setup_patient_link(&db, cabinet_id, account_id).await;

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
                    json!({ "cabinet_id": cabinet_id, "subject": "Question prothèse" }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert!(v["id"].is_string(), "id doit être présent");
    assert_eq!(
        v["cabinet_id"],
        cabinet_id.to_string(),
        "cabinet_id correct"
    );
    assert_eq!(v["subject"], "Question prothèse", "subject correct");
    assert!(v["created_at"].is_string(), "created_at doit être présent");

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

// ── Test 2 : re-POST même cabinet → 201 + même id (idempotence) ───────────────

#[tokio::test]
async fn conversations_create_idempotent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = setup_listed_cabinet(&db).await;
    let (user_id, account_id) = setup_patient(&db).await;
    let patient_id = setup_patient_link(&db, cabinet_id, account_id).await;

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
    let conv_id = v1["id"].as_str().unwrap().to_string();

    let r2 = router.oneshot(make_request()).await.unwrap();
    assert_eq!(r2.status(), StatusCode::CREATED);
    let b2 = axum::body::to_bytes(r2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&b2).unwrap();

    assert_eq!(
        v2["id"].as_str().unwrap(),
        conv_id,
        "id doit être identique au 2e appel"
    );

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id,
                "role": "admin", "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn lazy_app_pool() -> PgPool {
    PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap()
}

// ── Test 4 : cabinet non lié au patient → 403 ─────────────────────────────────

#[tokio::test]
async fn conversations_create_unlinked_cabinet_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    // Cabinet existant mais sans lien `patient` pour ce compte.
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

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
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

// ═══════════════════════════════════════════════════════════════════════════════
// Trous T-API-AUDIT-A006 — routes auditées mais non couvertes par tests existants
// ═══════════════════════════════════════════════════════════════════════════════

// ── GET /v1/conversations : auth scope ────────────────────────────────────────

/// 401 : requête sans token.
#[tokio::test]
async fn conversations_list_no_token_returns_401() {
    let state = AppState {
        db: lazy_app_pool(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/conversations")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

/// 403 : token pro (rôle inadéquat pour route patient).
#[tokio::test]
async fn conversations_list_pro_token_returns_403() {
    let state = AppState {
        db: lazy_app_pool(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let token = make_pro_jwt(Uuid::new_v4(), Uuid::new_v4());

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/conversations")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

/// 401 : token patient bien formé (bonne signature) mais expiré.
/// Vérifie que `PatientAccountClaims` respecte `validate_exp = true`
/// et ne laisse pas passer un token dont le `exp` est dépassé.
#[tokio::test]
async fn conversations_list_expired_token_returns_401() {
    let state = AppState {
        db: lazy_app_pool(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // exp fixé à 2 h dans le passé — dépasse le leeway par défaut (60 s).
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        - 7200;
    let token = encode(
        &Header::default(),
        &json!({
            "sub": Uuid::new_v4(),
            "kind": "patient",
            "account_id": Uuid::new_v4(),
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/conversations")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── GET /v1/conversations/:id/messages : auth scope ───────────────────────────

/// 401 : requête sans token.
#[tokio::test]
async fn conversations_messages_no_token_returns_401() {
    let state = AppState {
        db: lazy_app_pool(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/conversations/{}/messages", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

/// 403 : token pro.
#[tokio::test]
async fn conversations_messages_pro_token_returns_403() {
    let state = AppState {
        db: lazy_app_pool(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let token = make_pro_jwt(Uuid::new_v4(), Uuid::new_v4());

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/conversations/{}/messages", Uuid::new_v4()))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

/// 404 : conversation inconnue (UUID aléatoire → RLS filtre → handler renvoie 404).
#[tokio::test]
async fn conversations_messages_unknown_conversation_returns_404() {
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
                .method("GET")
                .uri(format!("/v1/conversations/{}/messages", Uuid::new_v4()))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
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

/// happy path 200 + body conforme : liste des messages d'un fil.
#[tokio::test]
async fn conversations_messages_returns_200_with_data() {
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

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("conv-msgs+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Carol', 'Msgs')",
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
    .bind(format!("conv-msgs-pro+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

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
        .bind(format!("Cabinet Msgs Test {}", cabinet_id))
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
             VALUES ($1, $2, 'Carol', 'Msgs', $3)",
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
                .uri(format!("/v1/conversations/{}/messages", conv_id))
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

    let data = v["data"].as_array().unwrap();
    assert_eq!(data.len(), 1, "doit avoir 1 message");
    let msg = &data[0];
    assert_eq!(msg["id"], msg_id.to_string(), "id message correct");
    assert!(msg["created_at"].is_string(), "created_at présent");
    assert!(msg["read_at"].is_null(), "read_at null (non lu)");

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        for q in &[
            ("DELETE FROM message WHERE id = $1", msg_id),
            ("DELETE FROM conversation WHERE id = $1", conv_id),
            ("DELETE FROM patient WHERE id = $1", patient_id),
            ("DELETE FROM practitioner WHERE id = $1", prac_id),
            ("DELETE FROM cabinet WHERE id = $1", cabinet_id),
        ] {
            sqlx::query(q.0).bind(q.1).execute(&mut *tx).await.ok();
        }
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&db)
        .await
        .ok();
}

/// Conversation accessible mais sans aucun message → 200 + data:[] + page conforme.
#[tokio::test]
async fn conversations_messages_empty_conversation_returns_200_with_empty_data() {
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

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("conv-msgs-empty+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Eve', 'Empty')",
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
    .bind(format!("conv-msgs-empty-pro+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

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
        .bind(format!("Cabinet Msgs Empty Test {}", cabinet_id))
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
             VALUES ($1, $2, 'Eve', 'Empty', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(account_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        // Conversation sans aucun message.
        sqlx::query("INSERT INTO conversation (id, cabinet_id, patient_id) VALUES ($1, $2, $3)")
            .bind(conv_id)
            .bind(cabinet_id)
            .bind(patient_id)
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
                .uri(format!("/v1/conversations/{}/messages", conv_id))
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

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        for q in &[
            ("DELETE FROM conversation WHERE id = $1", conv_id),
            ("DELETE FROM patient WHERE id = $1", patient_id),
            ("DELETE FROM practitioner WHERE id = $1", prac_id),
            ("DELETE FROM cabinet WHERE id = $1", cabinet_id),
        ] {
            sqlx::query(q.0).bind(q.1).execute(&mut *tx).await.ok();
        }
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&db)
        .await
        .ok();
}

// ── POST /v1/conversations/:id/read : auth scope + état DB ────────────────────

/// 401 : requête sans token.
#[tokio::test]
async fn conversations_read_no_token_returns_401() {
    let state = AppState {
        db: lazy_app_pool(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/conversations/{}/read", Uuid::new_v4()))
                .header("content-type", "application/json")
                .body(Body::from("{}"))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

/// 403 : token pro.
#[tokio::test]
async fn conversations_read_pro_token_returns_403() {
    let state = AppState {
        db: lazy_app_pool(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let token = make_pro_jwt(Uuid::new_v4(), Uuid::new_v4());

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/conversations/{}/read", Uuid::new_v4()))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from("{}"))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

/// 404 : conversation inconnue.
#[tokio::test]
async fn conversations_read_unknown_conversation_returns_404() {
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
                .uri(format!("/v1/conversations/{}/read", Uuid::new_v4()))
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::from("{}"))
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

// ── GET /v1/conversations : isolation RLS cross-patient ───────────────────────

/// Le patient B ne voit pas les conversations du patient A dans le même cabinet.
/// Valide que `app.patient_account_id` filtre correctement (policy 0029).
#[tokio::test]
async fn conversations_list_does_not_leak_other_patient_data() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_a_id = Uuid::new_v4();
    let account_a_id = Uuid::new_v4();
    let user_b_id = Uuid::new_v4();
    let account_b_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let patient_a_id = Uuid::new_v4();
    let patient_b_id = Uuid::new_v4();
    let conv_a_id = Uuid::new_v4();
    let conv_b_id = Uuid::new_v4();

    // Entités plateforme (hors RLS cabinet).
    for (uid, email) in [
        (user_a_id, format!("conv-rls-a+{}@nubia.test", user_a_id)),
        (user_b_id, format!("conv-rls-b+{}@nubia.test", user_b_id)),
    ] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
        )
        .bind(uid)
        .bind(email)
        .execute(&db)
        .await
        .unwrap();
    }
    for (acc_id, uid, fname) in [
        (account_a_id, user_a_id, "Eve"),
        (account_b_id, user_b_id, "Frank"),
    ] {
        sqlx::query(
            "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
             VALUES ($1, $2, $3, 'RLS')",
        )
        .bind(acc_id)
        .bind(uid)
        .bind(fname)
        .execute(&db)
        .await
        .unwrap();
    }

    // Entités tenant : même cabinet, deux patients, deux conversations.
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
        .bind(format!("Cabinet RLS Test {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        for (pid, acc_id, fname) in [
            (patient_a_id, account_a_id, "Eve"),
            (patient_b_id, account_b_id, "Frank"),
        ] {
            sqlx::query(
                "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
                 VALUES ($1, $2, $3, 'RLS', $4)",
            )
            .bind(pid)
            .bind(cabinet_id)
            .bind(fname)
            .bind(acc_id)
            .execute(&mut *tx)
            .await
            .unwrap();
        }

        for (cid, pid) in [(conv_a_id, patient_a_id), (conv_b_id, patient_b_id)] {
            sqlx::query(
                "INSERT INTO conversation (id, cabinet_id, patient_id) VALUES ($1, $2, $3)",
            )
            .bind(cid)
            .bind(cabinet_id)
            .bind(pid)
            .execute(&mut *tx)
            .await
            .unwrap();
        }

        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Requête en tant que patient A.
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/conversations")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_a_id, account_a_id)),
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

    let data = v["data"].as_array().unwrap();
    assert_eq!(
        data.len(),
        1,
        "patient A ne doit voir que sa propre conversation"
    );
    assert_eq!(
        data[0]["id"],
        conv_a_id.to_string(),
        "la conversation visible est bien celle du patient A"
    );

    // Cleanup.
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        for q in &[
            ("DELETE FROM conversation WHERE id = $1", conv_a_id),
            ("DELETE FROM conversation WHERE id = $1", conv_b_id),
            ("DELETE FROM patient WHERE id = $1", patient_a_id),
            ("DELETE FROM patient WHERE id = $1", patient_b_id),
            ("DELETE FROM cabinet WHERE id = $1", cabinet_id),
        ] {
            sqlx::query(q.0).bind(q.1).execute(&mut *tx).await.ok();
        }
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM patient_account WHERE id = $1 OR id = $2")
        .bind(account_a_id)
        .bind(account_b_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_a_id)
        .bind(user_b_id)
        .execute(&db)
        .await
        .ok();
}

/// Idempotence : 2e appel → 204 sans erreur, `read_at` reste stable (pas écrasé).
#[tokio::test]
async fn conversations_read_idempotent_double_call_returns_204() {
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

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("conv-read-idem+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Dave', 'Idem')",
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
    .bind(format!("conv-read-idem-pro+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

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
        .bind(format!("Cabinet Idem Test {}", cabinet_id))
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
             VALUES ($1, $2, 'Dave', 'Idem', $3)",
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

    let make_request = || {
        Request::builder()
            .method("POST")
            .uri(format!("/v1/conversations/{}/read", conv_id))
            .header("content-type", "application/json")
            .header(
                "Authorization",
                format!("Bearer {}", make_patient_jwt(user_id, account_id)),
            )
            .body(Body::from("{}"))
            .unwrap()
    };

    let router = app(state);

    // Premier appel → 204.
    let r1 = router.clone().oneshot(make_request()).await.unwrap();
    assert_eq!(r1.status(), StatusCode::NO_CONTENT);

    let row = sqlx::query("SELECT read_at FROM message WHERE id = $1")
        .bind(msg_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let read_at_1: Option<chrono::DateTime<chrono::Utc>> = row.try_get("read_at").unwrap();
    assert!(read_at_1.is_some(), "read_at défini après 1er appel");

    // Second appel → 204 (idempotent, pas d'erreur).
    let r2 = router.oneshot(make_request()).await.unwrap();
    assert_eq!(r2.status(), StatusCode::NO_CONTENT);

    // read_at ne doit pas avoir changé (UPDATE WHERE read_at IS NULL ne touche rien).
    let row2 = sqlx::query("SELECT read_at FROM message WHERE id = $1")
        .bind(msg_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let read_at_2: Option<chrono::DateTime<chrono::Utc>> = row2.try_get("read_at").unwrap();
    assert_eq!(
        read_at_1, read_at_2,
        "read_at stable après 2e appel (idempotence)"
    );

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        for q in &[
            ("DELETE FROM message WHERE id = $1", msg_id),
            ("DELETE FROM conversation WHERE id = $1", conv_id),
            ("DELETE FROM patient WHERE id = $1", patient_id),
            ("DELETE FROM practitioner WHERE id = $1", prac_id),
            ("DELETE FROM cabinet WHERE id = $1", cabinet_id),
        ] {
            sqlx::query(q.0).bind(q.1).execute(&mut *tx).await.ok();
        }
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&db)
        .await
        .ok();
}

/// RLS cross-patient : patient B ne peut pas marquer lue la conversation de patient A.
/// La conversation existe en DB mais le RLS `conversation_patient_read` la masque → 404.
/// Valide que `mark_conversation_read` ne fuit pas de données cross-patient.
#[tokio::test]
async fn conversations_read_cross_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    // Patient A (propriétaire de la conversation).
    let user_a_id = Uuid::new_v4();
    let account_a_id = Uuid::new_v4();
    // Patient B (l'attaquant).
    let user_b_id = Uuid::new_v4();
    let account_b_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let patient_a_id = Uuid::new_v4();
    let patient_b_id = Uuid::new_v4();
    let conv_a_id = Uuid::new_v4();

    for (uid, email, kind) in [
        (
            user_a_id,
            format!("conv-cross-a+{}@nubia.test", user_a_id),
            "patient",
        ),
        (
            user_b_id,
            format!("conv-cross-b+{}@nubia.test", user_b_id),
            "patient",
        ),
    ] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(uid)
        .bind(email)
        .bind(kind)
        .execute(&db)
        .await
        .unwrap();
    }
    for (acc_id, uid, fname) in [
        (account_a_id, user_a_id, "Alice"),
        (account_b_id, user_b_id, "Bob"),
    ] {
        sqlx::query(
            "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
             VALUES ($1, $2, $3, 'Cross')",
        )
        .bind(acc_id)
        .bind(uid)
        .bind(fname)
        .execute(&db)
        .await
        .unwrap();
    }

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
        .bind(format!("Cabinet Cross Test {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        for (pid, acc_id, fname) in [
            (patient_a_id, account_a_id, "Alice"),
            (patient_b_id, account_b_id, "Bob"),
        ] {
            sqlx::query(
                "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
                 VALUES ($1, $2, $3, 'Cross', $4)",
            )
            .bind(pid)
            .bind(cabinet_id)
            .bind(fname)
            .bind(acc_id)
            .execute(&mut *tx)
            .await
            .unwrap();
        }

        // Seule la conversation de patient A est créée.
        sqlx::query("INSERT INTO conversation (id, cabinet_id, patient_id) VALUES ($1, $2, $3)")
            .bind(conv_a_id)
            .bind(cabinet_id)
            .bind(patient_a_id)
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

    // Patient B tente de marquer lue la conversation de patient A → RLS masque → 404.
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/conversations/{}/read", conv_a_id))
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_b_id, account_b_id)),
                )
                .body(Body::from("{}"))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        for q in &[
            ("DELETE FROM conversation WHERE id = $1", conv_a_id),
            ("DELETE FROM patient WHERE id = $1", patient_a_id),
            ("DELETE FROM patient WHERE id = $1", patient_b_id),
            ("DELETE FROM cabinet WHERE id = $1", cabinet_id),
        ] {
            sqlx::query(q.0).bind(q.1).execute(&mut *tx).await.ok();
        }
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM patient_account WHERE id = $1 OR id = $2")
        .bind(account_a_id)
        .bind(account_b_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_a_id)
        .bind(user_b_id)
        .execute(&db)
        .await
        .ok();
}

/// Lecture partielle : `last_read_message_id` fourni → seuls les messages dont
/// l'`id <= last_read_message_id` sont marqués lus ; les autres restent non lus.
/// Valide la branche `Some(last_read_message_id)` du handler `mark_conversation_read`.
#[tokio::test]
async fn conversations_read_partial_with_last_message_id_marks_only_earlier_messages() {
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
    let msg1_id = Uuid::new_v4();
    let msg2_id = Uuid::new_v4();

    // Détermine lequel des deux UUIDs est le plus petit (comparaison binaire).
    // L'UPDATE filtre `id <= last_read_message_id` : seul smaller_id sera marqué lu.
    let (smaller_id, larger_id) = if msg1_id < msg2_id {
        (msg1_id, msg2_id)
    } else {
        (msg2_id, msg1_id)
    };

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("conv-partial+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Grace', 'Partial')",
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
    .bind(format!("conv-partial-pro+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

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
        .bind(format!("Cabinet Partial Test {}", cabinet_id))
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
             VALUES ($1, $2, 'Grace', 'Partial', $3)",
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

        // Deux messages praticien non lus.
        for mid in [msg1_id, msg2_id] {
            sqlx::query(
                "INSERT INTO message \
                 (id, cabinet_id, conversation_id, sender_kind, sender_id, \
                  body_ciphertext, body_key_ref) \
                 VALUES ($1, $2, $3, 'practitioner', $4, '\\xDEAD'::bytea, 'key-ref-test')",
            )
            .bind(mid)
            .bind(cabinet_id)
            .bind(conv_id)
            .bind(prac_id)
            .execute(&mut *tx)
            .await
            .unwrap();
        }

        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // POST avec last_read_message_id = smaller_id → seul ce message doit être marqué lu.
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/conversations/{}/read", conv_id))
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::from(
                    json!({ "last_read_message_id": smaller_id }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    // smaller_id : read_at doit être renseigné (id <= last_read_message_id).
    let row_s = sqlx::query("SELECT read_at FROM message WHERE id = $1")
        .bind(smaller_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let read_at_s: Option<chrono::DateTime<chrono::Utc>> = row_s.try_get("read_at").unwrap();
    assert!(read_at_s.is_some(), "smaller_id doit être marqué lu");

    // larger_id : read_at doit rester NULL (id > last_read_message_id, non touché).
    let row_l = sqlx::query("SELECT read_at FROM message WHERE id = $1")
        .bind(larger_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let read_at_l: Option<chrono::DateTime<chrono::Utc>> = row_l.try_get("read_at").unwrap();
    assert!(
        read_at_l.is_none(),
        "larger_id doit rester non lu (id > last_read_message_id)"
    );

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        for q in &[
            ("DELETE FROM message WHERE id = $1", msg1_id),
            ("DELETE FROM message WHERE id = $1", msg2_id),
            ("DELETE FROM conversation WHERE id = $1", conv_id),
            ("DELETE FROM patient WHERE id = $1", patient_id),
            ("DELETE FROM practitioner WHERE id = $1", prac_id),
            ("DELETE FROM cabinet WHERE id = $1", cabinet_id),
        ] {
            sqlx::query(q.0).bind(q.1).execute(&mut *tx).await.ok();
        }
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&db)
        .await
        .ok();
}

/// happy path 204 + état DB : `read_at IS NOT NULL` après marquage.
#[tokio::test]
async fn conversations_read_marks_messages_and_returns_204() {
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

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("conv-read+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Dave', 'Read')",
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
    .bind(format!("conv-read-pro+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

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
        .bind(format!("Cabinet Read Test {}", cabinet_id))
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
             VALUES ($1, $2, 'Dave', 'Read', $3)",
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

        // Message praticien non lu (read_at IS NULL).
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
                .method("POST")
                .uri(format!("/v1/conversations/{}/read", conv_id))
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::from("{}"))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    // Vérification état DB : read_at doit être renseigné.
    let row = sqlx::query("SELECT read_at FROM message WHERE id = $1")
        .bind(msg_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let read_at: Option<chrono::DateTime<chrono::Utc>> = row.try_get("read_at").unwrap();
    assert!(
        read_at.is_some(),
        "read_at doit être non null après mark_conversation_read"
    );

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        for q in &[
            ("DELETE FROM message WHERE id = $1", msg_id),
            ("DELETE FROM conversation WHERE id = $1", conv_id),
            ("DELETE FROM patient WHERE id = $1", patient_id),
            ("DELETE FROM practitioner WHERE id = $1", prac_id),
            ("DELETE FROM cabinet WHERE id = $1", cabinet_id),
        ] {
            sqlx::query(q.0).bind(q.1).execute(&mut *tx).await.ok();
        }
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&db)
        .await
        .ok();
}
