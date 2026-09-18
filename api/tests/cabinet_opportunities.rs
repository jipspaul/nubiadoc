//! Test d'intégration : GET /v1/cabinet/opportunities (#7214)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use chrono::Datelike;
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-cabinet-opportunities";

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

fn make_manager_token(sub: Uuid, cabinet_id: Uuid) -> String {
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
            "role": "manager",
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

struct Fixture {
    cabinet_id: Uuid,
    user_id: Uuid,
    patient_quote_stale_id: Uuid,
    patient_unpaid_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_quote_stale_id = Uuid::new_v4();
    let patient_unpaid_id = Uuid::new_v4();
    let unpaid_quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("cabinetopportunities+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Opportunities Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    // Anniversaire du jour : même mois/jour que `now()`, année arbitraire
    // (1990) — repli au 1er mars si `now()` tombe un 29 février (année non
    // bissextile en 1990).
    let today = chrono::Utc::now().date_naive();
    let birth_date = chrono::NaiveDate::from_ymd_opt(1990, today.month(), today.day())
        .unwrap_or_else(|| chrono::NaiveDate::from_ymd_opt(1990, 3, 1).unwrap());
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, birth_date) \
         VALUES ($1, $2, 'Devis', 'SansReponse', $3)",
    )
    .bind(patient_quote_stale_id)
    .bind(cabinet_id)
    .bind(birth_date)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Facture', 'Impayee')",
    )
    .bind(patient_unpaid_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Devis envoyé il y a 10 jours, jamais répondu.
    sqlx::query(
        "INSERT INTO quote (cabinet_id, patient_id, status, total_amount, sent_at) \
         VALUES ($1, $2, 'sent', 200.00, now() - interval '10 days')",
    )
    .bind(cabinet_id)
    .bind(patient_quote_stale_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Devis signé il y a 45 jours, aucun paiement -> facture impayée.
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, signed_at) \
         VALUES ($1, $2, $3, 'signed', 500.00, now() - interval '45 days')",
    )
    .bind(unpaid_quote_id)
    .bind(cabinet_id)
    .bind(patient_unpaid_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, qty, unit_amount) \
         VALUES ($1, $2, 'Item test', 1, 500.00)",
    )
    .bind(cabinet_id)
    .bind(unpaid_quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
        patient_quote_stale_id,
        patient_unpaid_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
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
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
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

#[tokio::test]
async fn cabinet_opportunities_returns_expected_categories() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_manager_token(f.user_id, f.cabinet_id);

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/opportunities")
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
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let categories = body["categories"].as_array().unwrap();
    assert_eq!(categories.len(), 5);

    let by_kind = |kind: &str| {
        categories
            .iter()
            .find(|c| c["kind"].as_str().unwrap() == kind)
            .unwrap()
    };

    let sent_no_response = by_kind("quote_sent_no_response");
    assert_eq!(sent_no_response["count"].as_i64().unwrap(), 1);
    assert_eq!(
        sent_no_response["items"][0]["patient_id"].as_str().unwrap(),
        f.patient_quote_stale_id.to_string()
    );

    let unpaid = by_kind("unpaid_invoice");
    assert_eq!(unpaid["count"].as_i64().unwrap(), 1);
    assert_eq!(unpaid["total_amount_cents"].as_i64().unwrap(), 50_000);
    assert_eq!(
        unpaid["items"][0]["patient_id"].as_str().unwrap(),
        f.patient_unpaid_id.to_string()
    );

    let birthdays = by_kind("birthday_today");
    assert_eq!(birthdays["count"].as_i64().unwrap(), 1);
    assert_eq!(
        birthdays["items"][0]["patient_id"].as_str().unwrap(),
        f.patient_quote_stale_id.to_string()
    );

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn cabinet_opportunities_is_tenant_isolated() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    // Un autre cabinet, sans aucune donnée : ne doit rien voir de `f`.
    let other_cabinet_id = Uuid::new_v4();
    let other_user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(other_user_id)
    .bind(format!(
        "cabinetopportunities-other+{other_user_id}@nubia.test"
    ))
    .execute(&db)
    .await
    .unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(other_cabinet_id.to_string())
        .execute(&db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Autre Cabinet', 'dentaire')",
    )
    .bind(other_cabinet_id)
    .execute(&db)
    .await
    .unwrap();

    let token = make_manager_token(other_user_id, other_cabinet_id);

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/opportunities")
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
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let categories = body["categories"].as_array().unwrap();
    for category in categories {
        assert_eq!(
            category["count"].as_i64().unwrap(),
            0,
            "category={category:?}"
        );
    }

    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(other_cabinet_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_user_id)
        .execute(&db)
        .await
        .ok();

    cleanup(&db, &f).await;
}
