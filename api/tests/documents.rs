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

use nubia_api::{
    app, app_with_dispatcher, AppState, LocalStorageSigner, StorageSigner, StubJobDispatcher,
    StubMailer,
};

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
             (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, \
              sha256, size_bytes) \
             VALUES ($1, $2, $3, 'ordonnance', 'key/test', 'ordonnance.pdf', \
              'application/pdf', $4, 102400)",
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
    assert_eq!(
        doc["size_bytes"], 102400,
        "size_bytes exposé par la liste (issue #3349)"
    );
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

// ── Test : GET /v1/documents/:id/download sans token → 401 ───────────────────

#[tokio::test]
async fn download_no_auth_returns_401() {
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
                .uri(format!("/v1/documents/{}/download", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test : patient A authentifié essaie de télécharger le document de patient B → 404 ──

#[tokio::test]
async fn download_wrong_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_a_id = Uuid::new_v4();
    let account_a_id = Uuid::new_v4();
    let user_b_id = Uuid::new_v4();
    let account_b_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let patient_b_id = Uuid::new_v4();
    let doc_b_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_a_id)
    .bind(format!("dl-cross-a+{}@nubia.test", user_a_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_b_id)
    .bind(format!("dl-cross-b+{}@nubia.test", user_b_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES ($1, $2, 'Alice', 'Cross')",
    )
    .bind(account_a_id)
    .bind(user_a_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES ($1, $2, 'Bob', 'Cross')",
    )
    .bind(account_b_id)
    .bind(user_b_id)
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
        .bind(format!("Cabinet Cross {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Bob', 'Cross', $3)",
        )
        .bind(patient_b_id)
        .bind(cabinet_id)
        .bind(account_b_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO document \
             (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256) \
             VALUES ($1, $2, $3, 'ordonnance', 'key/cross', 'cross.pdf', 'application/pdf', $4)",
        )
        .bind(doc_b_id)
        .bind(cabinet_id)
        .bind(patient_b_id)
        .bind("b".repeat(64))
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

    // Patient A essaie de télécharger le document de patient B → RLS → 404 (anti-énumération)
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/documents/{}/download", doc_b_id))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_a_id, account_a_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "patient A ne doit pas voir le document de patient B (anti-énumération : 404)"
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
            .bind(doc_b_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM patient WHERE id = $1")
            .bind(patient_b_id)
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
    for uid in [user_a_id, user_b_id] {
        sqlx::query("DELETE FROM app_user WHERE id = $1")
            .bind(uid)
            .execute(&db)
            .await
            .ok();
    }
}

// ── Test : signer retourne None (config manquante, lien jamais généré) → 502 ──

struct ExpiredStorageSigner;

impl StorageSigner for ExpiredStorageSigner {
    fn sign(&self, _storage_key: &str) -> Option<String> {
        None
    }
}

#[tokio::test]
async fn download_signer_unavailable_returns_502() {
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
    .bind(format!("dl-exp+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES ($1, $2, 'Alice', 'Exp')",
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
        .bind(format!("Cabinet Exp {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Alice', 'Exp', $3)",
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
             VALUES ($1, $2, $3, 'ordonnance', 'key/exp', 'exp.pdf', 'application/pdf', $4)",
        )
        .bind(doc_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind("c".repeat(64))
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

    // Signer retournant None — simule un presigner expiré ou indisponible.
    let response = app_with_dispatcher(
        state,
        Arc::new(StubJobDispatcher),
        Arc::new(ExpiredStorageSigner),
    )
    .oneshot(
        Request::builder()
            .method("GET")
            .uri(format!("/v1/documents/{}/download", doc_id))
            .header(
                "Authorization",
                format!("Bearer {}", make_patient_jwt(user_id, account_id)),
            )
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::BAD_GATEWAY,
        "signer indisponible (lien jamais généré) doit retourner 502 upstream_unavailable, pas 410 link_expired"
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

// ── Test : LocalStorageSigner (fallback #6425) sert un lien, pas de 502 ──────

#[tokio::test]
async fn download_local_storage_signer_fallback_returns_200() {
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
    .bind(format!("dl-local+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES ($1, $2, 'Alice', 'Local')",
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
        .bind(format!("Cabinet Local {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Alice', 'Local', $3)",
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
             VALUES ($1, $2, $3, 'ordonnance', 'key/local', 'local.pdf', 'application/pdf', $4)",
        )
        .bind(doc_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind("d".repeat(64))
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

    // #6425 : sans SCW_* configurées, ScalewayStorageSigner::from_env() reste
    // `None` indéfiniment — LocalStorageSigner (choisi par `main.rs` dans ce
    // cas) doit garantir un lien exploitable, pas un 502 permanent.
    let response = app_with_dispatcher(
        state,
        Arc::new(StubJobDispatcher),
        Arc::new(LocalStorageSigner::from_env()),
    )
    .oneshot(
        Request::builder()
            .method("GET")
            .uri(format!("/v1/documents/{}/download", doc_id))
            .header(
                "Authorization",
                format!("Bearer {}", make_patient_jwt(user_id, account_id)),
            )
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::OK,
        "LocalStorageSigner doit toujours produire un lien exploitable — plus de 502 upstream_unavailable"
    );

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(
        json["download_url"]
            .as_str()
            .unwrap()
            .contains("/v1/storage/local/key/local?"),
        "download_url doit pointer sur la route de service locale : {json}"
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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    // account_id inclus pour que PatientAccountClaims tente de désérialiser ; kind:"pro" déclenche 403.
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "role": "admin",
                "account_id": Uuid::nil(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── Test : sans Authorization → 401 ──────────────────────────────────────────

#[tokio::test]
async fn documents_list_no_auth_returns_401() {
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
                .uri("/v1/documents")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test : token pro (kind:"pro") → 403 ──────────────────────────────────────

#[tokio::test]
async fn documents_list_pro_token_returns_403() {
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
                .uri("/v1/documents")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(Uuid::new_v4(), Uuid::new_v4())),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test : ?patient_account sans tutelle active → 403 ────────────────────────

#[tokio::test]
async fn documents_list_guardian_no_guardianship_returns_403() {
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
    .bind(format!("docs-guardian+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Tuteur', 'Test')",
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

    // UUID tiers quelconque — aucune relation account_guardianship.
    let other_account_id = Uuid::new_v4();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/documents?patient_account={other_account_id}"))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::FORBIDDEN,
        "tutelle inexistante doit retourner 403"
    );

    // Cleanup
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
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

// ── Test : pagination cursor-based — 2 documents, limit=1 ───────────────────

#[tokio::test]
async fn documents_list_pagination_cursor_works() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let doc1_id = Uuid::new_v4();
    let doc2_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("docs-page+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES ($1, $2, 'Page', 'Test')",
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
        .bind(format!("Cabinet Page {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Page', 'Test', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(account_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        // Plus récent (sera retourné en premier, ORDER BY created_at DESC)
        sqlx::query(
            "INSERT INTO document \
             (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256, created_at) \
             VALUES ($1, $2, $3, 'radio', 'key/pg1', 'radio1.pdf', 'application/pdf', $4, \
                     '2025-06-01 12:00:00+00')",
        )
        .bind(doc1_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind("d".repeat(64))
        .execute(&mut *tx)
        .await
        .unwrap();

        // Plus ancien (sera retourné en second)
        sqlx::query(
            "INSERT INTO document \
             (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256, created_at) \
             VALUES ($1, $2, $3, 'radio', 'key/pg2', 'radio2.pdf', 'application/pdf', $4, \
                     '2025-06-01 10:00:00+00')",
        )
        .bind(doc2_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind("e".repeat(64))
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let db_pool = app_pool().await;
    let jwt = make_patient_jwt(user_id, account_id);

    // Page 1 : limit=1 → doc1_id (le plus récent) + next_cursor présent
    let resp1 = app(AppState {
        db: db_pool.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        Request::builder()
            .method("GET")
            .uri("/v1/documents?limit=1")
            .header("Authorization", format!("Bearer {jwt}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();

    assert_eq!(resp1.status(), StatusCode::OK);
    let body1 = axum::body::to_bytes(resp1.into_body(), usize::MAX)
        .await
        .unwrap();
    let v1: serde_json::Value = serde_json::from_slice(&body1).unwrap();
    assert_eq!(
        v1["data"].as_array().unwrap().len(),
        1,
        "page 1 doit contenir 1 document"
    );
    assert_eq!(
        v1["data"][0]["id"],
        doc1_id.to_string(),
        "page 1 doit contenir le doc le plus récent"
    );
    let cursor = v1["page"]["next_cursor"]
        .as_str()
        .expect("next_cursor doit être présent en page 1")
        .to_owned();

    // Page 2 : cursor → doc2_id + next_cursor null
    let resp2 = app(AppState {
        db: db_pool.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        Request::builder()
            .method("GET")
            .uri(format!("/v1/documents?limit=1&cursor={cursor}"))
            .header("Authorization", format!("Bearer {jwt}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();

    assert_eq!(resp2.status(), StatusCode::OK);
    let body2 = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&body2).unwrap();
    assert_eq!(
        v2["data"].as_array().unwrap().len(),
        1,
        "page 2 doit contenir 1 document"
    );
    assert_eq!(
        v2["data"][0]["id"],
        doc2_id.to_string(),
        "page 2 doit contenir le doc le plus ancien"
    );
    assert!(
        v2["page"]["next_cursor"].is_null(),
        "next_cursor doit être null en page 2"
    );

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        for doc_id in [doc1_id, doc2_id] {
            sqlx::query("DELETE FROM document WHERE id = $1")
                .bind(doc_id)
                .execute(&mut *tx)
                .await
                .ok();
        }
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

/// #4756 : le coffre-fort refuse un fichier portant la signature EICAR en 422
/// (même garde que POST /account/coverage/card) — rien n'est écrit en base.
#[tokio::test]
async fn documents_upload_eicar_returns_422() {
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
    .bind(format!("upload-eicar+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Eicar')",
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

    let eicar = b"X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*";
    let boundary = "testboundaryeicar001";
    let body = make_upload_multipart(boundary, "facture", eicar, "eicar.pdf", "application/pdf");

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

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM document WHERE patient_account_id = $1")
            .bind(account_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(count, 0, "aucun document ne doit être stocké");

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
