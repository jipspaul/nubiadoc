//! Tests d'intégration : garde §14 sur POST /v1/cabinet/patients/:id/documents (#3834).
//!
//! Le GET (list_patient_documents) interdisait déjà aux non-praticiens (secretary,
//! admin) toute catégorie clinique faute de relation de soin possible ; le POST
//! (upload_patient_document) n'avait AUCUNE garde équivalente — une secrétaire
//! pouvait créer une ordonnance/radio/cbct/cr/consentement qu'elle ne peut même
//! pas relire ensuite. Fichier dédié : cabinet_patient_detail.rs est déjà au
//! plafond de taille (842 lignes > 700).

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

const JWT_SECRET: &str = "test-secret-patient-doc-upload-guard-3834";

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

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900
}

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": sub, "kind": "pro", "cabinet_id": cabinet_id, "role": "secretary",
                "secretariat_id": Option::<Uuid>::None, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère les fixtures minimales (cabinet + app_user secrétaire + patient).
/// Retourne `(cabinet_id, user_id, patient_id)`.
async fn insert_fixtures(db: &PgPool) -> (Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("docupload3834+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Doc Upload Guard Test', 'dentaire')",
    )
    .bind(cabinet_id)
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

    tx.commit().await.unwrap();

    (cabinet_id, user_id, patient_id)
}

async fn cleanup_fixtures(db: &PgPool, cabinet_id: Uuid, user_id: Uuid, patient_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM document WHERE patient_id = $1")
        .bind(patient_id)
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

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
}

async fn upload(patient_id: Uuid, token: &str, category: &str, db: PgPool) -> StatusCode {
    let boundary = "----TestBoundary3834";
    let body_bytes = format!(
        "--{boundary}\r\n\
         Content-Disposition: form-data; name=\"category\"\r\n\r\n\
         {category}\r\n\
         --{boundary}\r\n\
         Content-Disposition: form-data; name=\"file\"; filename=\"doc.pdf\"\r\n\
         Content-Type: application/pdf\r\n\r\n\
         %PDF-stub\r\n\
         --{boundary}--\r\n"
    );
    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/documents", patient_id))
                .header(
                    "content-type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body_bytes))
                .unwrap(),
        )
        .await
        .unwrap();
    resp.status()
}

// ── Test : secrétaire upload catégorie CLINIQUE → 403 (#3834) ───────────────

#[tokio::test]
async fn upload_clinical_category_by_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;
    let token = make_secretary_token(user_id, cabinet_id);

    for category in ["ordonnance", "radio", "cbct", "cr", "consentement"] {
        let status = upload(patient_id, &token, category, app_pool().await).await;
        assert_eq!(
            status,
            StatusCode::FORBIDDEN,
            "une secrétaire ne doit pas pouvoir créer un document '{category}' (clinique)"
        );
    }

    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM document WHERE patient_id = $1")
        .bind(patient_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(
        count, 0,
        "aucun document clinique ne doit avoir été persisté"
    );

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test : secrétaire upload catégorie NON-clinique → 201 (pas de sur-blocage) ──

#[tokio::test]
async fn upload_non_clinical_category_by_secretary_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;
    let token = make_secretary_token(user_id, cabinet_id);

    let status = upload(patient_id, &token, "devis", app_pool().await).await;
    assert_eq!(
        status,
        StatusCode::CREATED,
        "une catégorie administrative (devis) doit rester autorisée à une secrétaire"
    );

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}
