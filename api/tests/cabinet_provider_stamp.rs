//! Tests d'intégration #7148 (DP-F25.b) :
//! - POST /v1/cabinet/provider/signature → 201, `provider.signature_image_id` posé
//! - POST /v1/cabinet/provider/stamp → 201, `provider.stamp_image_id` posé
//! - MIME hors JPEG → 422
//! - non-praticien (secretary) → 403

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

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

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    }
}

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "secretary".into(),
            exp,
        },
        &EncodingKey::from_secret(b"test-secret"),
    )
    .unwrap()
}

/// Enregistre un cabinet pro (admin + practitioner + provider), renvoie
/// `(access_token, admin_user_id, cabinet_id)`.
async fn register_pro(db: PgPool, email: &str) -> (String, Uuid, Uuid) {
    let body = json!({
        "email": email,
        "password": "password1",
        "cabinet": { "raison_sociale": "Cabinet Stamp", "siret": null, "specialite": "dentaire" },
        "practitioner": { "first_name": "Admin", "last_name": "Test", "rpps": null, "adeli": null }
    });
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/pro/register")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let token = v["access_token"].as_str().unwrap().to_string();
    let account_id: Uuid = v["account_id"].as_str().unwrap().parse().unwrap();
    let cabinet_id: Uuid = v["cabinet_id"].as_str().unwrap().parse().unwrap();
    (token, account_id, cabinet_id)
}

/// JPEG minimal (SOI + SOF0 3 composantes + EOI) — reconnu par le nombre
/// magique (`file_scan`) ET par `pdf_text::JpegImage::parse` (marqueur SOF).
fn fake_jpeg() -> Vec<u8> {
    let width: u16 = 100;
    let height: u16 = 40;
    let components: u8 = 3;
    let mut b = vec![0xFFu8, 0xD8];
    b.extend_from_slice(&[0xFF, 0xC0]);
    let seg_len = 2 + 1 + 2 + 2 + 1 + 3 * components as usize;
    b.push((seg_len >> 8) as u8);
    b.push((seg_len & 0xFF) as u8);
    b.push(8);
    b.push((height >> 8) as u8);
    b.push((height & 0xFF) as u8);
    b.push((width >> 8) as u8);
    b.push((width & 0xFF) as u8);
    b.push(components);
    for c in 0..components {
        b.extend_from_slice(&[c + 1, 0x11, 0]);
    }
    b.extend_from_slice(&[0xFF, 0xD9]);
    b
}

fn make_upload_multipart(
    boundary: &str,
    file_bytes: &[u8],
    file_name: &str,
    mime: &str,
) -> Vec<u8> {
    let mut body: Vec<u8> = Vec::new();
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

async fn cleanup(email: &str) {
    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(email)
        .execute(&owner_pool().await)
        .await
        .ok();
}

// ── Test 1 : signature JPEG valide → 201, provider.signature_image_id posé ──

#[tokio::test]
async fn upload_signature_happy_path_returns_201() {
    if !db_available() {
        return;
    }
    let email = format!("stamp_sig_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, user_id, cabinet_id) = register_pro(db.clone(), &email).await;

    let boundary = "X-BOUNDARY-SIG";
    let multipart = make_upload_multipart(boundary, &fake_jpeg(), "signature.jpg", "image/jpeg");

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/provider/signature")
                .header("Authorization", format!("Bearer {}", token))
                .header(
                    "Content-Type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(multipart))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let document_id: Uuid = v["document_id"].as_str().unwrap().parse().unwrap();

    let row = sqlx::query("SELECT category, cabinet_id FROM document WHERE id = $1")
        .bind(document_id)
        .fetch_one(&owner_pool().await)
        .await
        .unwrap();
    let category: String = row.try_get("category").unwrap();
    let doc_cabinet_id: Uuid = row.try_get("cabinet_id").unwrap();
    assert_eq!(category, "signature");
    assert_eq!(doc_cabinet_id, cabinet_id);

    let provider_row = sqlx::query(
        "SELECT signature_image_id FROM provider WHERE cabinet_id = $1 AND user_id = $2",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .fetch_one(&owner_pool().await)
    .await
    .unwrap();
    let signature_image_id: Option<Uuid> = provider_row.try_get("signature_image_id").unwrap();
    assert_eq!(signature_image_id, Some(document_id));

    cleanup(&email).await;
}

// ── Test 2 : tampon JPEG valide → 201, provider.stamp_image_id posé ─────────

#[tokio::test]
async fn upload_stamp_happy_path_returns_201() {
    if !db_available() {
        return;
    }
    let email = format!("stamp_tampon_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, user_id, cabinet_id) = register_pro(db.clone(), &email).await;

    let boundary = "X-BOUNDARY-STAMP";
    let multipart = make_upload_multipart(boundary, &fake_jpeg(), "tampon.jpg", "image/jpeg");

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/provider/stamp")
                .header("Authorization", format!("Bearer {}", token))
                .header(
                    "Content-Type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(multipart))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let document_id: Uuid = v["document_id"].as_str().unwrap().parse().unwrap();

    let row = sqlx::query("SELECT category FROM document WHERE id = $1")
        .bind(document_id)
        .fetch_one(&owner_pool().await)
        .await
        .unwrap();
    let category: String = row.try_get("category").unwrap();
    assert_eq!(category, "tampon");

    let provider_row =
        sqlx::query("SELECT stamp_image_id FROM provider WHERE cabinet_id = $1 AND user_id = $2")
            .bind(cabinet_id)
            .bind(user_id)
            .fetch_one(&owner_pool().await)
            .await
            .unwrap();
    let stamp_image_id: Option<Uuid> = provider_row.try_get("stamp_image_id").unwrap();
    assert_eq!(stamp_image_id, Some(document_id));

    cleanup(&email).await;
}

// ── Test 3 : MIME hors JPEG (PNG) → 422 ──────────────────────────────────────

#[tokio::test]
async fn upload_signature_rejects_non_jpeg_mime() {
    if !db_available() {
        return;
    }
    let email = format!("stamp_png_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _, _) = register_pro(db.clone(), &email).await;

    let png_bytes: Vec<u8> = vec![0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0];
    let boundary = "X-BOUNDARY-PNG";
    let multipart = make_upload_multipart(boundary, &png_bytes, "signature.png", "image/png");

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/provider/signature")
                .header("Authorization", format!("Bearer {}", token))
                .header(
                    "Content-Type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(multipart))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&email).await;
}

// ── Test 4 : secretary (non praticien) → 403 ─────────────────────────────────

#[tokio::test]
async fn upload_signature_as_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("stamp_403_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_, account_id, cabinet_id) = register_pro(db.clone(), &email).await;
    let secretary_token = make_secretary_token(account_id, cabinet_id);

    let boundary = "X-BOUNDARY-403";
    let multipart = make_upload_multipart(boundary, &fake_jpeg(), "signature.jpg", "image/jpeg");

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/provider/signature")
                .header("Authorization", format!("Bearer {}", secretary_token))
                .header(
                    "Content-Type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(multipart))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup(&email).await;
}
