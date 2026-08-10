//! Tests d'intégration : POST/PATCH /v1/account/medical-questionnaire (patient)
//! + GET /v1/cabinet/patients/:id/medical-questionnaire (praticien) (#4108)

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

const JWT_SECRET: &str = "test-secret-medical-questionnaire";

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

fn make_patient_token(user_id: Uuid, account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub, "kind": "pro", "cabinet_id": cabinet_id,
            "role": "practitioner", "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    patient_user_id: Uuid,
    account_id: Uuid,
    prac_user_id: Uuid,
    patient_id: Uuid,
}

/// `with_appointment = false` : aucun RDV entre le patient et le praticien
/// (utilisé pour tester la garde R.4127-72 → 403 côté GET cabinet).
async fn insert_fixtures(db: &PgPool, with_appointment: bool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("mq-patient+{}@nubia.test", patient_user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Marie', 'Questionnaire')",
    )
    .bind(account_id)
    .bind(patient_user_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("mq-prac+{}@nubia.test", prac_user_id))
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
         VALUES ($1, 'Cabinet Questionnaire Test', 'dentaire')",
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Marie', 'Questionnaire', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    if with_appointment {
        sqlx::query(
            "INSERT INTO appointment \
             (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
             VALUES ($1, $2, $3, $4, now() + interval '1 day', now() + interval '1 day 30 minutes', 'confirmed', 'premiere consultation')",
        )
        .bind(Uuid::new_v4())
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    }

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        patient_user_id,
        account_id,
        prac_user_id,
        patient_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(f.account_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM medical_questionnaire_submission WHERE patient_account_id = $1")
        .bind(f.account_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM medical_record WHERE patient_id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(f.patient_user_id)
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : POST crée un brouillon ─────────────────────────────────────────

#[tokio::test]
async fn create_medical_questionnaire_creates_draft() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let token = make_patient_token(f.patient_user_id, f.account_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "payload": {"allergies": "aucune"}})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["status"], "draft");
    assert_eq!(body["payload"]["allergies"], "aucune");
    assert!(body["submitted_at"].is_null());

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : POST alors qu'un brouillon existe déjà → 409 ───────────────────

#[tokio::test]
async fn create_medical_questionnaire_duplicate_draft_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let token = make_patient_token(f.patient_user_id, f.account_id);
    let state = make_state(app_pool().await);

    let body = json!({"cabinet_id": f.cabinet_id, "payload": {}}).to_string();

    let first = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(body.clone()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::OK);

    let second = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::CONFLICT);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2b : POST avec un cabinet_id inexistant → 404 (#4343) ──────────────

#[tokio::test]
async fn create_medical_questionnaire_unknown_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let token = make_patient_token(f.patient_user_id, f.account_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "cabinet_id": "deadbeef-0000-0000-0000-000000000000",
                        "payload": {"allergies": "aucune"}
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    let db_count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM medical_questionnaire_submission WHERE patient_account_id = $1",
    )
    .bind(f.account_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(
        db_count, 0,
        "aucun brouillon créé pour un cabinet inexistant"
    );

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : PATCH met à jour puis soumet ───────────────────────────────────

#[tokio::test]
async fn patch_medical_questionnaire_updates_and_submits() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let token = make_patient_token(f.patient_user_id, f.account_id);
    let state = make_state(app_pool().await);

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "payload": {"allergies": "aucune"}})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    let patch_resp = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "cabinet_id": f.cabinet_id,
                        "payload": {"allergies": "penicilline"},
                        "submit": true
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(patch_resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(patch_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["status"], "submitted");
    assert_eq!(body["payload"]["allergies"], "penicilline");
    assert!(!body["submitted_at"].is_null());

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3bis : PATCH avec un octet NUL dans payload → 422 (pas 500) ────────

#[tokio::test]
async fn patch_medical_questionnaire_nul_byte_in_payload_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let token = make_patient_token(f.patient_user_id, f.account_id);
    let state = make_state(app_pool().await);

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "payload": {"allergies": "aucune"}})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    let patch_resp = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "cabinet_id": f.cabinet_id,
                        "payload": {"note": "abc\u{0}def"}
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(patch_resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 4 : PATCH sans brouillon existant → 404 ─────────────────────────────

#[tokio::test]
async fn patch_medical_questionnaire_no_draft_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let token = make_patient_token(f.patient_user_id, f.account_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "payload": {}}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 5 : GET cabinet — brouillon non soumis invisible ───────────────────

#[tokio::test]
async fn get_cabinet_medical_questionnaire_draft_not_visible() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let patient_token = make_patient_token(f.patient_user_id, f.account_id);
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);
    let state = make_state(app_pool().await);

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", patient_token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "payload": {}}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    let get_resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-questionnaire",
                    f.patient_id
                ))
                .header("Authorization", format!("Bearer {}", prac_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 6 : GET cabinet — visible une fois soumis ───────────────────────────

#[tokio::test]
async fn get_cabinet_medical_questionnaire_visible_after_submit() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let patient_token = make_patient_token(f.patient_user_id, f.account_id);
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);
    let state = make_state(app_pool().await);

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", patient_token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "payload": {"allergies": "latex"}})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", patient_token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "submit": true}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    let get_resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-questionnaire",
                    f.patient_id
                ))
                .header("Authorization", format!("Bearer {}", prac_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(get_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["status"], "submitted");
    assert_eq!(body["payload"]["allergies"], "latex");

    cleanup_fixtures(&db, &f).await;
}

// ── Test 7 : GET cabinet — aucun RDV avec ce praticien → 403 ─────────────────

#[tokio::test]
async fn get_cabinet_medical_questionnaire_no_appointment_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, false).await;
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-questionnaire",
                    f.patient_id
                ))
                .header("Authorization", format!("Bearer {}", prac_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 8 : review importe dans medical_record et passe reviewed ───────────

#[tokio::test]
async fn review_medical_questionnaire_imports_and_marks_reviewed() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let patient_token = make_patient_token(f.patient_user_id, f.account_id);
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);
    let state = make_state(app_pool().await);

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", patient_token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "cabinet_id": f.cabinet_id,
                        "payload": {
                            "antecedents": "Diabète type 2",
                            "allergies": "Pénicilline",
                            "traitements_en_cours": "Metformine",
                            "ald": true
                        }
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", patient_token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "submit": true}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    let review_resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-questionnaire/review",
                    f.patient_id
                ))
                .header("Authorization", format!("Bearer {}", prac_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(review_resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(review_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["status"], "reviewed");

    let record_resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-record",
                    f.patient_id
                ))
                .header("Authorization", format!("Bearer {}", prac_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(record_resp.status(), StatusCode::OK);
    let record_bytes = axum::body::to_bytes(record_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let record: serde_json::Value = serde_json::from_slice(&record_bytes).unwrap();
    assert!(record["history"]
        .as_str()
        .unwrap()
        .contains("Diabète type 2"));
    assert_eq!(record["allergies"][0]["text"], "Pénicilline");
    assert_eq!(record["treatments"][0]["text"], "Metformine");
    assert_eq!(record["medico_legal"]["ald"], true);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 9 : review d'une soumission déjà reviewed → 409 ────────────────────

#[tokio::test]
async fn review_medical_questionnaire_already_reviewed_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let patient_token = make_patient_token(f.patient_user_id, f.account_id);
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);
    let state = make_state(app_pool().await);

    app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", patient_token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "payload": {}}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    app(state.clone())
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {}", patient_token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "submit": true}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    let review_uri = format!(
        "/v1/cabinet/patients/{}/medical-questionnaire/review",
        f.patient_id
    );
    let first = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&review_uri)
                .header("Authorization", format!("Bearer {}", prac_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::OK);

    let second = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(&review_uri)
                .header("Authorization", format!("Bearer {}", prac_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::CONFLICT);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 10 : review sans soumission visible → 404 ───────────────────────────

#[tokio::test]
async fn review_medical_questionnaire_no_submission_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-questionnaire/review",
                    f.patient_id
                ))
                .header("Authorization", format!("Bearer {}", prac_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 11 : review sans RDV avec ce praticien → 403 ────────────────────────

#[tokio::test]
async fn review_medical_questionnaire_no_appointment_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, false).await;
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-questionnaire/review",
                    f.patient_id
                ))
                .header("Authorization", format!("Bearer {}", prac_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, &f).await;
}
