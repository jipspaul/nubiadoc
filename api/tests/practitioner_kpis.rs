//! Tests d'intégration : GET /v1/me/kpis + CRUD
//! /v1/cabinet/practitioner-objectives (#7189, DP-F10.b)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use chrono::{Datelike, Duration, Utc};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-practitioner-kpis";

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

fn make_pro_jwt(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub, "kind": "pro", "cabinet_id": cabinet_id,
            "role": role, "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Premier jour du mois courant, même calcul que `practitioner_kpis::get_my_kpis`
/// (année/mois UTC).
fn current_month_start() -> chrono::NaiveDate {
    let now = Utc::now();
    chrono::NaiveDate::from_ymd_opt(now.year(), now.month(), 1).unwrap()
}

/// Fixture : un praticien (même `user_id`) exerçant dans DEUX cabinets, avec
/// un `provider`/patient/manager par cabinet — de quoi couvrir facturé,
/// encaissé, RDV du jour, rappels, occupation et objectif, en multi-cabinet.
struct Fixtures {
    user_id: Uuid,
    cabinet_a: Uuid,
    practitioner_a: Uuid,
    provider_a: Uuid,
    patient_a: Uuid,
    manager_a: Uuid,
    cabinet_b: Uuid,
    practitioner_b: Uuid,
    provider_b: Uuid,
    patient_b: Uuid,
}

async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let user_id = Uuid::new_v4();
    let manager_a = Uuid::new_v4();
    let cabinet_a = Uuid::new_v4();
    let cabinet_b = Uuid::new_v4();
    let patient_a = Uuid::new_v4();
    let patient_b = Uuid::new_v4();
    let practitioner_a = Uuid::new_v4();
    let practitioner_b = Uuid::new_v4();
    let provider_a = Uuid::new_v4();
    let provider_b = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("kpi-prac+{user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(manager_a)
    .bind(format!("kpi-manager+{manager_a}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    for (cabinet_id, practitioner_id, provider_id, patient_id, name) in [
        (cabinet_a, practitioner_a, provider_a, patient_a, "A"),
        (cabinet_b, practitioner_b, provider_b, patient_b, "B"),
    ] {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, $2)")
            .bind(cabinet_id)
            .bind(format!("Cabinet KPI {name} {cabinet_id}"))
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
             VALUES ($1, $2, 'Patient', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(format!("Kpi{name}"))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
            .bind(practitioner_id)
            .bind(cabinet_id)
            .bind(user_id)
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO provider (id, practitioner_id, cabinet_id, user_id, display_name) \
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(provider_id)
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(user_id)
        .bind(format!("Dr Kpi {name}"))
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    Fixtures {
        user_id,
        cabinet_a,
        practitioner_a,
        provider_a,
        patient_a,
        manager_a,
        cabinet_b,
        practitioner_b,
        provider_b,
        patient_b,
    }
}

async fn insert_consultation_act(
    db: &PgPool,
    cabinet_id: Uuid,
    appointment_id: Uuid,
    patient_id: Uuid,
    practitioner_id: Uuid,
    amount_cents: i32,
) {
    sqlx::query(
        "INSERT INTO consultation_act \
           (id, cabinet_id, appointment_id, patient_id, practitioner_id, ccam_code, label, amount_cents) \
         VALUES ($1, $2, $3, $4, $5, 'HBQK002', 'Acte KPI', $6)",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(appointment_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(amount_cents)
    .execute(db)
    .await
    .unwrap();
}

async fn insert_appointment(
    db: &PgPool,
    cabinet_id: Uuid,
    patient_id: Uuid,
    practitioner_id: Uuid,
    starts_at: chrono::DateTime<Utc>,
) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO appointment \
           (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, $5, $6, 'confirmed')",
    )
    .bind(id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(starts_at)
    .bind(starts_at + Duration::minutes(30))
    .execute(db)
    .await
    .unwrap();
    id
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    for cabinet_id in [f.cabinet_a, f.cabinet_b] {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM practitioner_objective WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM reminder WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM consultation_act WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM payment WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM availability_slot WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
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
    }
    sqlx::query("DELETE FROM app_user WHERE id IN ($1, $2)")
        .bind(f.user_id)
        .bind(f.manager_a)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : agrégation multi-cabinet (facturé/encaissé/RDV/rappels/occupation/objectif) ──

#[tokio::test]
async fn my_kpis_aggregates_across_multiple_cabinets() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let now = Utc::now();

    // Cabinet A : 5000 cents facturés aujourd'hui, 3000 cents encaissés,
    // 1 RDV aujourd'hui, 1 rappel en attente, objectif 10000 cents (50% atteint).
    let appt_a = insert_appointment(&db, f.cabinet_a, f.patient_a, f.practitioner_a, now).await;
    insert_consultation_act(
        &db,
        f.cabinet_a,
        appt_a,
        f.patient_a,
        f.practitioner_a,
        5000,
    )
    .await;
    sqlx::query(
        "INSERT INTO payment (id, cabinet_id, patient_id, amount, currency, kind, provider, status) \
         VALUES ($1, $2, $3, 30, 'EUR', 'full', 'stripe', 'paid')",
    )
    .bind(Uuid::new_v4())
    .bind(f.cabinet_a)
    .bind(f.patient_a)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO reminder (id, cabinet_id, appointment_id, patient_id, scheduled_at, status) \
         VALUES ($1, $2, $3, $4, $5, 'pending')",
    )
    .bind(Uuid::new_v4())
    .bind(f.cabinet_a)
    .bind(appt_a)
    .bind(f.patient_a)
    .bind(now + Duration::hours(1))
    .execute(&db)
    .await
    .unwrap();
    // 2 créneaux cette semaine : 1 ouvert, 1 réservé -> occupation 50%.
    sqlx::query(
        "INSERT INTO availability_slot (id, cabinet_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, $5, 'open')",
    )
    .bind(Uuid::new_v4())
    .bind(f.cabinet_a)
    .bind(f.practitioner_a)
    .bind(now + Duration::hours(2))
    .bind(now + Duration::hours(3))
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO availability_slot (id, cabinet_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, $5, 'booked')",
    )
    .bind(Uuid::new_v4())
    .bind(f.cabinet_a)
    .bind(f.practitioner_a)
    .bind(now + Duration::hours(4))
    .bind(now + Duration::hours(5))
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO practitioner_objective (id, cabinet_id, provider_id, month, target_cents, created_by) \
         VALUES ($1, $2, $3, $4, 10000, $5)",
    )
    .bind(Uuid::new_v4())
    .bind(f.cabinet_a)
    .bind(f.provider_a)
    .bind(current_month_start())
    .bind(f.manager_a)
    .execute(&db)
    .await
    .unwrap();

    // Cabinet B : 2000 cents facturés aujourd'hui, pas d'objectif.
    let appt_b = insert_appointment(&db, f.cabinet_b, f.patient_b, f.practitioner_b, now).await;
    insert_consultation_act(
        &db,
        f.cabinet_b,
        appt_b,
        f.patient_b,
        f.practitioner_b,
        2000,
    )
    .await;

    let state = make_state(app_pool().await);
    let token = make_pro_jwt(f.user_id, f.cabinet_a, "practitioner");

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/kpis")
                .header("Authorization", format!("Bearer {token}"))
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

    assert_eq!(
        v["today"]["billed_cents"], 7000,
        "5000 (cabinet A) + 2000 (cabinet B)"
    );
    assert_eq!(v["month"]["billed_cents"], 7000);
    assert_eq!(v["today"]["collected_cents"], 3000);
    assert_eq!(v["appointments_today"], 2, "1 RDV par cabinet");
    assert_eq!(v["pending_reminders"], 1);
    assert!(
        (v["occupancy_rate"].as_f64().unwrap() - 0.5).abs() < 1e-9,
        "1 réservé / 2 ouverts cette semaine"
    );
    assert_eq!(
        v["objective_target_cents"], 10000,
        "seul le cabinet A a un objectif, sommé tel quel"
    );
    assert!(
        (v["objective_achieved_pct"].as_f64().unwrap() - 0.7).abs() < 1e-9,
        "facturé TOTAL (5000 + 2000) / objectif TOTAL (10000) = 70% \
         — le facturé du cabinet B pèse dans l'agrégat global même sans objectif propre"
    );

    let by_cabinet = v["by_cabinet"].as_array().unwrap();
    assert_eq!(by_cabinet.len(), 2, "multi-cabinet : 2 cabinets détaillés");
    let cabinet_a_json = by_cabinet
        .iter()
        .find(|c| c["cabinet_id"] == f.cabinet_a.to_string())
        .expect("cabinet A présent dans by_cabinet");
    assert_eq!(cabinet_a_json["today"]["billed_cents"], 5000);
    assert!(
        (cabinet_a_json["objective_achieved_pct"].as_f64().unwrap() - 0.5).abs() < 1e-9,
        "par cabinet : 5000 facturé / 10000 objectif = 50%"
    );
    let cabinet_b_json = by_cabinet
        .iter()
        .find(|c| c["cabinet_id"] == f.cabinet_b.to_string())
        .expect("cabinet B présent dans by_cabinet");
    assert_eq!(cabinet_b_json["today"]["billed_cents"], 2000);
    assert!(cabinet_b_json.get("objective_target_cents").is_none());

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : secrétaire → 403 (KPI praticien, pas secrétariat) ───────────────

#[tokio::test]
async fn my_kpis_secretary_forbidden() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_a, "secretary");

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/kpis")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : compte sans profil practitioner → tout à zéro, pas d'erreur ────

#[tokio::test]
async fn my_kpis_without_practitioner_profile_returns_zeroed_response() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let admin_user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(admin_user_id)
    .bind(format!("kpi-admin-only+{admin_user_id}@nubia.test"))
    .execute(&db)
    .await
    .unwrap();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet KPI Admin Only')")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    let token = make_pro_jwt(admin_user_id, cabinet_id, "admin");
    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/me/kpis")
                .header("Authorization", format!("Bearer {token}"))
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
    assert_eq!(v["today"]["billed_cents"], 0);
    assert_eq!(v["by_cabinet"].as_array().unwrap().len(), 0);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
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
        .bind(admin_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Tests 4+ : CRUD /v1/cabinet/practitioner-objectives ─────────────────────

#[tokio::test]
async fn practitioner_objectives_crud_lifecycle() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let manager_token = make_pro_jwt(f.manager_a, f.cabinet_a, "manager");
    let month = format!(
        "{:04}-{:02}",
        current_month_start().year(),
        current_month_start().month()
    );

    // CREATE
    let create_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioner-objectives")
                .header("Authorization", format!("Bearer {manager_token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "provider_id": f.provider_a,
                        "month": month,
                        "target_cents": 15000,
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(create_resp.status(), StatusCode::CREATED);
    let create_bytes = axum::body::to_bytes(create_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let created: serde_json::Value = serde_json::from_slice(&create_bytes).unwrap();
    assert_eq!(created["target_cents"], 15000);
    assert_eq!(created["provider_id"], f.provider_a.to_string());
    let objective_id = created["id"].as_str().unwrap().to_string();

    // Doublon (même provider+mois) -> 409
    let dup_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioner-objectives")
                .header("Authorization", format!("Bearer {manager_token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "provider_id": f.provider_a,
                        "month": month,
                        "target_cents": 20000,
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(dup_resp.status(), StatusCode::CONFLICT);

    // provider d'un AUTRE cabinet -> 404 (pas de fuite cross-tenant)
    let cross_tenant_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioner-objectives")
                .header("Authorization", format!("Bearer {manager_token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "provider_id": f.provider_b,
                        "month": month,
                        "target_cents": 1000,
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(cross_tenant_resp.status(), StatusCode::NOT_FOUND);

    // target_cents négatif -> 422
    let negative_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/practitioner-objectives")
                .header("Authorization", format!("Bearer {manager_token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "provider_id": f.provider_a,
                        "month": "2026-11",
                        "target_cents": -1,
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(negative_resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    // practitioner (non manager/admin) -> 403 sur la même route
    let practitioner_token = make_pro_jwt(f.user_id, f.cabinet_a, "practitioner");
    let forbidden_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/practitioner-objectives")
                .header("Authorization", format!("Bearer {practitioner_token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(forbidden_resp.status(), StatusCode::FORBIDDEN);

    // LIST
    let list_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/practitioner-objectives?month={month}"))
                .header("Authorization", format!("Bearer {manager_token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(list_resp.status(), StatusCode::OK);
    let list_bytes = axum::body::to_bytes(list_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let list: serde_json::Value = serde_json::from_slice(&list_bytes).unwrap();
    let items = list.as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["id"], objective_id);

    // PATCH
    let patch_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!(
                    "/v1/cabinet/practitioner-objectives/{objective_id}"
                ))
                .header("Authorization", format!("Bearer {manager_token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"target_cents": 25000}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(patch_resp.status(), StatusCode::OK);
    let patch_bytes = axum::body::to_bytes(patch_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let patched: serde_json::Value = serde_json::from_slice(&patch_bytes).unwrap();
    assert_eq!(patched["target_cents"], 25000);

    // DELETE
    let delete_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/v1/cabinet/practitioner-objectives/{objective_id}"
                ))
                .header("Authorization", format!("Bearer {manager_token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(delete_resp.status(), StatusCode::NO_CONTENT);

    // Déjà supprimé -> 404
    let redelete_resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/v1/cabinet/practitioner-objectives/{objective_id}"
                ))
                .header("Authorization", format!("Bearer {manager_token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(redelete_resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, &f).await;
}
