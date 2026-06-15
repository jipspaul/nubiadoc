//! Tests d'intégration : POST /v1/cabinet/consultations/:id/acts

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

const JWT_SECRET: &str = "test-secret-acts-post";

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

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
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
            role: "secretary".into(),
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère le jeu de fixtures minimal pour une séance en cours.
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
    .bind(format!("acts-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Acts Test', 'dentaire')",
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
         VALUES ($1, $2, 'Patient', 'Acts')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now(), now() + interval '1 hour', 'in_progress', 'détartrage')",
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
    sqlx::query("DELETE FROM consultation_session WHERE id = $1")
        .bind(session_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_act WHERE appointment_id = $1")
        .bind(appt_id)
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

// ── Test 1 : praticien, body valide → 201 avec act_id ─────────────────────────

#[tokio::test]
async fn add_act_practitioner_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = serde_json::json!({
        "ccam_code": "HBLD001",
        "label": "Détartrage",
        "tooth": "11",
        "amount_cents": 2500
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    assert!(v["act_id"].is_string(), "act_id doit être un UUID string");

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

// ── Test 2 : secrétaire → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn add_act_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;

    let secretary_id = Uuid::new_v4();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = serde_json::json!({
        "ccam_code": "HBLD001",
        "label": "Détartrage",
        "amount_cents": 2500
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", session_id))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_secretary_token(secretary_id, cabinet_id)),
                )
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

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

// ── Test 3 : séance d'un autre cabinet (cross-tenant) → 404 via RLS ────────────

#[tokio::test]
async fn add_act_cross_tenant_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;

    // Autre cabinet — le token pointe vers un cabinet_id différent.
    let other_cabinet_id = Uuid::new_v4();
    let other_user_id = Uuid::new_v4();

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(other_cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(other_user_id)
        .bind(format!("other-prac+{}@nubia.test", other_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) \
             VALUES ($1, 'Cabinet Autre', 'dentaire')",
        )
        .bind(other_cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = serde_json::json!({
        "ccam_code": "HBLD001",
        "label": "Détartrage",
        "amount_cents": 2500
    });

    // Token du praticien de l'autre cabinet, session appartient au premier cabinet.
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(other_user_id, other_cabinet_id)
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    // Cleanup
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
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(other_cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(other_cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 4 : autre praticien du même cabinet → 403 ────────────────────────────

#[tokio::test]
async fn add_act_other_practitioner_same_cabinet_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;

    // Second praticien dans le même cabinet.
    let other_prac_user_id = Uuid::new_v4();
    let other_prac_id = Uuid::new_v4();
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(other_prac_user_id)
        .bind(format!("other-same+{}@nubia.test", other_prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
            .bind(other_prac_id)
            .bind(cabinet_id)
            .bind(other_prac_user_id)
            .execute(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = serde_json::json!({
        "ccam_code": "HBLD001",
        "label": "Détartrage",
        "amount_cents": 2500
    });

    // Token du second praticien — il appartient au même cabinet mais n'est pas
    // celui qui a démarré la séance.
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(other_prac_user_id, cabinet_id)
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM practitioner WHERE id = $1")
            .bind(other_prac_id)
            .execute(&mut *tx)
            .await
            .ok();
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_prac_user_id)
        .execute(&db)
        .await
        .ok();
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

// ── Test 5 : consultation non démarrée (status != 'in_progress') → 409 ────────

#[tokio::test]
async fn add_act_session_not_started_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();

    {
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
        .bind(format!("nostatus-prac+{}@nubia.test", prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) \
             VALUES ($1, 'Cabinet NoStatus Test', 'dentaire')",
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
             VALUES ($1, $2, 'Patient', 'NoStatus')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO appointment \
             (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
             VALUES ($1, $2, $3, $4, now(), now() + interval '1 hour', 'confirmed', 'détartrage')",
        )
        .bind(appt_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        // Séance avec statut 'completed' — non démarrée (pour les actes).
        sqlx::query(
            "INSERT INTO consultation_session \
             (id, cabinet_id, appointment_id, practitioner_id, status) \
             VALUES ($1, $2, $3, $4, 'completed')",
        )
        .bind(session_id)
        .bind(cabinet_id)
        .bind(appt_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = serde_json::json!({
        "ccam_code": "HBLD001",
        "label": "Détartrage",
        "amount_cents": 2500
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CONFLICT);

    // Cleanup
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

// ── Test 6 : sans token → 401 ─────────────────────────────────────────────────

#[tokio::test]
async fn add_act_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = serde_json::json!({
        "ccam_code": "HBLD001",
        "label": "Détartrage",
        "amount_cents": 2500
    });

    // UUID fictif — 401 retourné avant toute requête DB.
    let session_id = Uuid::new_v4();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", session_id))
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 7 : ccam_code vide → 422 ─────────────────────────────────────────────

#[tokio::test]
async fn add_act_empty_ccam_code_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = serde_json::json!({
        "ccam_code": "   ",
        "label": "Détartrage",
        "amount_cents": 2500
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
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

// ── Test 8 : amount_cents négatif → 422 ───────────────────────────────────────

#[tokio::test]
async fn add_act_negative_amount_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = serde_json::json!({
        "ccam_code": "HBLD001",
        "label": "Détartrage",
        "amount_cents": -1
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
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

// ── Test 9 : DB state — l'acte est bien inséré en base après 201 ──────────────

#[tokio::test]
async fn add_act_db_state_row_exists_after_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = serde_json::json!({
        "ccam_code": "HBQK002",
        "label": "Composite",
        "tooth": "21",
        "amount_cents": 12000
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let resp_bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&resp_bytes).unwrap();
    let act_id: uuid::Uuid = v["act_id"].as_str().unwrap().parse().unwrap();

    // Vérifie que la ligne existe réellement en DB avec les bons champs.
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query(
        "SELECT ccam_code, label, tooth, amount_cents \
         FROM consultation_act WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(act_id)
    .bind(cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let ccam: String = row.try_get("ccam_code").unwrap();
    let label: String = row.try_get("label").unwrap();
    let tooth: Option<String> = row.try_get("tooth").unwrap();
    let amount: i32 = row.try_get("amount_cents").unwrap();
    assert_eq!(ccam, "HBQK002");
    assert_eq!(label, "Composite");
    assert_eq!(tooth.as_deref(), Some("21"));
    assert_eq!(amount, 12000);

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
