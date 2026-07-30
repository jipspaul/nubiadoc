//! Tests d'intégration : POST /v1/cabinet/quotes/:id/payment-schedule avec
//! `provider='alma'` déclenche la souscription via `AlmaClient` (#4163).

use async_trait::async_trait;
use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app_with_alma_client, AlmaClient, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-payment-schedule-alma";

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
            "sub": sub, "kind": "pro", "cabinet_id": cabinet_id,
            "role": "practitioner", "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Client Alma mocké — enregistre chaque appel (#4163). `should_fail`
/// simule un refus provider pour vérifier que la création échoue entière.
struct MockAlmaClient {
    calls: Arc<AtomicUsize>,
    should_fail: bool,
}

#[async_trait]
impl AlmaClient for MockAlmaClient {
    async fn subscribe(
        &self,
        schedule_id: Uuid,
        _total_amount_cents: i64,
    ) -> Result<String, String> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        if self.should_fail {
            return Err("alma refused".to_string());
        }
        Ok(format!("alma-sub-{schedule_id}"))
    }
}

struct Fixtures {
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    quote_id: Uuid,
}

async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("alma-prac+{prac_user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Alma Test', 'dentaire')",
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
         VALUES ($1, $2, 'Alma', 'Patient')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'signed', 150.00, 'EUR')",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        prac_user_id,
        quote_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM payment_schedule WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
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
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

#[tokio::test]
async fn create_schedule_with_alma_provider_calls_alma_client() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let calls = Arc::new(AtomicUsize::new(0));
    let alma_client = Arc::new(MockAlmaClient {
        calls: calls.clone(),
        should_fail: false,
    });

    let resp = app_with_alma_client(make_state(app_pool().await), alma_client)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/quotes/{}/payment-schedule",
                    f.quote_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::from(
                    json!({
                        "installments": [{"date": "2026-08-01", "amount_cents": 15000}],
                        "provider": "alma"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "#4163 : AlmaClient::subscribe doit etre appele exactement 1 fois"
    );

    let body: serde_json::Value = serde_json::from_slice(
        &axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap(),
    )
    .unwrap();
    let schedule_id: Uuid = body["schedule_id"].as_str().unwrap().parse().unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT provider_ref FROM payment_schedule WHERE id = $1")
        .bind(schedule_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let provider_ref: Option<String> = row.try_get("provider_ref").unwrap();
    assert_eq!(provider_ref, Some(format!("alma-sub-{schedule_id}")));

    cleanup_fixtures(&db, &f).await;
}

#[tokio::test]
async fn create_schedule_alma_refused_fails_whole_creation() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let calls = Arc::new(AtomicUsize::new(0));
    let alma_client = Arc::new(MockAlmaClient {
        calls: calls.clone(),
        should_fail: true,
    });

    let resp = app_with_alma_client(make_state(app_pool().await), alma_client)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/quotes/{}/payment-schedule",
                    f.quote_id
                ))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::from(
                    json!({
                        "installments": [{"date": "2026-08-01", "amount_cents": 15000}],
                        "provider": "alma"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::INTERNAL_SERVER_ERROR);
    assert_eq!(calls.load(Ordering::SeqCst), 1);

    // Aucun echeancier fantome persiste (rollback de la transaction).
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM payment_schedule WHERE cabinet_id = $1")
            .bind(f.cabinet_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(count, 0);

    cleanup_fixtures(&db, &f).await;
}
