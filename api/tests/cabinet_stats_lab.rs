//! Tests d'intégration : GET /v1/cabinet/lab-stats (#7164, DP-F19.b)

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-stats-lab";

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

/// Jeu de test : 2 bons de travail sur le mois courant.
/// - Bon A (labo "Dentalis") rattaché à une ligne de devis du praticien X :
///   coût labo 200€ (20000c), CA patient 500€ (50000c) -> marge 300€.
/// - Bon B (labo "Protheo") sans ligne de devis : coût labo 80€ (8000c),
///   pas de CA patient identifiable -> marge -80€, absent de by_practitioner.
#[tokio::test]
async fn lab_stats_computes_margin_per_act_practitioner_and_lab() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let admin_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();
    let quote_item_id = Uuid::new_v4();
    let order_a_id = Uuid::new_v4();
    let order_b_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(admin_user_id)
    .bind(format!("stats-lab-admin+{admin_user_id}@nubia.test"))
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("stats-lab-prac+{prac_user_id}@nubia.test"))
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
        .bind(format!("Cabinet Stats Lab {cabinet_id}"))
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
         VALUES ($1, $2, 'Patient', 'StatsLab')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, practitioner_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, $4, 'signed', 500, 'EUR')",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote_item (id, cabinet_id, quote_id, label, qty, unit_amount) \
         VALUES ($1, $2, $3, 'Couronne céramique', 1, 500)",
    )
    .bind(quote_item_id)
    .bind(cabinet_id)
    .bind(quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Bon A : rattaché au devis (CA patient identifiable), coût 200€.
    sqlx::query(
        "INSERT INTO lab_work_order \
         (id, cabinet_id, patient_id, quote_item_id, lab_name, purchase_price_cents) \
         VALUES ($1, $2, $3, $4, 'Dentalis', 20000)",
    )
    .bind(order_a_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(quote_item_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Bon B : sans ligne de devis, coût 80€, aucun CA patient identifiable.
    sqlx::query(
        "INSERT INTO lab_work_order \
         (id, cabinet_id, patient_id, lab_name, purchase_price_cents) \
         VALUES ($1, $2, $3, 'Protheo', 8000)",
    )
    .bind(order_b_id)
    .bind(cabinet_id)
    .bind(patient_id)
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
                .uri("/v1/cabinet/lab-stats")
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

    assert_eq!(v["total_lab_cost_cents"], 28000, "200€ + 80€ = 280€");
    assert_eq!(
        v["total_patient_revenue_cents"], 50000,
        "seul le bon A a un CA patient identifiable (500€)"
    );
    assert_eq!(
        v["total_margin_cents"], 22000,
        "500€ CA - 280€ coût labo = 220€"
    );

    let by_act = v["by_act"].as_array().unwrap();
    assert_eq!(by_act.len(), 2);
    let act_a = by_act
        .iter()
        .find(|a| a["lab_work_order_id"] == order_a_id.to_string())
        .unwrap();
    assert_eq!(act_a["lab_cost_cents"], 20000);
    assert_eq!(act_a["patient_revenue_cents"], 50000);
    assert_eq!(act_a["margin_cents"], 30000, "500€ - 200€ = 300€");
    assert_eq!(act_a["practitioner_id"], prac_id.to_string());

    let act_b = by_act
        .iter()
        .find(|a| a["lab_work_order_id"] == order_b_id.to_string())
        .unwrap();
    assert_eq!(act_b["lab_cost_cents"], 8000);
    assert_eq!(act_b["patient_revenue_cents"], 0);
    assert_eq!(
        act_b["margin_cents"], -8000,
        "coût labo sans CA patient identifié"
    );
    assert!(act_b.get("practitioner_id").is_none() || act_b["practitioner_id"].is_null());

    let by_lab = v["by_lab"].as_array().unwrap();
    assert_eq!(by_lab.len(), 2);
    let dentalis = by_lab.iter().find(|l| l["lab_name"] == "Dentalis").unwrap();
    assert_eq!(dentalis["margin_cents"], 30000);
    let protheo = by_lab.iter().find(|l| l["lab_name"] == "Protheo").unwrap();
    assert_eq!(protheo["margin_cents"], -8000);

    let by_practitioner = v["by_practitioner"].as_array().unwrap();
    assert_eq!(
        by_practitioner.len(),
        1,
        "seul le bon A est rattaché à un praticien via le devis"
    );
    assert_eq!(by_practitioner[0]["practitioner_id"], prac_id.to_string());
    assert_eq!(by_practitioner[0]["margin_cents"], 30000);

    // Cleanup
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM lab_work_order WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_item WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM app_user WHERE id IN ($1, $2)")
        .bind(admin_user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}

#[tokio::test]
async fn lab_stats_no_jwt_returns_401() {
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
                .uri("/v1/cabinet/lab-stats")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
