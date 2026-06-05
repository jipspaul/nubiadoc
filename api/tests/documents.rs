//! Tests d'intégration : GET /v1/documents

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

const JWT_SECRET: &str = "test-jwt-secret-documents";

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

// ── Test 1 : happy-path — patient avec 1 document → 200 avec le document ──────

#[tokio::test]
async fn documents_happy_path_returns_document() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let doc_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("docs-happy+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Doc')",
    )
    .bind(account_id)
    .bind(user_id)
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
        .bind(format!("Cabinet Docs Test {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient \
             (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Alice', 'Doc', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(account_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO document \
             (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256) \
             VALUES ($1, $2, $3, 'ordonnance', 'key/test', 'ordonnance.pdf', 'application/pdf', $4)",
        )
        .bind(doc_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind("a".repeat(64))
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
                .uri("/v1/documents")
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
    assert!(!data.is_empty(), "data ne doit pas être vide");

    let doc = &data[0];
    assert_eq!(doc["id"], doc_id.to_string(), "id doit correspondre");
    assert_eq!(doc["category"], "ordonnance");
    assert_eq!(doc["filename"], "ordonnance.pdf");
    assert_eq!(doc["mime_type"], "application/pdf");
    assert!(
        doc["created_at"].is_string(),
        "created_at doit être présent"
    );
    assert!(
        v["page"]["next_cursor"].is_null(),
        "next_cursor doit être null"
    );

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM document WHERE id = $1")
            .bind(doc_id)
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test pour POST /v1/documents ─────────────────────────────────────────────

/// Construit un corps multipart minimal pour POST /v1/documents.
fn make_upload_multipart(
    boundary: &str,
    category: &str,
    file_bytes: &[u8],
    file_name: &str,
    mime: &str,
) -> Vec<u8> {
    let mut body: Vec<u8> = Vec::new();

    // Champ "category"
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(b"Content-Disposition: form-data; name=\"category\"\r\n");
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(category.as_bytes());
    body.extend_from_slice(b"\r\n");

    // Champ "file"
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!("Content-Disposition: form-data; name=\"file\"; filename=\"{file_name}\"\r\n")
            .as_bytes(),
    );
    body.extend_from_slice(format!("Content-Type: {mime}\r\n").as_bytes());
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(file_bytes);
    body.extend_from_slice(b"\r\n");

    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    body
}

// ── Test : upload PDF valide + catégorie valide → 201 avec document_id UUID ───

#[tokio::test]
async fn documents_upload_pdf_happy_path() {
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
    .bind(format!("upload+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Upload')",
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

    // PDF minimal (magic bytes %PDF-)
    let pdf_stub = b"%PDF-1.4\n%%EOF\n";
    let boundary = "testboundaryupload001";
    let body = make_upload_multipart(
        boundary,
        "ordonnance",
        pdf_stub,
        "ordonnance.pdf",
        "application/pdf",
    );

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/documents")
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
    let doc_id = Uuid::parse_str(doc_id_str).expect("document_id doit être un UUID valide");
    assert_eq!(v["category"], "ordonnance");
    assert_eq!(v["filename"], "ordonnance.pdf");
    assert!(v["size_bytes"].as_i64().unwrap_or(0) > 0);
    let sha = v["sha256"].as_str().expect("sha256 doit être présent");
    assert_eq!(
        sha.len(),
        64,
        "sha256 doit être une chaîne hex de 64 caractères"
    );

    // Cleanup — supprimer le document avant le compte (pas de cascade patient_account→document)
    sqlx::query("DELETE FROM document WHERE id = $1")
        .bind(doc_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test : catégorie invalide → 422 validation_error ─────────────────────────

#[tokio::test]
async fn documents_upload_invalid_category_returns_422() {
    // Pas de requête DB : la validation de catégorie précède tout accès base.
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

    let boundary = "testboundaryinvalidcat";
    let body = make_upload_multipart(
        boundary,
        "categorie_inexistante",
        b"%PDF-1.4\n%%EOF\n",
        "test.pdf",
        "application/pdf",
    );

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/documents")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(Uuid::new_v4(), Uuid::new_v4())
                    ),
                )
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

    let resp_body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&resp_body).unwrap();
    assert_eq!(v["code"], "validation_error");
}

// ── Test 2 : catégorie inconnue → 200 liste vide ───────────────────────────────

#[tokio::test]
async fn documents_unknown_category_returns_empty() {
    // Retour immédiat sans requête DB — pas besoin de DB disponible.
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

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/documents?category=categorie_inexistante")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(Uuid::new_v4(), Uuid::new_v4())
                    ),
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

    assert_eq!(
        v["data"],
        json!([]),
        "data doit être vide pour une catégorie inconnue"
    );
    assert!(
        v["page"]["next_cursor"].is_null(),
        "next_cursor doit être null"
    );
}
