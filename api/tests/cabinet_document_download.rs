//! Tests d'intégration : GET /v1/cabinet/patients/:id/documents/:doc_id/download (#4286)

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-document-download-4286";

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

fn state_with(db: PgPool) -> AppState {
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

fn make_practitioner_jwt(sub: Uuid, cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": sub, "kind": "pro", "cabinet_id": cabinet_id, "role": "practitioner",
                "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_secretary_jwt(sub: Uuid, cabinet_id: Uuid, secretariat_id: Option<Uuid>) -> String {
    encode(
        &Header::default(),
        &json!({"sub": sub, "kind": "pro", "cabinet_id": cabinet_id, "role": "secretary",
                "secretariat_id": secretariat_id, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
    doc_id: Uuid,
    secretariat_id: Uuid,
}

/// Fixture : cabinet, secrétariat, provider lié au secrétariat, praticien,
/// patient et un document de catégorie `category`. Si `with_appointment` est
/// `true`, crée un `appointment` liant le praticien au patient — satisfait à
/// la fois la garde §14 (relation de soin praticien) et la garde R10 (scope
/// secrétariat, qui joint via cet appointment).
async fn seed(db: &PgPool, category: &str, with_appointment: bool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let doc_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("cabdoc-dl+{}@nubia.test", prac_user_id))
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
        .bind(format!("Cabinet DocDL Test {}", cabinet_id))
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
        "INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Secrétariat DocDL Test')",
    )
    .bind(secretariat_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, practitioner_id, cabinet_id, user_id, display_name, specialite) \
         VALUES ($1, $2, $3, $4, 'Dr DocDL', 'dentaire')",
    )
    .bind(provider_id)
    .bind(prac_id)
    .bind(cabinet_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO provider_secretariat (provider_id, secretariat_id, active) \
         VALUES ($1, $2, true)",
    )
    .bind(provider_id)
    .bind(secretariat_id)
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

    if with_appointment {
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
    }

    sqlx::query(
        "INSERT INTO document \
         (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256) \
         VALUES ($1, $2, $3, $4, 'key/cabdoc-dl-test', 'doc.pdf', 'application/pdf', $5)",
    )
    .bind(doc_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(category)
    .bind("c".repeat(64))
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        prac_user_id,
        prac_id,
        patient_id,
        doc_id,
        secretariat_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM audit_log WHERE entity_id = $1")
        .bind(f.doc_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM document WHERE id = $1")
        .bind(f.doc_id)
        .execute(&mut *tx)
        .await
        .ok();
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
    sqlx::query("DELETE FROM provider_secretariat WHERE secretariat_id = $1")
        .bind(f.secretariat_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE practitioner_id = $1")
        .bind(f.prac_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM secretariat WHERE id = $1")
        .bind(f.secretariat_id)
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

fn download_uri(patient_id: Uuid, doc_id: Uuid) -> String {
    format!("/v1/cabinet/patients/{patient_id}/documents/{doc_id}/download")
}

// ── Test 1 : sans Authorization → 401 ────────────────────────────────────────

#[tokio::test]
async fn cabinet_document_download_no_auth_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();

    let response = app(state_with(db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(download_uri(Uuid::new_v4(), Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 2 : praticien avec relation de soin, catégorie clinique → 200 ──────

#[tokio::test]
async fn cabinet_document_download_practitioner_with_appointment_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "radio", true).await;

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(download_uri(f.patient_id, f.doc_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_jwt(f.prac_user_id, f.cabinet_id)
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
    assert!(
        v["download_url"].as_str().is_some_and(|s| !s.is_empty()),
        "download_url doit être présent et non vide"
    );
    assert!(v["expires_at"].as_str().is_some());

    cleanup(&db, &f).await;
}

// ── Test 3 : praticien SANS relation de soin, catégorie clinique → 403 (§14) ─

#[tokio::test]
async fn cabinet_document_download_practitioner_without_appointment_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "radio", false).await;

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(download_uri(f.patient_id, f.doc_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_jwt(f.prac_user_id, f.cabinet_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup(&db, &f).await;
}

// ── Test 4 : secrétaire dans le scope secrétariat, catégorie clinique → 403 (§14) ─
//
// Le secrétariat DOIT être en scope (sinon la garde R10 renvoie 404 avant
// même d'atteindre la garde §14 — cf. test 4b) : with_appointment=true crée
// l'appointment nécessaire au JOIN R10 (provider → provider_secretariat).

#[tokio::test]
async fn cabinet_document_download_secretary_clinical_category_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "ordonnance", true).await;

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(download_uri(f.patient_id, f.doc_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_secretary_jwt(f.prac_user_id, f.cabinet_id, Some(f.secretariat_id))
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup(&db, &f).await;
}

// ── Test 4b : secrétaire hors scope secrétariat (R10) → 404, même catégorie non-clinique ─
//
// Pas de fuite d'existence via un 403 — même contrat que list_patient_documents.

#[tokio::test]
async fn cabinet_document_download_secretary_out_of_scope_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "devis", true).await;

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(download_uri(f.patient_id, f.doc_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_secretary_jwt(f.prac_user_id, f.cabinet_id, None)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}

// ── Test 5 : document inexistant → 404 ───────────────────────────────────────

#[tokio::test]
async fn cabinet_document_download_unknown_document_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "radio", true).await;

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(download_uri(f.patient_id, Uuid::new_v4()))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_jwt(f.prac_user_id, f.cabinet_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}
