//! Tests d'intégration : PATCH /v1/cabinet/treatment-plans/:id/phases/:phase_id (#4262)
//!
//! 1. `requested` → `done` (saut) réussit, reflété au GET suivant.
//! 2. `done` → `requested` (retour arrière) → 409 invalid_status.

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

const JWT_SECRET: &str = "test-secret-treatment-phases-patch";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": "practitioner",
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
    plan_id: Uuid,
    phase_id: Uuid,
}

async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let plan_id = Uuid::new_v4();
    let phase_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("tph-patch+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Phase Patch Test', 'dentaire')",
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
         VALUES ($1, $2, 'Marie', 'Durand')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO treatment_plan (id, cabinet_id, patient_id, title, status) \
         VALUES ($1, $2, $3, 'Plan test', 'draft')",
    )
    .bind(plan_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO treatment_phase (id, cabinet_id, plan_id, position, title, status) \
         VALUES ($1, $2, $3, 1, 'Phase 1', 'requested')",
    )
    .bind(phase_id)
    .bind(cabinet_id)
    .bind(plan_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        user_id,
        plan_id,
        phase_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_phase WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_plan WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

async fn patch_status(
    state: AppState,
    plan_id: Uuid,
    phase_id: Uuid,
    token: &str,
    status: &str,
) -> (StatusCode, serde_json::Value) {
    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!(
                    "/v1/cabinet/treatment-plans/{plan_id}/phases/{phase_id}"
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::from(json!({ "status": status }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    let status_code = resp.status();
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap_or_default();
    (status_code, body)
}

#[tokio::test]
async fn requested_to_done_succeeds_and_persists() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let (status, body) = patch_status(
        make_state(app_pool().await),
        f.plan_id,
        f.phase_id,
        &token,
        "done",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "done");

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT status FROM treatment_phase WHERE id = $1")
        .bind(f.phase_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let row_status: String = row.try_get("status").unwrap();
    assert_eq!(row_status, "done");

    // #4348 : seule phase du plan passée `done` -> le plan doit suivre
    // (auparavant restait `draft` à vie, machine à états morte).
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let plan_row = sqlx::query("SELECT status FROM treatment_plan WHERE id = $1")
        .bind(f.plan_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let plan_status: String = plan_row.try_get("status").unwrap();
    assert_eq!(
        plan_status, "done",
        "#4348 : plan.status doit suivre quand toutes ses phases sont done"
    );

    cleanup_fixtures(&db, &f).await;
}

/// #4348 : avec plusieurs phases, le plan passe `in_progress` dès qu'UNE
/// phase progresse, mais ne passe `done` que quand TOUTES le sont.
#[tokio::test]
async fn plan_status_in_progress_until_all_phases_done() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let second_phase_id = Uuid::new_v4();
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO treatment_phase (id, cabinet_id, plan_id, position, title, status) \
             VALUES ($1, $2, $3, 2, 'Phase 2', 'requested')",
        )
        .bind(second_phase_id)
        .bind(f.cabinet_id)
        .bind(f.plan_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    // Première phase seule -> done. Le plan doit passer in_progress (pas done,
    // il reste une phase 'requested').
    let (status, _) = patch_status(
        make_state(app_pool().await),
        f.plan_id,
        f.phase_id,
        &token,
        "done",
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let plan_row = sqlx::query("SELECT status FROM treatment_plan WHERE id = $1")
        .bind(f.plan_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let plan_status: String = plan_row.try_get("status").unwrap();
    assert_eq!(
        plan_status, "in_progress",
        "1 phase done sur 2 -> plan in_progress, pas done"
    );

    // Seconde phase -> done aussi. Le plan doit maintenant passer done.
    let (status, _) = patch_status(
        make_state(app_pool().await),
        f.plan_id,
        second_phase_id,
        &token,
        "done",
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let plan_row = sqlx::query("SELECT status FROM treatment_plan WHERE id = $1")
        .bind(f.plan_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let plan_status: String = plan_row.try_get("status").unwrap();
    assert_eq!(plan_status, "done", "2/2 phases done -> plan done");

    cleanup_fixtures(&db, &f).await;
}

#[tokio::test]
async fn backward_transition_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let (status, _) = patch_status(
        make_state(app_pool().await),
        f.plan_id,
        f.phase_id,
        &token,
        "done",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "requested → done doit réussir");

    let (status, body) = patch_status(
        make_state(app_pool().await),
        f.plan_id,
        f.phase_id,
        &token,
        "requested",
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "invalid_status");

    cleanup_fixtures(&db, &f).await;
}
