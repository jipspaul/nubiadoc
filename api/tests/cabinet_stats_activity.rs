//! Tests d'intégration : GET /v1/cabinet/stats/activity (#4079)

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-stats-activity";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": user_id,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": role,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    prac1_id: Uuid,
    prac2_id: Uuid,
    admin_user_id: Uuid,
    patient_id: Uuid,
    appointment_id: Uuid,
}

async fn insert_fixture(db: &PgPool, tag: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let admin_user_id = Uuid::new_v4();
    let prac1_user_id = Uuid::new_v4();
    let prac2_user_id = Uuid::new_v4();
    let prac1_id = Uuid::new_v4();
    let prac2_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appointment_id = Uuid::new_v4();

    for (id, kind) in [
        (admin_user_id, "pro"),
        (prac1_user_id, "pro"),
        (prac2_user_id, "pro"),
    ] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(id)
        .bind(format!("stats-{}-{}+{}@nubia.test", tag, kind, id))
        .bind(kind)
        .execute(db)
        .await
        .unwrap();
    }

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Stats {} {}", tag, cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac1_id)
        .bind(cabinet_id)
        .bind(prac1_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac2_id)
        .bind(cabinet_id)
        .bind(prac2_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'Stats')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', now(), 'done')",
    )
    .bind(appointment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac1_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        prac1_id,
        prac2_id,
        admin_user_id,
        patient_id,
        appointment_id,
    }
}

async fn insert_act(
    db: &PgPool,
    f: &Fixture,
    practitioner_id: Uuid,
    ccam_code: &str,
    amount_cents: i32,
) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO consultation_act \
         (cabinet_id, appointment_id, patient_id, practitioner_id, ccam_code, label, amount_cents) \
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(f.cabinet_id)
    .bind(f.appointment_id)
    .bind(f.patient_id)
    .bind(practitioner_id)
    .bind(ccam_code)
    .bind(format!("Acte test {ccam_code}"))
    .bind(amount_cents)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_act WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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
        .bind(f.admin_user_id)
        .execute(db)
        .await
        .ok();
}

#[tokio::test]
async fn activity_stats_counts_acts_per_practitioner_and_code() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "count").await;

    // Praticien 1 : 2 actes du même code (5000c), 1 acte d'un autre code (3000c).
    insert_act(&db, &f, f.prac1_id, "HBLD724", 5000).await;
    insert_act(&db, &f, f.prac1_id, "HBLD724", 5000).await;
    insert_act(&db, &f, f.prac1_id, "HBMD006", 3000).await;
    // Praticien 2 : 1 acte.
    insert_act(&db, &f, f.prac2_id, "HBLD724", 4000).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/stats/activity")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(f.admin_user_id, f.cabinet_id, "admin")
                    ),
                )
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
    let items = v["data"].as_array().unwrap();

    let prac1_hbld724 = items
        .iter()
        .find(|i| {
            i["practitioner_id"].as_str() == Some(&f.prac1_id.to_string())
                && i["ccam_code"].as_str() == Some("HBLD724")
        })
        .expect("agrégat praticien 1 / HBLD724 attendu");
    assert_eq!(prac1_hbld724["act_count"], 2);
    assert_eq!(prac1_hbld724["total_amount_cents"], 10000);

    let prac1_hbmd006 = items
        .iter()
        .find(|i| {
            i["practitioner_id"].as_str() == Some(&f.prac1_id.to_string())
                && i["ccam_code"].as_str() == Some("HBMD006")
        })
        .expect("agrégat praticien 1 / HBMD006 attendu");
    assert_eq!(prac1_hbmd006["act_count"], 1);
    assert_eq!(prac1_hbmd006["total_amount_cents"], 3000);

    let prac2_hbld724 = items
        .iter()
        .find(|i| {
            i["practitioner_id"].as_str() == Some(&f.prac2_id.to_string())
                && i["ccam_code"].as_str() == Some("HBLD724")
        })
        .expect("agrégat praticien 2 / HBLD724 attendu");
    assert_eq!(prac2_hbld724["act_count"], 1);
    assert_eq!(prac2_hbld724["total_amount_cents"], 4000);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn activity_stats_no_jwt_returns_401() {
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
                .uri("/v1/cabinet/stats/activity")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn activity_stats_invalid_date_returns_422() {
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
                .uri("/v1/cabinet/stats/activity?from=not-a-date")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "admin")
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}
