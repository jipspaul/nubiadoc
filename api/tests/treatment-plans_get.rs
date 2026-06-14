//! Tests d'intégration : GET /v1/treatment-plans/:id

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

const JWT_SECRET: &str = "test-jwt-secret-treatment-plans-get";

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

fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "role": "admin",
                "account_id": Uuid::nil(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère le jeu de fixtures minimal pour un plan de traitement.
/// Retourne (cabinet_id, prac_id, patient_id, plan_id, phase_id, quote_id).
async fn insert_treatment_plan_fixture(
    db: &PgPool,
    prac_user_id: Uuid,
    patient_account_id: Uuid,
) -> (Uuid, Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let plan_id = Uuid::new_v4();
    let phase_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet TP Test {}", cabinet_id))
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
         VALUES ($1, $2, 'Test', 'Patient', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO treatment_plan \
         (id, cabinet_id, patient_id, practitioner_id, title, status) \
         VALUES ($1, $2, $3, $4, 'Plan implant', 'proposed')",
    )
    .bind(plan_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Quote rattaché au plan (quote_item.quote_id est NOT NULL)
    sqlx::query("INSERT INTO quote (id, cabinet_id, patient_id) VALUES ($1, $2, $3)")
        .bind(quote_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO treatment_phase \
         (id, cabinet_id, plan_id, position, title, status) \
         VALUES ($1, $2, $3, 1, 'Phase 1 · Bilan', 'requested')",
    )
    .bind(phase_id)
    .bind(cabinet_id)
    .bind(plan_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Acte dans la phase
    sqlx::query(
        "INSERT INTO quote_item \
         (id, cabinet_id, quote_id, phase_id, label, ccam_code, unit_amount, amo_part, amc_part) \
         VALUES ($1, $2, $3, $4, 'Détartrage', 'HBMD001', 35.00, 12.50, 8.00)",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(quote_id)
    .bind(phase_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    (cabinet_id, prac_id, patient_id, plan_id, phase_id, quote_id)
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
    plan_id: Uuid,
    phase_id: Uuid,
    quote_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_item WHERE phase_id = $1")
        .bind(phase_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE id = $1")
        .bind(quote_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_phase WHERE plan_id = $1")
        .bind(plan_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_plan WHERE id = $1")
        .bind(plan_id)
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
    tx.commit().await.ok();
}

// ── Test 1 : happy path — propriétaire du plan → 200 avec tous les champs ────

#[tokio::test]
async fn treatment_plan_get_owner_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("tp-get+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Detail', 'TP')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("tp-get-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    let (cabinet_id, prac_id, patient_id, plan_id, phase_id, quote_id) =
        insert_treatment_plan_fixture(&db, prac_user_id, account_id).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/treatment-plans/{}", plan_id))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(v["id"], plan_id.to_string(), "id doit correspondre");
    assert_eq!(v["title"], "Plan implant");
    assert_eq!(v["status"], "proposed");
    assert!(
        v["total_cost_cents"].is_number(),
        "total_cost_cents présent"
    );
    assert!(v["remaining_cents"].is_number(), "remaining_cents présent");
    assert!(v["amo_part_cents"].is_number(), "amo_part_cents présent");
    assert!(v["amc_part_cents"].is_number(), "amc_part_cents présent");

    let phases = v["phases"].as_array().expect("phases doit être un tableau");
    assert_eq!(phases.len(), 1, "une phase attendue");
    assert_eq!(phases[0]["title"], "Phase 1 · Bilan");
    assert_eq!(phases[0]["position"], 1);
    assert_eq!(phases[0]["status"], "requested");

    let items = phases[0]["items"]
        .as_array()
        .expect("items doit être un tableau");
    assert_eq!(items.len(), 1, "un acte attendu");
    assert_eq!(items[0]["label"], "Détartrage");
    assert_eq!(items[0]["ccam_code"], "HBMD001");
    assert_eq!(
        items[0]["unit_amount_cents"], 3500,
        "35.00 EUR = 3500 centimes"
    );
    assert_eq!(
        items[0]["amo_part_cents"], 1250,
        "12.50 EUR = 1250 centimes"
    );
    assert_eq!(items[0]["amc_part_cents"], 800, "8.00 EUR = 800 centimes");

    // total = 3500, amo = 1250, amc = 800, remaining = 3500 - 1250 - 800 = 1450
    assert_eq!(v["total_cost_cents"], 3500);
    assert_eq!(v["amo_part_cents"], 1250);
    assert_eq!(v["amc_part_cents"], 800);
    assert_eq!(v["remaining_cents"], 1450);

    cleanup_fixture(
        &db, cabinet_id, prac_id, patient_id, plan_id, phase_id, quote_id,
    )
    .await;
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn treatment_plan_get_no_jwt_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/treatment-plans/{}", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 3 : token pro → 403 ──────────────────────────────────────────────────

#[tokio::test]
async fn treatment_plan_get_pro_token_returns_403() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/treatment-plans/{}", Uuid::new_v4()))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(Uuid::new_v4(), Uuid::new_v4())),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 4 : plan inexistant → 404 ────────────────────────────────────────────

#[tokio::test]
async fn treatment_plan_get_unknown_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("tp-notfound+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Solo', 'Patient')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/treatment-plans/{}", Uuid::new_v4()))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 5 : plan d'un autre patient → 404 (RLS anti-énumération) ─────────────

#[tokio::test]
async fn treatment_plan_get_other_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    // Patient A (le requérant)
    let user_a_id = Uuid::new_v4();
    let account_a_id = Uuid::new_v4();

    // Patient B (propriétaire du plan)
    let user_b_id = Uuid::new_v4();
    let account_b_id = Uuid::new_v4();

    let prac_user_id = Uuid::new_v4();

    for (uid, email, kind) in [
        (
            user_a_id,
            format!("tp-cross-a+{}@nubia.test", user_a_id),
            "patient",
        ),
        (
            user_b_id,
            format!("tp-cross-b+{}@nubia.test", user_b_id),
            "patient",
        ),
        (
            prac_user_id,
            format!("tp-cross-prac+{}@nubia.test", prac_user_id),
            "pro",
        ),
    ] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(uid)
        .bind(&email)
        .bind(kind)
        .execute(&db)
        .await
        .unwrap();
    }

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'A')",
    )
    .bind(account_a_id)
    .bind(user_a_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'B')",
    )
    .bind(account_b_id)
    .bind(user_b_id)
    .execute(&db)
    .await
    .unwrap();

    // Crée le plan de traitement de Patient B
    let (cabinet_id, prac_id, patient_id, plan_b_id, phase_id, quote_id) =
        insert_treatment_plan_fixture(&db, prac_user_id, account_b_id).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Patient A essaie d'accéder au plan de Patient B → 404
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/treatment-plans/{}", plan_b_id))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_a_id, account_a_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "plan d'un autre patient doit retourner 404 (anti-énumération RLS)"
    );

    // Cleanup
    cleanup_fixture(
        &db, cabinet_id, prac_id, patient_id, plan_b_id, phase_id, quote_id,
    )
    .await;
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2 OR id = $3")
        .bind(user_a_id)
        .bind(user_b_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}
