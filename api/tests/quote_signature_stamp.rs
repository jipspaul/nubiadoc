//! Test d'intégration #7148 (DP-F25.b) : signature et tampon du praticien
//! apposés sur le PDF de devis signé (`billing::render_quote_pdf`).

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

const JWT_SECRET: &str = "test-jwt-secret-quote-signature-stamp";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "role": role, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// JPEG minimal (SOI + SOF0 3 composantes + EOI) — reconnu par le nombre
/// magique (`file_scan`) ET par `pdf_text::JpegImage::parse` (marqueur SOF).
fn fake_jpeg() -> Vec<u8> {
    let (width, height, components): (u16, u16, u8) = (120, 50, 3);
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

fn make_stamp_multipart(boundary: &str, file_bytes: &[u8]) -> Vec<u8> {
    let mut body: Vec<u8> = Vec::new();
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        b"Content-Disposition: form-data; name=\"file\"; filename=\"stamp.jpg\"\r\n",
    );
    body.extend_from_slice(b"Content-Type: image/jpeg\r\n\r\n");
    body.extend_from_slice(file_bytes);
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    body
}

#[tokio::test]
async fn sign_quote_embeds_practitioner_signature_and_stamp_on_pdf() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let patient_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("qss-patient+{patient_user_id}@nubia.test"))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Claire', 'Devis')",
    )
    .bind(account_id)
    .bind(patient_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("qss-prac+{prac_user_id}@nubia.test"))
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
        .bind(format!("Cabinet QSS Test {cabinet_id}"))
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
            "INSERT INTO provider (id, practitioner_id, cabinet_id, user_id, display_name) \
             VALUES ($1, $2, $3, $4, 'Dr Amélie Rousseau')",
        )
        .bind(provider_id)
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient \
             (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Claire', 'Devis', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(account_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO quote \
             (id, cabinet_id, patient_id, practitioner_id, status, total_amount, currency) \
             VALUES ($1, $2, $3, $4, 'sent', 150.00, 'EUR')",
        )
        .bind(quote_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let prac_token = make_pro_jwt(prac_user_id, cabinet_id, "practitioner");

    for (path, boundary) in [
        ("/v1/cabinet/provider/signature", "X-SIG"),
        ("/v1/cabinet/provider/stamp", "X-STAMP"),
    ] {
        let response = app(make_state(app_pool().await))
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(path)
                    .header("Authorization", format!("Bearer {prac_token}"))
                    .header(
                        "Content-Type",
                        format!("multipart/form-data; boundary={boundary}"),
                    )
                    .body(Body::from(make_stamp_multipart(boundary, &fake_jpeg())))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::CREATED);
    }

    // Signe le devis (patient) — génère le PDF via `generate_quote_document`.
    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/quotes/{quote_id}/sign"))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(patient_user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    let storage_key: String = sqlx::query(
        "SELECT d.storage_key FROM quote q \
         JOIN document d ON d.id = q.document_id \
         WHERE q.id = $1",
    )
    .bind(quote_id)
    .fetch_one(&db)
    .await
    .unwrap()
    .try_get("storage_key")
    .unwrap();

    let blob = sqlx::query("SELECT bytes FROM object_storage_blob WHERE key = $1")
        .bind(&storage_key)
        .fetch_one(&db)
        .await
        .unwrap();
    let bytes: Vec<u8> = blob.try_get("bytes").unwrap();
    assert!(bytes.starts_with(b"%PDF-1.4"));
    let text = String::from_utf8_lossy(&bytes);
    assert_eq!(
        text.matches("/Subtype /Image").count(),
        2,
        "signature ET tampon doivent être apposés : {text}"
    );
    assert!(text.contains("/Filter /DCTDecode"));

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM audit_log WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM quote WHERE id = $1")
            .bind(quote_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM document WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM patient WHERE id = $1")
            .bind(patient_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM provider WHERE id = $1")
            .bind(provider_id)
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
        .bind(patient_user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}
