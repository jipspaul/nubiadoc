//! Tests d'intégration : GET + PUT /v1/cabinet/patients/:id/periodontal-chart (#4105)

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

const JWT_SECRET: &str = "test-secret-periodontal-chart";

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

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub, "kind": "pro", "cabinet_id": cabinet_id,
            "role": "secretary", "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn insert_fixtures(db: &PgPool) -> (Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("perio-prac+{}@nubia.test", user_id))
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
         VALUES ($1, 'Cabinet Perio Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Serge', 'Parodonte')",
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

    (cabinet_id, user_id, patient_id)
}

async fn cleanup_fixtures(db: &PgPool, cabinet_id: Uuid, user_id: Uuid, patient_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM periodontal_chart WHERE patient_id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(cabinet_id)
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

// ── Test 1 : secretary → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn get_periodontal_chart_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_secretary_token(Uuid::new_v4(), cabinet_id);
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/periodontal-chart",
                    patient_id
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 2 : GET sans bilan existant → objets vides ──────────────────────────

#[tokio::test]
async fn get_periodontal_chart_no_bilan_returns_empty() {
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
                .uri(format!(
                    "/v1/cabinet/patients/{}/periodontal-chart",
                    patient_id
                ))
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
    assert_eq!(v["sites"], json!({}));
    assert_eq!(v["indices"], json!({}));
    assert_eq!(
        v["measured_at"],
        serde_json::Value::Null,
        "#4413 : aucun bilan -> measured_at explicitement null, pas un now() fabriqué"
    );

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

/// #4413 : deux lectures consécutives d'un patient sans bilan doivent
/// renvoyer le même `measured_at` (null) — avant le fix, `now()` était
/// recalculé à chaque GET et changeait entre deux appels.
#[tokio::test]
async fn get_periodontal_chart_no_bilan_measured_at_stable_across_reads() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);

    async fn get_measured_at(state: AppState, patient_id: Uuid, token: &str) -> serde_json::Value {
        let resp = app(state)
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(format!(
                        "/v1/cabinet/patients/{}/periodontal-chart",
                        patient_id
                    ))
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
        v["measured_at"].clone()
    }

    let first = get_measured_at(make_state(app_pool().await), patient_id, &token).await;
    let second = get_measured_at(make_state(app_pool().await), patient_id, &token).await;
    assert_eq!(first, serde_json::Value::Null);
    assert_eq!(second, serde_json::Value::Null);
    assert_eq!(
        first, second,
        "#4413 : état vide stable entre deux lectures"
    );

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 3 : PUT crée un bilan, GET le relit ─────────────────────────────────

#[tokio::test]
async fn put_periodontal_chart_persists_and_get_reads_latest() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);
    let state = make_state(app_pool().await);

    let put_resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!(
                    "/v1/cabinet/patients/{}/periodontal-chart",
                    patient_id
                ))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "sites": {"11": {"depth_mm": 3}},
                        "indices": {"plaque_index": 0.2}
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(put_resp.status(), StatusCode::OK);
    let put_bytes = axum::body::to_bytes(put_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let put_body: serde_json::Value = serde_json::from_slice(&put_bytes).unwrap();
    assert_eq!(put_body["sites"]["11"]["depth_mm"], 3);

    let get_resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/cabinet/patients/{}/periodontal-chart",
                    patient_id
                ))
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
    let get_body: serde_json::Value = serde_json::from_slice(&get_bytes).unwrap();
    assert_eq!(get_body["indices"]["plaque_index"], 0.2);

    // Un 2e PUT crée un nouveau bilan (série de mesures), pas un remplacement.
    let put2_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!(
                    "/v1/cabinet/patients/{}/periodontal-chart",
                    patient_id
                ))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"sites": {"11": {"depth_mm": 2}}, "indices": {}}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(put2_resp.status(), StatusCode::OK);

    let count: i64 = {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        let c = sqlx::query_scalar("SELECT count(*) FROM periodontal_chart WHERE patient_id = $1")
            .bind(patient_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
        c
    };
    assert_eq!(
        count, 2,
        "2 PUT = 2 bilans (série de mesures, pas un upsert)"
    );

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 4 : sites non-objet → 422 ───────────────────────────────────────────

#[tokio::test]
async fn put_periodontal_chart_invalid_sites_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!(
                    "/v1/cabinet/patients/{}/periodontal-chart",
                    patient_id
                ))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"sites": "not-an-object", "indices": {}}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}
