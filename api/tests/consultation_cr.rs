//! Tests d'intégration : CR structuré (#7154) —
//! `PUT`/`GET /v1/cabinet/consultations/:id/cr`,
//! `POST /v1/cabinet/consultations/:id/cr/finalize`,
//! `GET /v1/cabinet/consultations/:id/cr/render`.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-consultation-cr";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "practitioner".into(),
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère les fixtures minimales pour une séance en cours.
/// Retourne `(cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id)`.
async fn insert_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("cr-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet CR Structure Test', 'dentaire')",
    )
    .bind(cabinet_id)
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
         VALUES ($1, $2, 'Patient', 'CrStructure')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', now(), 'in_progress', 'pose implant')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO consultation_session \
         (id, cabinet_id, appointment_id, practitioner_id, status) \
         VALUES ($1, $2, $3, $4, 'in_progress')",
    )
    .bind(session_id)
    .bind(cabinet_id)
    .bind(appt_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    patient_id: Uuid,
    appt_id: Uuid,
    session_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM implant_passport WHERE patient_id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_cr WHERE appointment_id = $1")
        .bind(appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_clinique WHERE appointment_id = $1")
        .bind(appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_session WHERE id = $1")
        .bind(session_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

fn test_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn put_cr(
    state: AppState,
    session_id: Uuid,
    token: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/v1/cabinet/consultations/{}/cr", session_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap()
    };
    (status, json)
}

// ── PUT/GET : autosave brouillon ────────────────────────────────────────────

#[tokio::test]
async fn save_and_get_consultation_cr_roundtrips_latest_draft() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;
    let token = make_practitioner_token(prac_user_id, cabinet_id);

    // Première frappe : une section "diagnostic" partiellement rédigée.
    let (status, body) = put_cr(
        test_state(app_pool().await),
        session_id,
        &token,
        serde_json::json!({
            "sections": [{"key": "diagnostic", "title": "Diagnostic", "content": "Carie"}]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "draft");

    // Deuxième frappe : le contenu est complété.
    let (status, _) = put_cr(
        test_state(app_pool().await),
        session_id,
        &token,
        serde_json::json!({
            "sections": [
                {"key": "diagnostic", "title": "Diagnostic", "content": "Carie occlusale 26"}
            ]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // GET doit refléter la dernière version sauvegardée.
    let response = app(test_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/consultations/{}/cr", session_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["status"], "draft");
    assert_eq!(v["sections"][0]["content"], "Carie occlusale 26");

    cleanup_fixture(
        &db,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
    .await;
}

// ── GET sans brouillon existant : objet par défaut, pas 404 ─────────────────

#[tokio::test]
async fn get_consultation_cr_without_draft_returns_default_empty() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;
    let token = make_practitioner_token(prac_user_id, cabinet_id);

    let response = app(test_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/consultations/{}/cr", session_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["status"], "draft");
    assert_eq!(v["sections"], serde_json::json!([]));

    cleanup_fixture(
        &db,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
    .await;
}

// ── Finalize : fige le CR, alimente consultation_clinique, bloque l'autosave ─

#[tokio::test]
async fn finalize_consultation_cr_renders_clinique_and_blocks_further_autosave() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;
    let token = make_practitioner_token(prac_user_id, cabinet_id);

    let (status, _) = put_cr(
        test_state(app_pool().await),
        session_id,
        &token,
        serde_json::json!({
            "sections": [{"key": "acte", "title": "Acte réalisé", "content": "Extraction 46"}]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let response = app(test_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/consultations/{}/cr/finalize",
                    session_id
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["status"], "finalized");

    // consultation_clinique doit désormais porter le compte rendu, finalisé.
    let clinique_status: String =
        sqlx::query("SELECT status FROM consultation_clinique WHERE appointment_id = $1")
            .bind(appt_id)
            .fetch_one(&db)
            .await
            .unwrap()
            .try_get("status")
            .unwrap();
    assert_eq!(clinique_status, "finalized");

    // Toute nouvelle frappe après finalisation est refusée (409).
    let (status, _) = put_cr(
        test_state(app_pool().await),
        session_id,
        &token,
        serde_json::json!({
            "sections": [{"key": "acte", "title": "Acte réalisé", "content": "Modif interdite"}]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    cleanup_fixture(
        &db,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
    .await;
}

#[tokio::test]
async fn finalize_consultation_cr_without_content_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;
    let token = make_practitioner_token(prac_user_id, cabinet_id);

    // Aucun brouillon enregistré du tout.
    let response = app(test_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/consultations/{}/cr/finalize",
                    session_id
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixture(
        &db,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
    .await;
}

// ── Rendu texte/PDF ──────────────────────────────────────────────────────────

#[tokio::test]
async fn render_consultation_cr_returns_text_then_pdf() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;
    let token = make_practitioner_token(prac_user_id, cabinet_id);

    let (status, _) = put_cr(
        test_state(app_pool().await),
        session_id,
        &token,
        serde_json::json!({
            "sections": [{"key": "acte", "title": "Acte réalisé", "content": "Détartrage complet"}]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // Texte (défaut).
    let response = app(test_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/consultations/{}/cr/render",
                    session_id
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response
            .headers()
            .get("content-type")
            .unwrap()
            .to_str()
            .unwrap(),
        "text/plain; charset=utf-8"
    );
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let text = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(text.contains("Détartrage complet"));

    // PDF.
    let response = app(test_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/consultations/{}/cr/render?format=pdf",
                    session_id
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response
            .headers()
            .get("content-type")
            .unwrap()
            .to_str()
            .unwrap(),
        "application/pdf"
    );
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    assert!(bytes.starts_with(b"%PDF-1.4"));

    cleanup_fixture(
        &db,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
    .await;
}

// ── Lien passeport implantaire ───────────────────────────────────────────────

#[tokio::test]
async fn save_consultation_cr_with_implant_section_feeds_implant_passport_idempotently() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;
    let token = make_practitioner_token(prac_user_id, cabinet_id);

    // Première frappe avec la section implant renseignée.
    let (status, _) = put_cr(
        test_state(app_pool().await),
        session_id,
        &token,
        serde_json::json!({
            "sections": [{"key": "implant", "title": "Implant", "content": "Pose implant 26"}],
            "implant": {
                "brand": "Nobel Biocare",
                "implant_ref": "NB-4213",
                "lot_number": "L001"
            }
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let implants = sqlx::query(
        "SELECT id, brand, implant_ref, lot_number FROM implant_passport WHERE patient_id = $1",
    )
    .bind(patient_id)
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(
        implants.len(),
        1,
        "un seul implant créé après la 1ʳᵉ frappe"
    );
    let brand: String = implants[0].try_get("brand").unwrap();
    let lot_number: String = implants[0].try_get("lot_number").unwrap();
    assert_eq!(brand, "Nobel Biocare");
    assert_eq!(lot_number, "L001");

    // Deuxième frappe : la même section implant est mise à jour (lot corrigé),
    // pas de doublon.
    let (status, _) = put_cr(
        test_state(app_pool().await),
        session_id,
        &token,
        serde_json::json!({
            "sections": [{"key": "implant", "title": "Implant", "content": "Pose implant 26"}],
            "implant": {
                "brand": "Nobel Biocare",
                "implant_ref": "NB-4213",
                "lot_number": "L002"
            }
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let implants = sqlx::query("SELECT lot_number FROM implant_passport WHERE patient_id = $1")
        .bind(patient_id)
        .fetch_all(&db)
        .await
        .unwrap();
    assert_eq!(
        implants.len(),
        1,
        "toujours un seul implant après la 2ᵉ frappe (idempotent)"
    );
    let lot_number: String = implants[0].try_get("lot_number").unwrap();
    assert_eq!(lot_number, "L002");

    cleanup_fixture(
        &db,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
    .await;
}

// ── Forbidden : un praticien tiers ne peut pas écrire le CR d'une autre séance ─

#[tokio::test]
async fn save_consultation_cr_forbidden_for_non_owning_practitioner() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;

    let other_prac_user_id = Uuid::new_v4();
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) \
             VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(other_prac_user_id)
        .bind(format!("cr-other-prac+{}@nubia.test", other_prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();
        let other_prac_id = Uuid::new_v4();
        sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
            .bind(other_prac_id)
            .bind(cabinet_id)
            .bind(other_prac_user_id)
            .execute(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
    }

    let other_token = make_practitioner_token(other_prac_user_id, cabinet_id);
    let (status, _) = put_cr(
        test_state(app_pool().await),
        session_id,
        &other_token,
        serde_json::json!({
            "sections": [{"key": "diagnostic", "title": "Diagnostic", "content": "Intrus"}]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM practitioner WHERE user_id = $1")
            .bind(other_prac_user_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM app_user WHERE id = $1")
            .bind(other_prac_user_id)
            .execute(&mut *tx)
            .await
            .ok();
        tx.commit().await.ok();
    }

    cleanup_fixture(
        &db,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
    .await;
}
