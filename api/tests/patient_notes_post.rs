//! Tests d'intégration : POST /v1/cabinet/patients/:id/notes (§14)
//!
//! Tests requis par l'issue #661 :
//! 1. POST .../notes → 201
//! 2. Token secretary → 403 (R.4127-72)
//! 3. content_ciphertext stocké ≠ clair en base

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

const JWT_SECRET: &str = "test-secret-notes";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "practitioner".into(),
            exp: exp(),
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
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
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "secretary".into(),
            exp: exp(),
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère les fixtures minimales (cabinet + app_user + patient).
/// Retourne `(cabinet_id, user_id, patient_id)`.
async fn insert_fixtures(db: &PgPool) -> (Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    // app_user — hors RLS (pas de current_user_id requis pour INSERT depuis nubia_app
    // tant qu'aucune FORCE policy n'existe sur app_user sans current_user_id).
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("notes-prac+{}@nubia.test", user_id))
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
         VALUES ($1, 'Cabinet Notes Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Jean', 'Test')",
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
    sqlx::query("DELETE FROM clinical_note WHERE patient_id = $1")
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

// ── Test 1 : POST .../notes avec token praticien → 201 ───────────────────────

#[tokio::test]
async fn add_clinical_note_practitioner_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);
    let body = json!({
        "note_kind": "observation",
        "text": "Patient asymptomatique, contrôle à 6 mois."
    });

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/notes", patient_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
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
    assert!(
        v["note_id"]
            .as_str()
            .and_then(|s| s.parse::<Uuid>().ok())
            .is_some(),
        "note_id doit être un UUID valide"
    );
    assert!(
        v["created_at"].is_string(),
        "created_at doit être une chaîne"
    );

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 2 : Token secretary → 403 ───────────────────────────────────────────

#[tokio::test]
async fn add_clinical_note_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id);
    let body = json!({ "note_kind": "observation", "text": "Tentative secrétaire." });

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/notes", patient_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 3 : content_ciphertext en base ≠ texte en clair ─────────────────────

#[tokio::test]
async fn add_clinical_note_content_is_encrypted_in_db() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let plain_text = "Carie mésiale dent 36, traitement endodontique prévu.";
    let token = make_practitioner_token(user_id, cabinet_id);
    let body = json!({
        "note_kind": "act",
        "text": plain_text,
        "tooth": "36",
        "act_ref": { "label": "Traitement canalaire", "ccam": "HBFD001" }
    });

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/notes", patient_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
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
    let note_id: Uuid = v["note_id"].as_str().unwrap().parse().unwrap();

    // Lit directement le ciphertext depuis la DB (rôle owner — bypasse RLS).
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT content_ciphertext FROM clinical_note WHERE id = $1")
        .bind(note_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    let ciphertext: Vec<u8> = row.try_get("content_ciphertext").unwrap();
    // Le ciphertext ne doit pas contenir le texte en clair.
    assert!(
        !ciphertext
            .windows(plain_text.len())
            .any(|w| w == plain_text.as_bytes()),
        "content_ciphertext ne doit pas contenir le texte en clair"
    );
    // Le ciphertext doit être non vide et différent du texte clair.
    assert!(!ciphertext.is_empty(), "ciphertext ne doit pas être vide");
    assert_ne!(ciphertext, plain_text.as_bytes(), "ciphertext ≠ clair");

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}
