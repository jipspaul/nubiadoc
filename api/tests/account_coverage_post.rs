//! Tests d'intégration : POST /v1/account/coverage/card (T-API-T006)

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

const JWT_SECRET: &str = "test-jwt-secret-coverage-post";

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

fn make_pro_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Construit un corps multipart/form-data à deux champs : `side` et `file`.
fn make_multipart(
    boundary: &str,
    side: &str,
    file_bytes: &[u8],
    filename: &str,
    mime: &str,
) -> Vec<u8> {
    let mut body: Vec<u8> = Vec::new();

    // Champ "side"
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(b"Content-Disposition: form-data; name=\"side\"\r\n");
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(side.as_bytes());
    body.extend_from_slice(b"\r\n");

    // Champ "file"
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!("Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n")
            .as_bytes(),
    );
    body.extend_from_slice(format!("Content-Type: {mime}\r\n").as_bytes());
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(file_bytes);
    body.extend_from_slice(b"\r\n");

    // Délimiteur de fin
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    body
}

// ── Test 1 : happy path — upload JPEG valide → 201 + document_id UUID ────────

#[tokio::test]
async fn coverage_card_post_jpeg_returns_201() {
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
    .bind(format!("cpost+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Post')",
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
    let jwt = make_patient_jwt(user_id, account_id);

    // Octets JPEG minimaux (magic bytes)
    let jpeg_stub = b"\xff\xd8\xff\xe0\x00\x10JFIF";
    let boundary = "bound-cpost-happy";
    let body = make_multipart(boundary, "recto", jpeg_stub, "mutuelle_recto.jpg", "image/jpeg");

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/coverage/card")
                .header("Authorization", format!("Bearer {jwt}"))
                .header(
                    "Content-Type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let resp_body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&resp_body).unwrap();

    let doc_id_str = v["document_id"]
        .as_str()
        .expect("document_id doit être présent");
    Uuid::parse_str(doc_id_str).expect("document_id doit être un UUID valide");
    assert!(v["signed_url"].is_string(), "signed_url doit être présent");

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : sans JWT → 401 ────────────────────────────────────────────────────

#[tokio::test]
async fn coverage_card_post_no_jwt_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let boundary = "bound-cpost-nojwt";
    let body = make_multipart(
        boundary,
        "recto",
        b"\xff\xd8\xff",
        "test.jpg",
        "image/jpeg",
    );

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/coverage/card")
                .header(
                    "Content-Type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 3 : JWT pro (kind != "patient") → 403 ────────────────────────────────

#[tokio::test]
async fn coverage_card_post_pro_jwt_returns_403() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let pro_jwt = make_pro_jwt(Uuid::new_v4());
    let boundary = "bound-cpost-projwt";
    let body = make_multipart(
        boundary,
        "recto",
        b"\xff\xd8\xff",
        "test.jpg",
        "image/jpeg",
    );

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/coverage/card")
                .header("Authorization", format!("Bearer {pro_jwt}"))
                .header(
                    "Content-Type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 4 : valeur `side` invalide → 422 ─────────────────────────────────────

#[tokio::test]
async fn coverage_card_post_invalid_side_returns_422() {
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
    .bind(format!("cpost-side+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'Side')",
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
    let jwt = make_patient_jwt(user_id, account_id);

    // "front" n'est pas une valeur autorisée — seuls "recto" et "verso" le sont
    let boundary = "bound-cpost-side";
    let body = make_multipart(
        boundary,
        "front",
        b"\xff\xd8\xff",
        "test.jpg",
        "image/jpeg",
    );

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/coverage/card")
                .header("Authorization", format!("Bearer {jwt}"))
                .header(
                    "Content-Type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 5 : fichier contenant la signature EICAR → 422 (antivirus stub) ──────

#[tokio::test]
async fn coverage_card_post_eicar_returns_422() {
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
    .bind(format!("cpost-eicar+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Eve', 'Eicar')",
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
    let jwt = make_patient_jwt(user_id, account_id);

    // Signature EICAR standard
    let eicar = b"X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*";
    let boundary = "bound-cpost-eicar";
    let body = make_multipart(boundary, "verso", eicar, "eicar.pdf", "application/pdf");

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/coverage/card")
                .header("Authorization", format!("Bearer {jwt}"))
                .header(
                    "Content-Type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}
