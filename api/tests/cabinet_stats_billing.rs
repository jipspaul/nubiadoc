//! Tests d'intégration : GET /v1/cabinet/stats/billing (#4080)

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-stats-billing";

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

#[tokio::test]
async fn billing_stats_aggregates_revenue_outstanding_and_conversion() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let admin_user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_draft_id = Uuid::new_v4();
    let quote_sent_id = Uuid::new_v4();
    let quote_signed_id = Uuid::new_v4();
    let quote_refused_id = Uuid::new_v4();
    let payment_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(admin_user_id)
    .bind(format!("stats-billing-admin+{admin_user_id}@nubia.test"))
    .execute(&db)
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
        .bind(format!("Cabinet Stats Billing {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'StatsBilling')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // draft : n'entre dans AUCUN compteur (jamais envoyé).
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'draft', 100, 'EUR')",
    )
    .bind(quote_draft_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // sent : compte dans sent_total, pas dans signed_count.
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'sent', 200, 'EUR')",
    )
    .bind(quote_sent_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // signed : compte dans sent_total ET signed_count ; 500€ de dette
    // (total_amount) dont 300€ payés (payment 'paid' ci-dessous).
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'signed', 500, 'EUR')",
    )
    .bind(quote_signed_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // refused : compte dans sent_total (a été envoyé), pas signed_count.
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'refused', 150, 'EUR')",
    )
    .bind(quote_refused_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Paiement 'paid' de 300€ sur le devis signé — CA encaissé + réduit l'impayé.
    sqlx::query(
        "INSERT INTO payment \
         (id, cabinet_id, patient_id, quote_id, amount, currency, kind, provider, status) \
         VALUES ($1, $2, $3, $4, 300, 'EUR', 'installment', 'stripe', 'paid')",
    )
    .bind(payment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(quote_signed_id)
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
                .uri("/v1/cabinet/stats/billing")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(admin_user_id, cabinet_id, "admin")
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

    assert_eq!(
        v["revenue_collected_cents"], 30000,
        "300€ payés = 30000 centimes"
    );
    assert_eq!(
        v["outstanding_cents"], 20000,
        "devis signé 500€ - 300€ payé = 200€ = 20000 centimes"
    );
    assert_eq!(v["signed_count"], 1);
    assert_eq!(
        v["sent_total"], 3,
        "sent + signed + refused = 3, draft exclu"
    );
    let conversion_rate = v["conversion_rate"].as_f64().unwrap();
    assert!(
        (conversion_rate - (1.0 / 3.0)).abs() < 1e-9,
        "1 signé / 3 envoyés attendu, obtenu {conversion_rate}"
    );

    // Cleanup
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
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
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

/// #4347 : un paiement SANS lien (ou lié à un devis non-signé) ne doit pas
/// faire passer `outstanding_cents` en négatif — reproduit exactement le
/// repro de l'issue (paiement massif hors du devis signé).
#[tokio::test]
async fn billing_stats_unrelated_payment_does_not_go_negative() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let admin_user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_signed_id = Uuid::new_v4();
    let quote_draft_id = Uuid::new_v4();
    let unrelated_payment_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(admin_user_id)
    .bind(format!("stats-billing-neg+{admin_user_id}@nubia.test"))
    .execute(&db)
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
        .bind(format!("Cabinet Stats Billing Neg {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'StatsBillingNeg')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Devis signé de 50€ seulement.
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'signed', 50, 'EUR')",
    )
    .bind(quote_signed_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Devis draft — jamais engageant, un paiement dessus n'est pas une dette soldée.
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'draft', 10, 'EUR')",
    )
    .bind(quote_draft_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Paiement massif (10 000€) sur le devis DRAFT (pas signé) — reproduit
    // le repro de l'issue : un paiement sans rapport avec les devis signés
    // ne doit jamais faire passer outstanding_cents sous 0.
    sqlx::query(
        "INSERT INTO payment \
         (id, cabinet_id, patient_id, quote_id, amount, currency, kind, provider, status) \
         VALUES ($1, $2, $3, $4, 10000, 'EUR', 'full', 'stripe', 'paid')",
    )
    .bind(unrelated_payment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(quote_draft_id)
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
                .uri("/v1/cabinet/stats/billing")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(admin_user_id, cabinet_id, "admin")
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

    let outstanding = v["outstanding_cents"].as_i64().unwrap();
    assert!(
        outstanding >= 0,
        "outstanding_cents ne doit jamais être négatif (#4347), obtenu {outstanding}"
    );
    assert_eq!(
        outstanding, 5000,
        "50€ de devis signé, non soldé (le paiement de 10000€ est sur un devis draft, hors scope)"
    );

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
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
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

#[tokio::test]
async fn billing_stats_no_data_returns_null_conversion_rate() {
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
    .bind(format!("stats-billing-empty+{admin_user_id}@nubia.test"))
    .execute(&db)
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
        .bind(format!("Cabinet Stats Billing Empty {cabinet_id}"))
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
                .uri("/v1/cabinet/stats/billing")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(admin_user_id, cabinet_id, "admin")
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

    assert_eq!(v["revenue_collected_cents"], 0);
    assert_eq!(v["outstanding_cents"], 0);
    assert_eq!(v["signed_count"], 0);
    assert_eq!(v["sent_total"], 0);
    assert!(v.get("conversion_rate").is_none() || v["conversion_rate"].is_null());

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

#[tokio::test]
async fn billing_stats_no_jwt_returns_401() {
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
                .uri("/v1/cabinet/stats/billing")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
