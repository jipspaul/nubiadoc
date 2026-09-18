//! Tests d'intégration : les octets téléversés sont réellement écrits dans
//! l'`ObjectStorage` et relisibles via l'URL signée (#7135, #6894, #6802).
//!
//! Les trois endpoints d'upload utilisateur (coffre-fort patient, carte
//! mutuelle, document versé au dossier par le cabinet) rendaient `201` avec
//! une `storage_key` inventée sans jamais appeler `ObjectStorage::upload` :
//! `GET <download_url>` répondait `404`. Chaque test rejoue exactement le
//! scénario QA — upload → URL de téléchargement → GET de l'objet — et
//! compare les octets et le sha256 avec ceux annoncés au `201`.
//!
//! Signer : `LocalStorageSigner` (fallback sans `SCW_*`, cf. `main.rs`), dont
//! la route de service `GET /v1/storage/local/*key` lit l'`ObjectStorage`
//! (Postgres, `object_storage_blob`) — c'est ce chemin qui rendait 404.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sha2::{Digest, Sha256};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app_with_dispatcher, AppState, LocalStorageSigner, StubJobDispatcher, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-upload-bytes-persisted-7135";

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

async fn state() -> AppState {
    AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

/// Application câblée comme en production sans `SCW_*` : `LocalStorageSigner`
/// + `PostgresObjectStorage` (câblé en dur par `build_router`).
fn local_app(state: AppState) -> axum::Router {
    app_with_dispatcher(
        state,
        Arc::new(StubJobDispatcher),
        Arc::new(LocalStorageSigner::from_env()),
    )
}

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900
}

fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_practitioner_jwt(sub: Uuid, cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": sub, "kind": "pro", "cabinet_id": cabinet_id, "role": "practitioner",
                "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Corps multipart/form-data : champs texte `fields` puis un champ `file`.
fn make_multipart(
    boundary: &str,
    fields: &[(&str, &str)],
    file_bytes: &[u8],
    filename: &str,
    mime: &str,
) -> Vec<u8> {
    let mut body: Vec<u8> = Vec::new();
    for (name, value) in fields {
        body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
        body.extend_from_slice(
            format!("Content-Disposition: form-data; name=\"{name}\"\r\n\r\n").as_bytes(),
        );
        body.extend_from_slice(value.as_bytes());
        body.extend_from_slice(b"\r\n");
    }
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!("Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n")
            .as_bytes(),
    );
    body.extend_from_slice(format!("Content-Type: {mime}\r\n\r\n").as_bytes());
    body.extend_from_slice(file_bytes);
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    body
}

fn sha256_hex(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

/// PDF minimal valide (même esprit que les 47/69 octets du QA), unique par test
/// pour que le sha256 ne puisse pas être confondu avec un autre objet.
fn sample_pdf(tag: &str) -> Vec<u8> {
    format!("%PDF-1.4\n% nubia-test {tag}\n%%EOF\n").into_bytes()
}

/// PNG 1×1 (en-tête + IHDR tronqué : le MIME est vérifié, pas le décodage).
fn sample_png(tag: &str) -> Vec<u8> {
    let mut bytes = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR".to_vec();
    bytes.extend_from_slice(tag.as_bytes());
    bytes
}

async fn json_body(response: axum::response::Response) -> serde_json::Value {
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&body).unwrap()
}

/// Ramène une URL signée `LocalStorageSigner` (absolue, `PUBLIC_API_BASE`)
/// à son chemin relatif `/v1/storage/local/<key>?expires=…&sig=…`.
fn local_path(signed_url: &str) -> String {
    let idx = signed_url
        .find("/v1/storage/local/")
        .unwrap_or_else(|| panic!("URL signée hors LocalStorageSigner : {signed_url}"));
    signed_url[idx..].to_string()
}

/// `GET <download_url>` — l'étape « ← ICI » des tickets QA. Retourne
/// `(status, content_type, bytes)`.
async fn fetch_signed(state: AppState, signed_url: &str) -> (StatusCode, String, Vec<u8>) {
    let response = local_app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(local_path(signed_url))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default()
        .to_string();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap()
        .to_vec();
    (status, content_type, bytes)
}

async fn assert_served(
    state: AppState,
    signed_url: &str,
    expected: &[u8],
    expected_mime: &str,
    label: &str,
) {
    let (status, content_type, bytes) = fetch_signed(state, signed_url).await;
    assert_eq!(
        status,
        StatusCode::OK,
        "{label} : GET <download_url> doit servir l'objet (observé {status}, {} octet(s)) — \
         les octets téléversés ne sont pas écrits dans l'ObjectStorage (#7135)",
        bytes.len()
    );
    assert_eq!(content_type, expected_mime, "{label} : content-type");
    assert_eq!(bytes.len(), expected.len(), "{label} : taille");
    assert_eq!(bytes, expected, "{label} : octets");
    assert_eq!(sha256_hex(&bytes), sha256_hex(expected), "{label} : sha256");
}

// ── Fixtures patient ─────────────────────────────────────────────────────────

struct PatientFixture {
    user_id: Uuid,
    account_id: Uuid,
}

async fn seed_patient(db: &PgPool, tag: &str) -> PatientFixture {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("{tag}+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Upload')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
    PatientFixture {
        user_id,
        account_id,
    }
}

async fn cleanup_patient(db: &PgPool, f: &PatientFixture, doc_id: Option<Uuid>) {
    if let Some(doc_id) = doc_id {
        sqlx::query(
            "DELETE FROM object_storage_blob WHERE key IN \
             (SELECT storage_key FROM document WHERE id = $1)",
        )
        .bind(doc_id)
        .execute(db)
        .await
        .ok();
        sqlx::query("DELETE FROM audit_log WHERE entity_id = $1")
            .bind(doc_id)
            .execute(db)
            .await
            .ok();
        sqlx::query("DELETE FROM document WHERE id = $1")
            .bind(doc_id)
            .execute(db)
            .await
            .ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

// ── Fixture cabinet (praticien avec relation de soin) ────────────────────────

struct CabinetFixture {
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
}

async fn seed_cabinet(db: &PgPool) -> CabinetFixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("upload-cab+{}@nubia.test", prac_user_id))
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
        .bind(format!("Cabinet Upload {}", cabinet_id))
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Marc', 'Dubois')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, now() - interval '1 day', \
                 now() - interval '1 day' + interval '30 min', 'confirmed')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    CabinetFixture {
        cabinet_id,
        prac_user_id,
        prac_id,
        patient_id,
    }
}

async fn cleanup_cabinet(db: &PgPool, f: &CabinetFixture, doc_id: Option<Uuid>) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    if let Some(doc_id) = doc_id {
        sqlx::query(
            "DELETE FROM object_storage_blob WHERE key IN \
             (SELECT storage_key FROM document WHERE id = $1)",
        )
        .bind(doc_id)
        .execute(&mut *tx)
        .await
        .ok();
        sqlx::query("DELETE FROM audit_log WHERE entity_id = $1")
            .bind(doc_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM document WHERE id = $1")
            .bind(doc_id)
            .execute(&mut *tx)
            .await
            .ok();
    }
    sqlx::query("DELETE FROM appointment WHERE patient_id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(f.prac_id)
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
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

// ── A. Coffre-fort patient : POST /v1/documents ──────────────────────────────

#[tokio::test]
async fn patient_vault_upload_is_downloadable_with_same_bytes() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed_patient(&db, "upload-vault").await;
    let jwt = make_patient_jwt(f.user_id, f.account_id);

    let pdf = sample_pdf(&f.account_id.to_string());
    let boundary = "boundary-7135-vault";
    let body = make_multipart(
        boundary,
        &[
            ("category", "attestation"),
            ("filename", "QA-R77-coffre.pdf"),
        ],
        &pdf,
        "up.pdf",
        "application/pdf",
    );

    let response = local_app(state().await)
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
    let created = json_body(response).await;
    let doc_id = Uuid::parse_str(created["document_id"].as_str().unwrap()).unwrap();
    assert_eq!(created["size_bytes"].as_i64().unwrap(), pdf.len() as i64);
    assert_eq!(created["sha256"].as_str().unwrap(), sha256_hex(&pdf));

    let response = local_app(state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/documents/{doc_id}/download"))
                .header("Authorization", format!("Bearer {jwt}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let download = json_body(response).await;
    let download_url = download["download_url"].as_str().unwrap().to_string();

    assert_served(
        state().await,
        &download_url,
        &pdf,
        "application/pdf",
        "coffre-fort patient",
    )
    .await;

    cleanup_patient(&db, &f, Some(doc_id)).await;
}

// ── B. Carte mutuelle : POST /v1/account/coverage/card ───────────────────────

#[tokio::test]
async fn coverage_card_upload_is_downloadable_with_same_bytes() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed_patient(&db, "upload-card").await;
    let jwt = make_patient_jwt(f.user_id, f.account_id);

    let png = sample_png(&f.account_id.to_string());
    let boundary = "boundary-7135-card";
    let body = make_multipart(boundary, &[("side", "recto")], &png, "px.png", "image/png");

    let response = local_app(state().await)
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
    let created = json_body(response).await;
    let doc_id = Uuid::parse_str(created["document_id"].as_str().unwrap()).unwrap();
    let signed_url = created["signed_url"].as_str().unwrap().to_string();

    // L'URL renvoyée par le 201 lui-même…
    assert_served(
        state().await,
        &signed_url,
        &png,
        "image/png",
        "carte mutuelle (signed_url du 201)",
    )
    .await;

    // …et l'URL canonique du coffre-fort.
    let response = local_app(state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/documents/{doc_id}/download"))
                .header("Authorization", format!("Bearer {jwt}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let download = json_body(response).await;
    let download_url = download["download_url"].as_str().unwrap().to_string();
    assert_served(
        state().await,
        &download_url,
        &png,
        "image/png",
        "carte mutuelle (download_url)",
    )
    .await;

    cleanup_patient(&db, &f, Some(doc_id)).await;
}

// ── C. Document versé au dossier par le cabinet ──────────────────────────────

#[tokio::test]
async fn cabinet_patient_document_upload_is_downloadable_with_same_bytes() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed_cabinet(&db).await;
    let jwt = make_practitioner_jwt(f.prac_user_id, f.cabinet_id);

    let png = sample_png(&f.patient_id.to_string());
    let boundary = "boundary-7135-cabinet";
    let body = make_multipart(
        boundary,
        &[("category", "radio"), ("filename", "QA-R77-radio.png")],
        &png,
        "px.png",
        "image/png",
    );

    let response = local_app(state().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/documents", f.patient_id))
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
    let created = json_body(response).await;
    let doc_id = Uuid::parse_str(created["document_id"].as_str().unwrap()).unwrap();

    let response = local_app(state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/documents/{doc_id}/download",
                    f.patient_id
                ))
                .header("Authorization", format!("Bearer {jwt}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let download = json_body(response).await;
    let download_url = download["download_url"].as_str().unwrap().to_string();

    assert_served(
        state().await,
        &download_url,
        &png,
        "image/png",
        "document cabinet",
    )
    .await;

    // Le sha256 persisté en base correspond bien aux octets servis.
    let stored_sha: String = sqlx::query_scalar("SELECT sha256 FROM document WHERE id = $1")
        .bind(doc_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(stored_sha, sha256_hex(&png));

    cleanup_cabinet(&db, &f, Some(doc_id)).await;
}
