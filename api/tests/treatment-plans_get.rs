//! Tests d'intégration : GET /v1/treatment-plans (liste) et GET /v1/treatment-plans/:id

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
    assert!(
        phases[0]["pending_quote_id"].is_null(),
        "pas de devis en attente tant que le devis reste `draft`"
    );

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

// ── Test 1b : devis envoyé et non signé sur une phase → pending_quote_id/
//    pending_quote_sent_at exposés (#6485 : jusqu'ici toujours `null`, quel
//    que soit l'état réel du devis — le front avait déjà le bandeau + le CTA
//    « Consulter et signer le devis » mais aucune donnée pour les afficher).

#[tokio::test]
async fn treatment_plan_get_includes_pending_quote_for_phase() {
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
    .bind(format!("tp-get-pending+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Pending', 'Quote')",
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
    .bind(format!("tp-get-pending-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    let (cabinet_id, prac_id, patient_id, plan_id, phase_id, quote_id) =
        insert_treatment_plan_fixture(&db, prac_user_id, account_id).await;

    // Fait passer le devis de la fixture en `sent` (envoyé, non signé).
    sqlx::query("UPDATE quote SET status = 'sent', sent_at = now() WHERE id = $1")
        .bind(quote_id)
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

    let phases = v["phases"].as_array().expect("phases doit être un tableau");
    assert_eq!(phases.len(), 1, "une phase attendue");
    assert_eq!(
        phases[0]["pending_quote_id"],
        quote_id.to_string(),
        "le devis `sent` couvrant la phase doit être exposé (#6485)"
    );
    assert!(
        phases[0]["pending_quote_sent_at"].is_string(),
        "pending_quote_sent_at doit être exposé quand le devis est `sent`"
    );

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

// ══════════════════════════════════════════════════════════════════════════════
// Tests : GET /v1/treatment-plans (liste paginée)
// ══════════════════════════════════════════════════════════════════════════════

// ── Test L1 : happy path — patient avec un plan → 200, champs conformes ───────

#[tokio::test]
async fn treatment_plans_list_returns_200() {
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
    .bind(format!("tp-list+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'List', 'Patient')",
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
    .bind(format!("tp-list-prac+{}@nubia.test", prac_user_id))
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
                .uri("/v1/treatment-plans")
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

    let data = v["data"].as_array().expect("data doit être un tableau");
    assert!(!data.is_empty(), "au moins un plan attendu");

    let plan = data.iter().find(|p| p["id"] == plan_id.to_string());
    assert!(
        plan.is_some(),
        "le plan inséré doit apparaître dans la liste"
    );
    let plan = plan.unwrap();
    assert_eq!(plan["title"], "Plan implant");
    assert_eq!(plan["status"], "proposed");
    assert!(
        plan["created_at"].is_string(),
        "created_at doit être une chaîne ISO 8601"
    );
    // #6209 : progression exposée dans la liste (carte « Mon suivi » accueil patient).
    assert_eq!(
        plan["step_count"], 1,
        "une phase (`requested`) attendue pour ce plan"
    );
    assert_eq!(
        plan["current_phase_title"], "Phase 1 · Bilan",
        "phase courante = première phase non `done`"
    );
    assert_eq!(
        plan["current_step"], 1,
        "current_step = position de la phase courante (#6233)"
    );
    // #6242 : la liste doit exposer le même montant que le détail
    // (`GET /v1/treatment-plans/:id`), pas « 0 € » faute de champ.
    assert_eq!(
        plan["total_cost_cents"], 3500,
        "total_cost_cents = somme des quote_item du plan (#6242)"
    );
    assert_eq!(
        plan["remaining_cents"], 1450,
        "remaining_cents = total - amo - amc (#6242)"
    );

    let page = &v["page"];
    assert!(page["limit"].is_number(), "page.limit présent");

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

// ── Test L2 : sans JWT → 401 ─────────────────────────────────────────────────

#[tokio::test]
async fn treatment_plans_list_no_jwt_returns_401() {
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
                .uri("/v1/treatment-plans")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test L3 : token pro → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn treatment_plans_list_pro_token_returns_403() {
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
                .uri("/v1/treatment-plans")
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

// ── Test L4 : patient sans plan → 200, data vide ─────────────────────────────

#[tokio::test]
async fn treatment_plans_list_empty_returns_200() {
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
    .bind(format!("tp-list-empty+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Empty', 'List')",
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
                .uri("/v1/treatment-plans")
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

    let data = v["data"].as_array().expect("data doit être un tableau");
    assert_eq!(data.len(), 0, "liste vide attendue pour patient sans plan");
    assert!(v["page"]["limit"].is_number(), "page.limit présent");
    assert!(
        v["page"]["next_cursor"].is_null(),
        "next_cursor null si aucun résultat"
    );

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test L5b : plan `draft` jamais renvoyé dans la liste patient (#5294) ──────

#[tokio::test]
async fn treatment_plans_list_excludes_draft_status() {
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
    .bind(format!("tp-list-draft+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Draft', 'Filter')",
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
    .bind(format!("tp-list-draft-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // Plan visible (statut `proposed`) + phases/quote associés.
    let (cabinet_id, prac_id, patient_id, visible_plan_id, phase_id, quote_id) =
        insert_treatment_plan_fixture(&db, prac_user_id, account_id).await;

    // Second plan du même patient, statut `draft` — ne doit jamais apparaître (#5294).
    let draft_plan_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO treatment_plan \
         (id, cabinet_id, patient_id, practitioner_id, title, status) \
         VALUES ($1, $2, $3, $4, 'Plan brouillon', 'draft')",
    )
    .bind(draft_plan_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/treatment-plans")
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

    let data = v["data"].as_array().expect("data doit être un tableau");
    let ids: Vec<&str> = data.iter().filter_map(|p| p["id"].as_str()).collect();
    assert!(
        !ids.contains(&draft_plan_id.to_string().as_str()),
        "un plan draft ne doit jamais apparaître dans la liste patient (#5294)"
    );
    assert!(
        ids.contains(&visible_plan_id.to_string().as_str()),
        "le plan non-draft doit rester visible"
    );

    sqlx::query("DELETE FROM treatment_plan WHERE id = $1")
        .bind(draft_plan_id)
        .execute(&db)
        .await
        .ok();

    cleanup_fixture(
        &db,
        cabinet_id,
        prac_id,
        patient_id,
        visible_plan_id,
        phase_id,
        quote_id,
    )
    .await;
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test L5 : RLS isolation — patient A ne voit pas les plans de patient B ────

#[tokio::test]
async fn treatment_plans_list_rls_own_only() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    // Patient A (requérant, aucun plan)
    let user_a_id = Uuid::new_v4();
    let account_a_id = Uuid::new_v4();

    // Patient B (possède un plan)
    let user_b_id = Uuid::new_v4();
    let account_b_id = Uuid::new_v4();

    let prac_user_id = Uuid::new_v4();

    for (uid, email, kind) in [
        (
            user_a_id,
            format!("tp-rls-a+{}@nubia.test", user_a_id),
            "patient",
        ),
        (
            user_b_id,
            format!("tp-rls-b+{}@nubia.test", user_b_id),
            "patient",
        ),
        (
            prac_user_id,
            format!("tp-rls-prac+{}@nubia.test", prac_user_id),
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
         VALUES ($1, $2, 'Alpha', 'A')",
    )
    .bind(account_a_id)
    .bind(user_a_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bravo', 'B')",
    )
    .bind(account_b_id)
    .bind(user_b_id)
    .execute(&db)
    .await
    .unwrap();

    // Crée un plan appartenant à Patient B
    let (cabinet_id, prac_id, patient_id, plan_b_id, phase_id, quote_id) =
        insert_treatment_plan_fixture(&db, prac_user_id, account_b_id).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Patient A liste ses plans — le plan de B ne doit pas apparaître
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/treatment-plans")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_a_id, account_a_id)),
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

    let data = v["data"].as_array().expect("data doit être un tableau");
    let ids: Vec<&str> = data.iter().filter_map(|p| p["id"].as_str()).collect();
    assert!(
        !ids.contains(&plan_b_id.to_string().as_str()),
        "le plan de Patient B ne doit pas apparaître dans la liste de Patient A (RLS)"
    );

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

// ── Test L6 : `current_step` = position de la phase courante, pas un
//    compteur de phases `done` (#6233 — régression : une phase tardive
//    terminée avant les précédentes ne doit pas faire croire que le plan
//    est à sa dernière étape) ──────────────────────────────────────────────

#[tokio::test]
async fn treatment_plans_list_current_step_is_current_phase_position() {
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
    .bind(format!("tp-list-step+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Step', 'Patient')",
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
    .bind(format!("tp-list-step-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // Fixture de base : plan avec une seule phase (position 1, `requested`).
    let (cabinet_id, prac_id, patient_id, plan_id, phase_id, quote_id) =
        insert_treatment_plan_fixture(&db, prac_user_id, account_id).await;

    // Ajoute 2 phases : position 2 `requested`, position 3 `done` — la
    // dernière phase (par position) est terminée en premier, ce qui aurait
    // fait remonter `current_step` à `step_count` avec l'ancien fallback
    // front, ou à `done_count + 1` avec un calcul naïf côté API.
    let phase2_id = Uuid::new_v4();
    let phase3_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO treatment_phase \
         (id, cabinet_id, plan_id, position, title, status) \
         VALUES ($1, $2, $3, 2, 'Phase 2', 'requested')",
    )
    .bind(phase2_id)
    .bind(cabinet_id)
    .bind(plan_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO treatment_phase \
         (id, cabinet_id, plan_id, position, title, status) \
         VALUES ($1, $2, $3, 3, 'Phase 3', 'done')",
    )
    .bind(phase3_id)
    .bind(cabinet_id)
    .bind(plan_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/treatment-plans")
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

    let data = v["data"].as_array().expect("data doit être un tableau");
    let plan = data
        .iter()
        .find(|p| p["id"] == plan_id.to_string())
        .expect("le plan inséré doit apparaître dans la liste");

    assert_eq!(plan["step_count"], 3, "3 phases au total");
    assert_eq!(
        plan["current_phase_title"], "Phase 1 · Bilan",
        "phase courante = première phase non `done` par position"
    );
    assert_eq!(
        plan["current_step"], 1,
        "current_step doit rester la position de la phase courante (1), \
         pas step_count (3) ni done_count + 1 (2)"
    );

    sqlx::query("DELETE FROM treatment_phase WHERE id = $1 OR id = $2")
        .bind(phase2_id)
        .bind(phase3_id)
        .execute(&db)
        .await
        .ok();
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

// ── Test L7 : `current_step` = le RANG (1-based) de la phase courante
//    parmi les phases du plan, pas sa `position` brute — `position` est une
//    clé de tri, ni 1-based ni contiguë, parfois dupliquée (#6268 — suite de
//    #6233). Repro exacte de « Plan QA B4 » : positions 0 (`in_progress`)
//    et 5 (`requested`) → `current_step` doit valoir 1, pas 0 ─────────────

#[tokio::test]
async fn treatment_plans_list_current_step_is_rank_not_raw_position() {
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
    .bind(format!("tp-list-rank+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Rank', 'Patient')",
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
    .bind(format!("tp-list-rank-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    // Fixture de base : plan avec une seule phase (position 1, `requested`).
    let (cabinet_id, prac_id, patient_id, plan_id, phase_id, quote_id) =
        insert_treatment_plan_fixture(&db, prac_user_id, account_id).await;

    // Reproduit « Plan QA B4 » : phase de base ramenée en position 0, plus
    // une seconde phase en position 5 — `position` n'est ni 1-based ni
    // contiguë, mais il n'y a que 2 phases (step_count = 2).
    let phase2_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("UPDATE treatment_phase SET position = 0 WHERE id = $1")
        .bind(phase_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO treatment_phase \
         (id, cabinet_id, plan_id, position, title, status) \
         VALUES ($1, $2, $3, 5, 'LeakTest', 'requested')",
    )
    .bind(phase2_id)
    .bind(cabinet_id)
    .bind(plan_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/treatment-plans")
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

    let data = v["data"].as_array().expect("data doit être un tableau");
    let plan = data
        .iter()
        .find(|p| p["id"] == plan_id.to_string())
        .expect("le plan inséré doit apparaître dans la liste");

    assert_eq!(plan["step_count"], 2, "2 phases au total");
    assert_eq!(
        plan["current_phase_title"], "Phase 1 · Bilan",
        "phase courante = première phase non `done` par position (0)"
    );
    assert_eq!(
        plan["current_step"], 1,
        "current_step doit être le RANG (1) de la phase courante, \
         pas sa position brute (0)"
    );

    sqlx::query("DELETE FROM treatment_phase WHERE id = $1")
        .bind(phase2_id)
        .execute(&db)
        .await
        .ok();
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
