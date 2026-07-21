//! Tests d'intégration : `POST /v1/cabinet/appointments/series` (#4088).

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

const JWT_SECRET: &str = "test-jwt-secret-appointment-series";

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
    practitioner_id: Uuid,
    patient_id: Uuid,
}

async fn insert_fixture(db: &PgPool, tag: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet AppointmentSeries {tag} {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("appt-series-{tag}+{user_id}@nubia.test"))
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES ($1, $2, 'Serge', 'Series')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        practitioner_id,
        patient_id,
    }
}

async fn cleanup_fixture(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

/// Spec de l'issue : création atomique de 3 RDV liés par recurrence_id.
#[tokio::test]
async fn create_series_creates_three_linked_appointments() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "atomic").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointments/series")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "practitioner_id": f.practitioner_id,
                        "patient_id": f.patient_id,
                        "motif": "Parodontologie",
                        "occurrences": [
                            {"starts_at": "2026-09-01T09:00:00Z", "ends_at": "2026-09-01T09:30:00Z"},
                            {"starts_at": "2026-09-08T09:00:00Z", "ends_at": "2026-09-08T09:30:00Z"},
                            {"starts_at": "2026-09-15T09:00:00Z", "ends_at": "2026-09-15T09:30:00Z"}
                        ]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let appointments = v["appointments"].as_array().unwrap();
    assert_eq!(appointments.len(), 3, "3 RDV créés");
    let recurrence_id = v["recurrence_id"].as_str().unwrap();

    let db_count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM appointment WHERE recurrence_id = $1::uuid")
            .bind(recurrence_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(
        db_count, 3,
        "les 3 RDV partagent le même recurrence_id en base"
    );

    cleanup_fixture(&db, &f).await;
}

/// Spec de l'issue : rollback complet si le 2e créneau est occupé.
#[tokio::test]
async fn create_series_rolls_back_entirely_on_conflict() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "rollback").await;

    // Pré-occupe le créneau du 2e RDV de la série à venir.
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO appointment \
             (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
             VALUES ($1, $2, $3, '2026-10-08 09:00+00', '2026-10-08 09:30+00', 'confirmed')",
        )
        .bind(f.cabinet_id)
        .bind(f.patient_id)
        .bind(f.practitioner_id)
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

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointments/series")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "practitioner_id": f.practitioner_id,
                        "patient_id": f.patient_id,
                        "motif": "Parodontologie",
                        "occurrences": [
                            {"starts_at": "2026-10-01T09:00:00Z", "ends_at": "2026-10-01T09:30:00Z"},
                            {"starts_at": "2026-10-08T09:00:00Z", "ends_at": "2026-10-08T09:30:00Z"},
                            {"starts_at": "2026-10-15T09:00:00Z", "ends_at": "2026-10-15T09:30:00Z"}
                        ]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CONFLICT);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "slot_taken");

    // Rollback complet : le 1er RDV (non conflictuel) n'a PAS été créé non plus.
    let db_count: i64 = {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        let count = sqlx::query_scalar(
            "SELECT count(*) FROM appointment WHERE starts_at = '2026-10-01T09:00:00Z'::timestamptz",
        )
        .fetch_one(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
        count
    };
    assert_eq!(
        db_count, 0,
        "rollback complet : même le 1er RDV (sans conflit) n'est pas créé"
    );

    cleanup_fixture(&db, &f).await;
}

/// Non-régression : occurrences vide → 422.
#[tokio::test]
async fn create_series_empty_occurrences_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "empty").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointments/series")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "practitioner_id": f.practitioner_id,
                        "patient_id": f.patient_id,
                        "occurrences": []
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixture(&db, &f).await;
}
