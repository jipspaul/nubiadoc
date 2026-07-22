//! Test d'intégration : notification patient au retour du laboratoire (#4165)
//! `PATCH /v1/cabinet/lab-work-orders/{id}` avec `status: "returned"` crée
//! une notification `lab_work_returned` pour le patient concerné.

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

const JWT_SECRET: &str = "test-secret-lab-work-returned";

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

struct Fixture {
    cabinet_id: Uuid,
    pro_user_id: Uuid,
    patient_app_user_id: Uuid,
    patient_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let pro_user_id = Uuid::new_v4();
    let patient_app_user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(pro_user_id)
    .bind(format!("labworkreturn-pro+{pro_user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_app_user_id)
    .bind(format!(
        "labworkreturn-patient+{patient_app_user_id}@nubia.test"
    ))
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
         VALUES ($1, 'Cabinet LabWork Returned Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, $3, 'Patient', 'Prothese')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_app_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        pro_user_id,
        patient_app_user_id,
        patient_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    sqlx::query("DELETE FROM notification WHERE app_user_id = $1")
        .bind(f.patient_app_user_id)
        .execute(db)
        .await
        .ok();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM lab_work_order WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.pro_user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.patient_app_user_id)
        .execute(db)
        .await
        .ok();
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

#[tokio::test]
async fn returned_status_creates_patient_notification() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_practitioner_token(f.pro_user_id, f.cabinet_id);

    let create_response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/lab-work-orders")
                .header("Authorization", format!("Bearer {token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "patient_id": f.patient_id,
                        "lab_name": "Labo Dentaire Retour",
                        "purchase_price_cents": 18000
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(create_response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(create_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let created: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let order_id: Uuid = created["order_id"].as_str().unwrap().parse().unwrap();

    let patch_response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/lab-work-orders/{order_id}"))
                .header("Authorization", format!("Bearer {token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"status": "returned"}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(patch_response.status(), StatusCode::OK);

    let notif = sqlx::query(
        "SELECT kind, data FROM notification WHERE app_user_id = $1 AND kind = 'lab_work_returned'",
    )
    .bind(f.patient_app_user_id)
    .fetch_optional(&db)
    .await
    .unwrap();
    let notif = notif.expect("une notification lab_work_returned doit exister pour le patient");
    let data: serde_json::Value = notif.try_get("data").unwrap();
    assert_eq!(data["order_id"], order_id.to_string());

    cleanup(&db, &f).await;
}
