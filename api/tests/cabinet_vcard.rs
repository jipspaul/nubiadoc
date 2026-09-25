//! Tests d'intégration : GET /v1/cabinet/vcard + GET /v1/cabinet/vcard/qr.png
//! (DP-F26.a, #7146) — même infra de fixtures que `cabinets_info_get.rs`.

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

const JWT_SECRET: &str = "test-secret-cabvcard";

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
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    }
}

/// Insère un cabinet minimal avec settings JSON (contact + adresse) et
/// renvoie `cabinet_id`.
async fn insert_cabinet(db: &PgPool, suffix: &str) -> Uuid {
    let cabinet_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite, settings) \
         VALUES ($1, $2, 'dentaire', $3::jsonb)",
    )
    .bind(cabinet_id)
    .bind(format!("Cabinet Vcard {}", suffix))
    .bind(json!({
        "contact": { "phone": "0102030405", "email": "cabinet@nubia.test" },
        "address": { "rue": "12 rue de la Paix", "cp": "75001", "ville": "Paris" },
    }))
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    cabinet_id
}

async fn cleanup_cabinet(db: &PgPool, cabinet_id: Uuid) {
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

/// JWT pro (kind = "pro") valide pour `cabinet_id`.
fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({ "sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "exp": exp }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// JWT patient (kind = "patient") — doit être rejeté (403) sur ces routes pro.
fn make_patient_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({ "sub": user_id, "kind": "patient", "account_id": user_id, "exp": exp }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── GET /v1/cabinet/vcard ─────────────────────────────────────────────────

#[tokio::test]
async fn get_cabinet_vcard_happy_path_returns_valid_vcard() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let cabinet_id = insert_cabinet(&db, &suffix).await;
    let jwt = make_pro_jwt(Uuid::new_v4(), cabinet_id);

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/vcard")
                .header("Authorization", format!("Bearer {}", jwt))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let content_type = response
        .headers()
        .get(axum::http::header::CONTENT_TYPE)
        .unwrap()
        .to_str()
        .unwrap()
        .to_string();
    assert!(content_type.starts_with("text/vcard"));

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let vcard = String::from_utf8(body.to_vec()).unwrap();

    assert!(vcard.starts_with("BEGIN:VCARD\r\n"), "{vcard}");
    assert!(vcard.ends_with("END:VCARD\r\n"), "{vcard}");
    assert!(vcard.contains("VERSION:4.0\r\n"));
    assert!(vcard.contains(&format!("FN:Cabinet Vcard {}\r\n", suffix)));
    assert!(vcard.contains("TEL;TYPE=work,voice:0102030405\r\n"));
    assert!(vcard.contains("EMAIL;TYPE=work:cabinet@nubia.test\r\n"));
    assert!(vcard.contains("ADR;TYPE=work:;;12 rue de la Paix;Paris;;75001;\r\n"));

    cleanup_cabinet(&db, cabinet_id).await;
}

#[tokio::test]
async fn get_cabinet_vcard_without_jwt_returns_401() {
    if !db_available() {
        return;
    }
    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/vcard")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn get_cabinet_vcard_with_patient_jwt_returns_403() {
    if !db_available() {
        return;
    }
    let jwt = make_patient_jwt(Uuid::new_v4());

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/vcard")
                .header("Authorization", format!("Bearer {}", jwt))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── GET /v1/cabinet/vcard/qr.png ──────────────────────────────────────────

#[tokio::test]
async fn get_cabinet_vcard_qr_png_happy_path_returns_readable_png() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let cabinet_id = insert_cabinet(&db, &suffix).await;
    let jwt = make_pro_jwt(Uuid::new_v4(), cabinet_id);

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/vcard/qr.png")
                .header("Authorization", format!("Bearer {}", jwt))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let content_type = response
        .headers()
        .get(axum::http::header::CONTENT_TYPE)
        .unwrap()
        .to_str()
        .unwrap()
        .to_string();
    assert_eq!(content_type, "image/png");

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();

    // Signature PNG (RFC 2083) : garantit un fichier PNG structurellement
    // valide, décodable par n'importe quel lecteur/scanner standard.
    assert!(body.starts_with(b"\x89PNG\r\n\x1a\n"));
    // IHDR : longueur(4)=13, type(4)="IHDR", largeur(4), hauteur(4).
    assert_eq!(&body[12..16], b"IHDR");
    let width = u32::from_be_bytes(body[16..20].try_into().unwrap());
    let height = u32::from_be_bytes(body[20..24].try_into().unwrap());
    assert_eq!(width, height, "le QR doit être carré");
    assert!(width > 0);

    cleanup_cabinet(&db, cabinet_id).await;
}

#[tokio::test]
async fn get_cabinet_vcard_qr_png_without_jwt_returns_401() {
    if !db_available() {
        return;
    }
    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/vcard/qr.png")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
