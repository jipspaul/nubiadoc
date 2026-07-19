//! Tests d'intégration : GET /v1/cabinet/patients/:id,
//! GET /v1/cabinet/patients/:id/documents,
//! POST /v1/cabinet/patients/:id/documents (issue #780)
//!
//! Tests requis par l'issue :
//! 1. Praticien voit les champs cliniques (`medical_record`, `notes`)
//! 2. Secrétaire NE voit PAS les champs cliniques
//! 3. Mauvais cabinet → 403 (RLS → 404, acceptable car anti-énumération)

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

const JWT_SECRET: &str = "test-secret-patient-detail-780";

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
    encode(
        &Header::default(),
        &json!({"sub": sub, "kind": "pro", "cabinet_id": cabinet_id, "role": "practitioner", "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid, secretariat_id: Option<Uuid>) -> String {
    encode(
        &Header::default(),
        &json!({"sub": sub, "kind": "pro", "cabinet_id": cabinet_id, "role": "secretary",
                "secretariat_id": secretariat_id, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Rattache le patient au périmètre d'un secrétariat (#3821) : practitioner +
/// provider + secretariat + provider_secretariat(active) + appointment non
/// annulé liant le patient à ce praticien. Retourne `secretariat_id`.
async fn scope_patient_to_secretariat(db: &PgPool, cabinet_id: Uuid, patient_id: Uuid) -> Uuid {
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("detail780-prac+{}@nubia.test", prac_user_id))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
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
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, is_listed, rpps_verified) \
         VALUES ($1, $2, $3, $4, 'Dr. Detail Test', true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec Detail Test')",
    )
    .bind(secretariat_id)
    .bind(cabinet_id)
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
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, now() + interval '1 day', now() + interval '1 day 1 hour', 'confirmed')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    secretariat_id
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
    .bind(format!("detail780+{}@nubia.test", user_id))
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
         VALUES ($1, 'Cabinet Detail Test 780', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Hélène', 'Dupont')",
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

/// Nettoie les rows créées par `scope_patient_to_secretariat` — à appeler
/// AVANT `cleanup_fixtures` (qui supprime le cabinet, référencé en FK).
async fn cleanup_secretariat_scope(db: &PgPool, cabinet_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query(
        "DELETE FROM provider_secretariat WHERE provider_id IN \
         (SELECT id FROM provider WHERE cabinet_id = $1)",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .ok();
    sqlx::query("DELETE FROM secretariat WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    let prac_user_id: Option<Uuid> =
        sqlx::query_scalar("SELECT user_id FROM practitioner WHERE cabinet_id = $1 LIMIT 1")
            .bind(cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .ok()
            .flatten();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    if let Some(prac_user_id) = prac_user_id {
        sqlx::query("DELETE FROM app_user WHERE id = $1")
            .bind(prac_user_id)
            .execute(db)
            .await
            .ok();
    }
}

// ── Test 1 : praticien voit les champs cliniques ───────────────────────────────

#[tokio::test]
async fn get_patient_detail_practitioner_sees_clinical_fields() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    // Ajoute une note clinique pour vérifier la présence du champ `notes`.
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        let mut ciphertext: Vec<u8> = b"STUB_ENC:".to_vec();
        ciphertext.extend_from_slice(b"Carie dent 16");
        sqlx::query(
            "INSERT INTO clinical_note \
             (cabinet_id, patient_id, author_id, content_ciphertext, content_key_ref, note_kind) \
             VALUES ($1, $2, $3, $4, 'stub', 'observation')",
        )
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(user_id)
        .bind(&ciphertext)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let token = make_practitioner_token(user_id, cabinet_id);
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    // Praticien : `notes` doit être présent.
    assert!(
        v["notes"].is_array(),
        "praticien doit voir le champ notes, got: {v}"
    );

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 2 : secrétaire ne voit PAS les champs cliniques ──────────────────────

#[tokio::test]
async fn get_patient_detail_secretary_no_clinical_fields() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;
    let secretariat_id = scope_patient_to_secretariat(&db, cabinet_id, patient_id).await;

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id, Some(secretariat_id));
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    // Secrétaire : `notes` et `medical_record` doivent être ABSENTS (R.4127-72).
    assert!(
        v.get("notes").is_none(),
        "secrétaire ne doit PAS voir `notes`, got: {v}"
    );
    assert!(
        v.get("medical_record").is_none(),
        "secrétaire ne doit PAS voir `medical_record`, got: {v}"
    );
    // Mais les champs admin doivent être présents.
    assert!(v["id"].is_string(), "id doit être présent");
    assert!(v["first_name"].is_string(), "first_name doit être présent");

    cleanup_secretariat_scope(&db, cabinet_id).await;
    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 2b : secrétaire HORS scope secrétariat → 404 (#3821) ────────────────
// Régression #3821 : le détail exposait le dossier admin/mutuelle d'un patient
// que la LISTE de cette même secrétaire masque déjà (contournement trivial
// par accès direct à l'URL).

#[tokio::test]
async fn get_patient_detail_secretary_out_of_scope_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;
    // Un AUTRE secrétariat existe dans ce cabinet, mais n'est PAS rattaché au
    // praticien de ce patient (pas de provider_secretariat le liant) — donc
    // hors scope pour cette secrétaire, comme il le serait pour list_cabinet_patients.
    let other_secretariat_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Autre Secrétariat')",
    )
    .bind(other_secretariat_id)
    .bind(cabinet_id)
    .execute(&db)
    .await
    .unwrap();

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id, Some(other_secretariat_id));
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        resp.status(),
        StatusCode::NOT_FOUND,
        "secrétaire hors scope ne doit pas voir un patient masqué par sa propre liste"
    );

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM secretariat WHERE id = $1")
        .bind(other_secretariat_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 2c : secrétaire sans secrétariat actif → 404 ─────────────────────────

#[tokio::test]
async fn get_patient_detail_secretary_no_secretariat_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id, None);
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 3 : mauvais cabinet → 404 (anti-énumération) ────────────────────────

#[tokio::test]
async fn get_patient_detail_wrong_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    // Token d'un cabinet différent.
    let other_cabinet_id = Uuid::new_v4();
    let token = make_practitioner_token(user_id, other_cabinet_id);
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // RLS cache le patient → 404 (anti-énumération, jamais 403).
    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 4 : GET documents → 200, liste vide ─────────────────────────────────

#[tokio::test]
async fn list_patient_documents_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/documents", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["data"].is_array(), "data doit être un tableau");
    assert!(v["page"].is_object(), "page doit être un objet");

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 5 : POST documents → 201 + document_id ──────────────────────────────

#[tokio::test]
async fn upload_patient_document_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);

    // Construit un multipart minimal.
    let boundary = "----TestBoundary780";
    let body_bytes = format!(
        "--{boundary}\r\n\
         Content-Disposition: form-data; name=\"category\"\r\n\r\n\
         radio\r\n\
         --{boundary}\r\n\
         Content-Disposition: form-data; name=\"file\"; filename=\"radio.pdf\"\r\n\
         Content-Type: application/pdf\r\n\r\n\
         %PDF-stub\r\n\
         --{boundary}--\r\n"
    );

    let resp = app(make_state(app_pool().await))
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

    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(
        v["document_id"]
            .as_str()
            .and_then(|s| s.parse::<Uuid>().ok())
            .is_some(),
        "document_id doit être un UUID valide, got: {v}"
    );

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 6 : GET documents mauvais cabinet → 404 ─────────────────────────────

#[tokio::test]
async fn list_patient_documents_wrong_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let other_cabinet_id = Uuid::new_v4();
    let token = make_practitioner_token(user_id, other_cabinet_id);
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/documents", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}
