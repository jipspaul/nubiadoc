//! Tests d'intégration : acompte obligatoire (`deposit_pct`) — POST /v1/billing/quotes/:id/deposit
//! + exposition dans GET /v1/quotes/:id et GET /v1/cabinet/quotes/:id (#3761)

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

const JWT_SECRET: &str = "test-jwt-secret-billing-deposit-pct";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "role": role, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    user_id: Uuid,
    patient_account_id: Uuid,
    prac_user_id: Uuid,
    cabinet_id: Uuid,
    quote_id: Uuid,
}

/// Devis `signed`, total 15000 centimes (150,00 €), deposit_pct=30 → plancher
/// attendu 4500 centimes.
async fn seed(db: &PgPool) -> Fixture {
    let user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("dep-patient+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Dep', 'Test')",
    )
    .bind(patient_account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("dep-prac+{}@nubia.test", prac_user_id))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Dep Test {}", cabinet_id))
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
         VALUES ($1, $2, 'Dep', 'Patient', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, deposit_pct) \
         VALUES ($1, $2, $3, 'signed', 150.00, 'EUR', 30)",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // #4433 : patient_share_cents (reste-à-charge) est dérivé des lignes
    // quote_item, pas de quote.total_amount — sans ligne, le devis aurait un
    // reste-à-charge de 0 et le plancher d'acompte ne serait jamais atteint.
    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, qty, unit_amount) \
         VALUES ($1, $2, 'Item test', 1, 150.00)",
    )
    .bind(cabinet_id)
    .bind(quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        user_id,
        patient_account_id,
        prac_user_id,
        cabinet_id,
        quote_id,
    }
}

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

/// Repro exacte de #3761 : un acompte très en dessous du plancher (30% de
/// 15000 = 4500) doit être refusé, pas accepté à 201.
#[tokio::test]
async fn deposit_below_floor_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/billing/quotes/{}/deposit", fx.quote_id))
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(fx.user_id, fx.patient_account_id)
                    ),
                )
                .header("Idempotency-Key", format!("dep-{}", Uuid::new_v4()))
                .body(Body::from(
                    json!({"amount_cents": 100, "method": "card"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::UNPROCESSABLE_ENTITY,
        "acompte de 100 centimes doit être refusé (plancher = 4500)"
    );

    let count: i64 = sqlx::query("SELECT count(*) AS n FROM payment WHERE quote_id = $1")
        .bind(fx.quote_id)
        .fetch_one(&db)
        .await
        .unwrap()
        .try_get("n")
        .unwrap();
    assert_eq!(count, 0, "aucun paiement ne doit être créé");
}

/// Un acompte couvrant exactement le plancher (4500) est accepté.
#[tokio::test]
async fn deposit_at_floor_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/billing/quotes/{}/deposit", fx.quote_id))
                .header("Content-Type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(fx.user_id, fx.patient_account_id)
                    ),
                )
                .header("Idempotency-Key", format!("dep-{}", Uuid::new_v4()))
                .body(Body::from(
                    json!({"amount_cents": 4500, "method": "card"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);
}

/// GET /v1/quotes/:id (patient) et GET /v1/cabinet/quotes/:id (pro) exposent
/// tous les deux deposit_pct + deposit_amount_cents dérivé.
#[tokio::test]
async fn quote_views_expose_deposit_pct() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;

    let (status, patient_view) = {
        let response = app(make_state(app_pool().await))
            .oneshot(
                Request::builder()
                    .uri(format!("/v1/quotes/{}", fx.quote_id))
                    .header(
                        "Authorization",
                        format!(
                            "Bearer {}",
                            make_patient_jwt(fx.user_id, fx.patient_account_id)
                        ),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let status = response.status();
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        (
            status,
            serde_json::from_slice::<serde_json::Value>(&body).unwrap(),
        )
    };
    assert_eq!(status, StatusCode::OK, "body: {patient_view}");
    assert_eq!(patient_view["deposit_pct"], json!(30.0));
    assert_eq!(patient_view["deposit_amount_cents"], json!(4500));

    let (status, cabinet_view) = {
        let response = app(make_state(app_pool().await))
            .oneshot(
                Request::builder()
                    .uri(format!("/v1/cabinet/quotes/{}", fx.quote_id))
                    .header(
                        "Authorization",
                        format!(
                            "Bearer {}",
                            make_pro_jwt(fx.prac_user_id, fx.cabinet_id, "practitioner")
                        ),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let status = response.status();
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        (
            status,
            serde_json::from_slice::<serde_json::Value>(&body).unwrap(),
        )
    };
    assert_eq!(status, StatusCode::OK, "body: {cabinet_view}");
    assert_eq!(cabinet_view["deposit_pct"], json!(30.0));
    assert_eq!(cabinet_view["deposit_amount_cents"], json!(4500));
}

/// Devis tiers-payant : total 1000,00€, amo_part 700,00€, deposit_pct=100 →
/// reste-à-charge patient = 300,00€ (30000 c). Repro exacte de #4433.
async fn seed_with_amo_share(db: &PgPool) -> Fixture {
    let user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("dep-amo-patient+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'DepAmo', 'Test')",
    )
    .bind(patient_account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("dep-amo-prac+{}@nubia.test", prac_user_id))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Dep Amo Test {}", cabinet_id))
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
         VALUES ($1, $2, 'DepAmo', 'Patient', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, deposit_pct) \
         VALUES ($1, $2, $3, 'signed', 1000.00, 'EUR', 100)",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, qty, unit_amount, amo_part) \
         VALUES ($1, $2, 'Item AMO', 1, 1000.00, 700.00)",
    )
    .bind(cabinet_id)
    .bind(quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        user_id,
        patient_account_id,
        prac_user_id,
        cabinet_id,
        quote_id,
    }
}

/// #4433 : le plancher d'acompte porte sur le reste-à-charge patient
/// (total - part AMO), pas sur le total brut. Ici deposit_pct=100 mais
/// amo_part=700€ sur un total de 1000€ → payer les 300€ de reste-à-charge
/// doit satisfaire l'acompte à 100%, pas exiger 1000€.
#[tokio::test]
async fn deposit_floor_uses_patient_share_not_gross_total() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed_with_amo_share(&db).await;
    let token = make_patient_jwt(fx.user_id, fx.patient_account_id);

    // Payer exactement le reste-à-charge (300€) doit être accepté.
    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/billing/quotes/{}/deposit", fx.quote_id))
                .header("Content-Type", "application/json")
                .header("Authorization", format!("Bearer {token}"))
                .header("Idempotency-Key", format!("dep-amo-{}", Uuid::new_v4()))
                .body(Body::from(
                    json!({"amount_cents": 30000, "method": "card"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::CREATED,
        "payer le reste-à-charge réel (300€) doit satisfaire l'acompte à 100%"
    );
}

/// Symétrique : payer en dessous du reste-à-charge réel (300€) est refusé,
/// même si c'est très supérieur à ce qu'un plancher calculé sur le brut
/// aurait exigé au même pourcentage.
#[tokio::test]
async fn deposit_below_patient_share_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed_with_amo_share(&db).await;
    let token = make_patient_jwt(fx.user_id, fx.patient_account_id);

    let response = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/billing/quotes/{}/deposit", fx.quote_id))
                .header("Content-Type", "application/json")
                .header("Authorization", format!("Bearer {token}"))
                .header("Idempotency-Key", format!("dep-amo-{}", Uuid::new_v4()))
                .body(Body::from(
                    json!({"amount_cents": 100, "method": "card"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::UNPROCESSABLE_ENTITY,
        "1 centime doit rester refusé (reste-à-charge = 30000)"
    );
}
