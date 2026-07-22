//! Tests d'intégration : GET /v1/cabinet/patients/:id/dental-chart/history?at=
//! (#4122). Timestamps de dental_chart_history/dental_chart réécrits
//! directement en DB après les PUT (rôle owner) pour des assertions
//! temporelles déterministes, plutôt que de dépendre de sleeps réels.

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

const JWT_SECRET: &str = "test-secret-dental-chart-history";
// A valide jusqu'à T2 (exclu), B valide de T2 à T3 (exclu), C valide à partir de T3.
const T2: &str = "2020-01-02T00:00:00Z";
const T3: &str = "2020-01-03T00:00:00Z";

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
    prac_user_id: Uuid,
    patient_id: Uuid,
}

async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("dc-hist-prac+{}@nubia.test", prac_user_id))
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
         VALUES ($1, 'Cabinet DentalHistoryAt Test', 'dentaire')",
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
         VALUES ($1, $2, 'Patient', 'DentalHistoryAt')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', now(), 'done', 'contrôle')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
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
    sqlx::query("DELETE FROM dental_chart_history WHERE patient_id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM dental_chart WHERE patient_id = $1")
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

async fn put_teeth(state: AppState, patient_id: Uuid, token: &str, status: &str) {
    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/v1/cabinet/patients/{}/dental-chart", patient_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({"teeth": {"11": {"status": status}}}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

async fn get_at(
    state: AppState,
    patient_id: Uuid,
    token: &str,
    at: &str,
) -> (StatusCode, serde_json::Value) {
    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/dental-chart/history?at={}",
                    patient_id, at
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, body)
}

/// Prépare 3 états (A à "sain", B à "carie", C à "obture") puis réécrit les
/// timestamps de dental_chart_history/dental_chart à T2/T3 (déterministe).
async fn setup_history(db: &PgPool, f: &Fixtures, token: &str) {
    let state = make_state(app_pool().await);
    put_teeth(state.clone(), f.patient_id, token, "sain").await; // A
    put_teeth(state.clone(), f.patient_id, token, "carie").await; // B (snapshot A)
    put_teeth(state, f.patient_id, token, "obture").await; // C (snapshot B)

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    // Réécrit recorded_at des 2 snapshots dans l'ordre chronologique (id
    // d'insertion croissant = ordre réel des PUT).
    let history_ids: Vec<Uuid> = sqlx::query(
        "SELECT id FROM dental_chart_history WHERE patient_id = $1 ORDER BY recorded_at ASC",
    )
    .bind(f.patient_id)
    .fetch_all(&mut *tx)
    .await
    .unwrap()
    .into_iter()
    .map(|r| r.try_get("id").unwrap())
    .collect();
    assert_eq!(history_ids.len(), 2);

    sqlx::query("UPDATE dental_chart_history SET recorded_at = $1 WHERE id = $2")
        .bind(T2.parse::<chrono::DateTime<chrono::Utc>>().unwrap())
        .bind(history_ids[0])
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("UPDATE dental_chart_history SET recorded_at = $1 WHERE id = $2")
        .bind(T3.parse::<chrono::DateTime<chrono::Utc>>().unwrap())
        .bind(history_ids[1])
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("UPDATE dental_chart SET updated_at = $1 WHERE patient_id = $2")
        .bind(T3.parse::<chrono::DateTime<chrono::Utc>>().unwrap())
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    tx.commit().await.unwrap();
}

// ── Test 1 : at avant T2 → état A ─────────────────────────────────────────

#[tokio::test]
async fn history_at_before_first_transition_returns_state_a() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);
    setup_history(&db, &f, &token).await;

    let (status, body) = get_at(
        make_state(app_pool().await),
        f.patient_id,
        &token,
        "2020-01-01T12:00:00Z",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["teeth"]["11"]["status"], "sain");

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : at entre T2 et T3 → état B ────────────────────────────────────

#[tokio::test]
async fn history_at_between_transitions_returns_state_b() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);
    setup_history(&db, &f, &token).await;

    let (status, body) = get_at(
        make_state(app_pool().await),
        f.patient_id,
        &token,
        "2020-01-02T12:00:00Z",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["teeth"]["11"]["status"], "carie");

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : at après T3 → état courant C ──────────────────────────────────

#[tokio::test]
async fn history_at_after_last_transition_returns_current_state() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);
    setup_history(&db, &f, &token).await;

    let (status, body) = get_at(
        make_state(app_pool().await),
        f.patient_id,
        &token,
        "2020-01-03T12:00:00Z",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["teeth"]["11"]["status"], "obture");

    cleanup_fixtures(&db, &f).await;
}

// ── Test 4 : patient sans aucun dental_chart → 404 ──────────────────────────

#[tokio::test]
async fn history_at_no_dental_chart_at_all_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let (status, _) = get_at(
        make_state(app_pool().await),
        f.patient_id,
        &token,
        "2020-01-01T00:00:00Z",
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 5 : at invalide (non RFC3339) → 422 ────────────────────────────────

#[tokio::test]
async fn history_at_invalid_date_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let (status, _) = get_at(
        make_state(app_pool().await),
        f.patient_id,
        &token,
        "not-a-date",
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, &f).await;
}
