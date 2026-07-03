//! Tests d'intégration : GET /v1/cabinet/consultations (historique des séances, #3232)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-consultations-list";

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

fn make_pro_token(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
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
            role: role.into(),
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère cabinet + praticien + patient + RDV + séance `in_progress`.
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
    .bind(format!("list-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet List Test', 'dentaire')",
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
         VALUES ($1, $2, 'Liste', 'Historique')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', now(), 'in_progress', 'détartrage')",
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

async fn get_list(state: AppState, token: &str, query: &str) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/consultations{}", query))
                .header("authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json = if bytes.is_empty() {
        serde_json::Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null)
    };
    (status, json)
}

// ── Test 1 : liste 200 avec la séance et ses champs ──────────────────────────

#[tokio::test]
async fn list_returns_sessions_200() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&owner).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_pro_token(prac_user_id, cabinet_id, "practitioner");

    let (status, json) = get_list(state, &token, "").await;

    assert_eq!(status, StatusCode::OK);
    let data = json["data"].as_array().expect("data doit être un tableau");
    let item = data
        .iter()
        .find(|s| s["id"] == session_id.to_string())
        .expect("la séance insérée doit apparaître");
    assert_eq!(item["appointment_id"], appt_id.to_string());
    assert_eq!(item["patient_id"], patient_id.to_string());
    assert_eq!(item["patient_name"], "Liste Historique");
    assert_eq!(item["status"], "in_progress");
    assert_eq!(item["acts_count"], 0);

    cleanup_fixture(
        &owner,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
    .await;
}

// ── Test 2 : filtre patient_id étranger → liste vide ─────────────────────────

#[tokio::test]
async fn list_filter_other_patient_returns_empty() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&owner).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_pro_token(prac_user_id, cabinet_id, "practitioner");

    let (status, json) = get_list(state, &token, &format!("?patient_id={}", Uuid::new_v4())).await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["data"].as_array().unwrap().len(), 0);

    cleanup_fixture(
        &owner,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
    .await;
}

// ── Test 3 : filtre status=completed → vide (séance in_progress) ─────────────

#[tokio::test]
async fn list_filter_status_completed_returns_empty() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&owner).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_pro_token(prac_user_id, cabinet_id, "practitioner");

    let (status, json) = get_list(state, &token, "?status=completed").await;

    assert_eq!(status, StatusCode::OK);
    let data = json["data"].as_array().unwrap();
    assert!(
        !data.iter().any(|s| s["id"] == session_id.to_string()),
        "la séance in_progress ne doit pas matcher status=completed"
    );

    cleanup_fixture(
        &owner,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
    .await;
}

// ── Test 4 : status inconnu → 422 ─────────────────────────────────────────────

#[tokio::test]
async fn list_invalid_status_returns_422() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "practitioner");

    let (status, _) = get_list(state, &token, "?status=nimporte").await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 5 : sans token → 401 ─────────────────────────────────────────────────

#[tokio::test]
async fn list_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/consultations")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 6 : secrétaire → 403 (cloisonnement clinique) ───────────────────────

#[tokio::test]
async fn list_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "secretary");

    let (status, _) = get_list(state, &token, "").await;

    assert_eq!(status, StatusCode::FORBIDDEN);
}

// ── Test 7 : cross-tenant → la séance d'un autre cabinet est invisible ───────

#[tokio::test]
async fn list_cross_tenant_invisible() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&owner).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    // Praticien d'un AUTRE cabinet.
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "practitioner");

    let (status, json) = get_list(state, &token, "").await;

    assert_eq!(status, StatusCode::OK);
    let data = json["data"].as_array().unwrap();
    assert!(
        !data.iter().any(|s| s["id"] == session_id.to_string()),
        "une séance d'un autre cabinet ne doit JAMAIS apparaître"
    );

    cleanup_fixture(
        &owner,
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
    .await;
}
