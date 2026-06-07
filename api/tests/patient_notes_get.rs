//! Tests d'intégration : GET /v1/cabinet/patients/:id/notes (§14)
//!
//! Tests requis par l'issue #783 :
//! 1. GET .../notes avec token secretary → 403 (R.4127-72)
//! 2. GET .../notes avec token praticien → 200, liste les notes non-supprimées, text déchiffré

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

const JWT_SECRET: &str = "test-secret-notes-get";

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

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("notes-get+{}@nubia.test", user_id))
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
         VALUES ($1, 'Cabinet Notes Get Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Test')",
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

// ── Test 1 : GET .../notes avec token secretary → 403 ────────────────────────

#[tokio::test]
async fn list_patient_notes_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/notes", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 2 : GET .../notes praticien → 200, notes non-supprimées, text déchiffré ─

#[tokio::test]
async fn list_patient_notes_practitioner_returns_200_with_decrypted_text() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    // Insère une note via POST (chiffrement stub).
    let plain_text = "Examen de contrôle, aucune anomalie.";
    let token = make_practitioner_token(user_id, cabinet_id);
    let body = json!({
        "note_kind": "observation",
        "text": plain_text
    });

    let post_resp = app(make_state(app_pool().await))
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
    assert_eq!(post_resp.status(), StatusCode::CREATED);
    let post_bytes = axum::body::to_bytes(post_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let post_v: serde_json::Value = serde_json::from_slice(&post_bytes).unwrap();
    let note_id: Uuid = post_v["note_id"].as_str().unwrap().parse().unwrap();

    // Insère une note soft-deleted directement en DB (ne doit PAS apparaître dans la liste).
    let deleted_note_id = Uuid::new_v4();
    let deleted_cipher: Vec<u8> = {
        let mut c = b"STUB_ENC:".to_vec();
        c.extend(b"deleted note".iter().map(|b| b ^ 0xFF));
        c
    };
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO clinical_note \
         (id, cabinet_id, patient_id, author_id, content_ciphertext, content_key_ref, \
          note_kind, deleted_at) \
         VALUES ($1, $2, $3, $4, $5, 'stub-key-ref', 'observation', now())",
    )
    .bind(deleted_note_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(user_id)
    .bind(&deleted_cipher)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    // GET .../notes
    let get_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/notes", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_resp.status(), StatusCode::OK);
    let get_bytes = axum::body::to_bytes(get_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&get_bytes).unwrap();

    let data = v["data"].as_array().expect("data doit être un tableau");
    // La note non-supprimée doit apparaître.
    let found = data
        .iter()
        .find(|n| n["note_id"].as_str() == Some(&note_id.to_string()));
    assert!(
        found.is_some(),
        "la note créée doit apparaître dans la liste"
    );
    let note_item = found.unwrap();
    assert_eq!(
        note_item["text"].as_str().unwrap(),
        plain_text,
        "text doit être déchiffré"
    );
    // La note soft-deleted ne doit PAS apparaître.
    let deleted_found = data
        .iter()
        .any(|n| n["note_id"].as_str() == Some(&deleted_note_id.to_string()));
    assert!(!deleted_found, "la note supprimée ne doit pas apparaître");

    // Vérifie que page est présent.
    assert!(v["page"].is_object(), "page doit être un objet");

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}
