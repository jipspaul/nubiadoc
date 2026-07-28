//! Tests d'intégration : POST /v1/cabinet/treatment-plans/:id/phases (#4050)
//!
//! 1. Praticien + plan du cabinet → 201 { phase_id }, ligne persistée.
//! 2. `quote_item_ids` fourni → les quote_item du cabinet sont rattachés
//!    (phase_id mis à jour).
//! 3. Plan hors cabinet (autre tenant) → 404.
//! 4. title vide → 422, aucune phase créée.
//! 5. position négative → 422, aucune phase créée (#4368).
//! 6. inline_acts[].tooth hors numérotation FDI → 422, aucune phase créée (#4368).
//! 7. plan déjà `done` (terminal) → 422, aucune phase créée (#4386).

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

const JWT_SECRET: &str = "test-secret-treatment-phases-create";

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

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
    patient_id: Uuid,
    plan_id: Uuid,
}

/// Insère cabinet + app_user + practitioner + patient + treatment_plan.
async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let plan_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("tph-prac+{}@nubia.test", user_id))
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
         VALUES ($1, 'Cabinet Phase Test', 'dentaire')",
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

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        user_id,
        patient_id,
        plan_id,
    }
}

/// Insère un devis + une ligne (`quote_item`), sans `phase_id`. Retourne l'id
/// du `quote_item`.
async fn insert_quote_item(db: &PgPool, cabinet_id: Uuid, patient_id: Uuid) -> Uuid {
    let quote_id = Uuid::new_v4();
    let item_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status) VALUES ($1, $2, $3, 'draft')",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote_item (id, cabinet_id, quote_id, label, unit_amount) \
         VALUES ($1, $2, $3, 'Couronne', 45000)",
    )
    .bind(item_id)
    .bind(cabinet_id)
    .bind(quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    item_id
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_item WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : praticien + plan du cabinet → 201, phase persistée ──────────────

#[tokio::test]
async fn create_treatment_phase_returns_201_and_persists() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/treatment-plans/{}/phases", f.plan_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({ "title": "Phase 1 · Détartrage", "position": 1 }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let phase_id: Uuid = v["phase_id"].as_str().unwrap().parse().unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row =
        sqlx::query("SELECT plan_id, position, title, status FROM treatment_phase WHERE id = $1")
            .bind(phase_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    tx.commit().await.unwrap();

    let row_plan_id: Uuid = row.try_get("plan_id").unwrap();
    let row_position: i32 = row.try_get("position").unwrap();
    let row_title: String = row.try_get("title").unwrap();
    let row_status: String = row.try_get("status").unwrap();
    assert_eq!(row_plan_id, f.plan_id);
    assert_eq!(row_position, 1);
    assert_eq!(row_title, "Phase 1 · Détartrage");
    assert_eq!(row_status, "requested");

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : quote_item_ids fourni → rattaché via phase_id ────────────────────

#[tokio::test]
async fn create_treatment_phase_attaches_existing_quote_items() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let item_id = insert_quote_item(&db, f.cabinet_id, f.patient_id).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/treatment-plans/{}/phases", f.plan_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({
                        "title": "Phase 1 · Détartrage",
                        "position": 1,
                        "quote_item_ids": [item_id],
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let phase_id: Uuid = v["phase_id"].as_str().unwrap().parse().unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT phase_id FROM quote_item WHERE id = $1")
        .bind(item_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    let row_phase_id: Option<Uuid> = row.try_get("phase_id").unwrap();
    assert_eq!(row_phase_id, Some(phase_id));

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2bis (#4421) : quote_item d'un AUTRE patient du même cabinet → ignoré ─

#[tokio::test]
async fn create_treatment_phase_ignores_cross_patient_quote_item() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;

    // 2e patient du MÊME cabinet, avec son propre quote_item.
    let other_patient_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Jade', 'Autre')",
    )
    .bind(other_patient_id)
    .bind(f.cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    let other_item_id = insert_quote_item(&db, f.cabinet_id, other_patient_id).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    // Plan de f.patient_id, mais on tente de rattacher l'item de other_patient_id.
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/treatment-plans/{}/phases", f.plan_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({
                        "title": "Phase crosslink",
                        "position": 1,
                        "quote_item_ids": [other_item_id],
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    // La création de la phase réussit (aucun item VALIDE n'est requis), mais
    // le rattachement de l'item d'un autre patient doit être ignoré.
    assert_eq!(resp.status(), StatusCode::CREATED);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT phase_id FROM quote_item WHERE id = $1")
        .bind(other_item_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    let row_phase_id: Option<Uuid> = row.try_get("phase_id").unwrap();
    assert_eq!(
        row_phase_id, None,
        "l'item du 2e patient ne doit PAS être rattaché à la phase du 1er"
    );

    // Nettoyage du 2e patient (hors cleanup_fixtures, qui ne connaît que f).
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(other_patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : plan hors cabinet → 404 ──────────────────────────────────────────

#[tokio::test]
async fn create_treatment_phase_foreign_plan_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let other = insert_fixtures(&db).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/treatment-plans/{}/phases",
                    other.plan_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({ "title": "Phase 1", "position": 1 }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, &f).await;
    cleanup_fixtures(&db, &other).await;
}

// ── Test 4 : title vide → 422, aucune phase créée ─────────────────────────────

#[tokio::test]
async fn create_treatment_phase_empty_title_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/treatment-plans/{}/phases", f.plan_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({ "title": "   ", "position": 1 }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let count: i64 = sqlx::query("SELECT count(*) AS n FROM treatment_phase WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap()
        .try_get("n")
        .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(count, 0);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 5 : position négative → 422, aucune phase créée (#4368) ─────────────

#[tokio::test]
async fn create_treatment_phase_negative_position_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/treatment-plans/{}/phases", f.plan_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({ "title": "Phase neg", "position": -5 }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let count: i64 = sqlx::query("SELECT count(*) AS n FROM treatment_phase WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap()
        .try_get("n")
        .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(count, 0);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 6 : inline_acts[].tooth hors numérotation FDI → 422 (#4368) ─────────

#[tokio::test]
async fn create_treatment_phase_invalid_tooth_code_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/treatment-plans/{}/phases", f.plan_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({
                        "title": "Phase acte",
                        "position": 1,
                        "inline_acts": [
                            { "label": "acte", "tooth": "zzz999", "amount_cents": 1000 }
                        ],
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let count: i64 = sqlx::query("SELECT count(*) AS n FROM treatment_phase WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap()
        .try_get("n")
        .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(count, 0);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 7 : plan déjà `done` (terminal) → 422, aucune phase créée (#4386) ───

#[tokio::test]
async fn create_treatment_phase_on_done_plan_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("UPDATE treatment_plan SET status = 'done' WHERE id = $1")
        .bind(f.plan_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/treatment-plans/{}/phases", f.plan_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({ "title": "Phase après done", "position": 2 }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let count: i64 = sqlx::query("SELECT count(*) AS n FROM treatment_phase WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap()
        .try_get("n")
        .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(count, 0);

    cleanup_fixtures(&db, &f).await;
}
