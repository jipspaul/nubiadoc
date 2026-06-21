//! Tests d'intégration : idempotency-key sur POST /v1/payments/intent

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

const JWT_SECRET: &str = "test-jwt-secret-billing-idempotency";

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
        &json!({
            "sub": user_id,
            "kind": "patient",
            "account_id": account_id,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── Test 1 : même clé → même réponse, payment créé une seule fois ────────────

#[tokio::test]
async fn payment_intent_same_key_returns_same_response() {
    if !db_available() {
        return;
    }

    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();
    let idempotency_key = format!("idem-test-{}", Uuid::new_v4());

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("idem-patient+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Idem', 'Test')",
    )
    .bind(patient_account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("idem-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet Idem Test {}", cabinet_id))
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
            "INSERT INTO patient \
             (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Idem', 'Patient', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(patient_account_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO quote \
             (id, cabinet_id, patient_id, status, total_amount, currency) \
             VALUES ($1, $2, $3, 'signed', 100.00, 'EUR')",
        )
        .bind(quote_id)
        .bind(cabinet_id)
        .bind(patient_id)
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

    let body = json!({
        "quote_id": quote_id,
        "kind": "full",
        "amount_cents": 10000,
        "method": "card"
    });

    let jwt = make_patient_jwt(user_id, patient_account_id);

    // Premier appel
    let r1 = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/payments/intent")
                .header("Content-Type", "application/json")
                .header("Authorization", format!("Bearer {}", jwt))
                .header("Idempotency-Key", &idempotency_key)
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(r1.status(), StatusCode::CREATED);
    let b1 = axum::body::to_bytes(r1.into_body(), usize::MAX)
        .await
        .unwrap();
    let v1: serde_json::Value = serde_json::from_slice(&b1).unwrap();
    let payment_id_1 = v1["payment_id"].as_str().unwrap().to_owned();
    let secret_1 = v1["client_secret"].as_str().unwrap().to_owned();

    // Deuxième appel avec la même clé → même réponse, payment non dupliqué
    let r2 = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/payments/intent")
                .header("Content-Type", "application/json")
                .header("Authorization", format!("Bearer {}", jwt))
                .header("Idempotency-Key", &idempotency_key)
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(r2.status(), StatusCode::CREATED);
    let b2 = axum::body::to_bytes(r2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&b2).unwrap();

    assert_eq!(
        v2["payment_id"], payment_id_1,
        "payment_id doit être identique au premier appel"
    );
    assert_eq!(
        v2["client_secret"], secret_1,
        "client_secret doit être identique au premier appel"
    );

    // Vérifie qu'un seul payment a été créé (idempotence garantie)
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM payment WHERE idempotency_key = $1",
        )
        .bind(&idempotency_key)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
        assert_eq!(count, 1, "un seul payment doit exister pour cette clé");
    }

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM payment WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM quote WHERE id = $1")
            .bind(quote_id)
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
    sqlx::query("DELETE FROM idempotency_keys WHERE key = $1")
        .bind(&idempotency_key)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(patient_account_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : sans header Idempotency-Key → 422 ───────────────────────────────

#[tokio::test]
async fn payment_intent_missing_idempotency_key_returns_422() {
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

    let body = json!({
        "quote_id": Uuid::new_v4(),
        "kind": "full",
        "amount_cents": 10000,
        "method": "card"
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/payments/intent")
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(Uuid::new_v4(), Uuid::new_v4())
                    ),
                )
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}
