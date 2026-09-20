//! Tests d'intégration : GET /v1/cabinet/quotes/overview (#7176, DP-F15.b)
//! — vue « suivi devis » multi-praticiens : compteurs par statut, taux de
//! signature, délai moyen, détail par praticien.

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-quotes-overview";

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

struct Fixtures {
    cabinet_id: Uuid,
    prac_a_id: Uuid,
    prac_b_id: Uuid,
}

/// Cabinet + 2 praticiens (avec fiche `provider` pour le nom affiché) + 5
/// devis répartis : praticien A (`signed` + `sent`), praticien B (`draft` +
/// `refused`), un devis sans praticien attribué (`sent`).
async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let prac_a_user_id = Uuid::new_v4();
    let prac_b_user_id = Uuid::new_v4();
    let prac_a_id = Uuid::new_v4();
    let prac_b_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Overview Test {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_a_id)
        .bind(cabinet_id)
        .bind(prac_a_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO provider (id, practitioner_id, cabinet_id, user_id, display_name) \
         VALUES ($1, $2, $3, $4, 'Dr A Overview')",
    )
    .bind(Uuid::new_v4())
    .bind(prac_a_id)
    .bind(cabinet_id)
    .bind(prac_a_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_b_id)
        .bind(cabinet_id)
        .bind(prac_b_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO provider (id, practitioner_id, cabinet_id, user_id, display_name) \
         VALUES ($1, $2, $3, $4, 'Dr B Overview')",
    )
    .bind(Uuid::new_v4())
    .bind(prac_b_id)
    .bind(cabinet_id)
    .bind(prac_b_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Overview', 'Patient')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Praticien A : un devis signé (délai de signature ~48h) + un devis envoyé.
    sqlx::query(
        "INSERT INTO quote \
         (id, cabinet_id, patient_id, practitioner_id, status, total_amount, currency, \
          sent_at, signed_at) \
         VALUES ($1, $2, $3, $4, 'signed', 100.00, 'EUR', now() - interval '2 days', now())",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_a_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO quote \
         (id, cabinet_id, patient_id, practitioner_id, status, total_amount, currency, sent_at) \
         VALUES ($1, $2, $3, $4, 'sent', 50.00, 'EUR', now() - interval '1 day')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_a_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Praticien B : un brouillon (hors ratio) + un devis refusé.
    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, practitioner_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, $4, 'draft', 30.00, 'EUR')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_b_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO quote \
         (id, cabinet_id, patient_id, practitioner_id, status, total_amount, currency, sent_at) \
         VALUES ($1, $2, $3, $4, 'refused', 20.00, 'EUR', now() - interval '5 days')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_b_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Devis sans praticien attribué (créé par un rôle non-clinicien) : compte
    // dans `by_status` mais absent de `by_practitioner`.
    sqlx::query(
        "INSERT INTO quote \
         (id, cabinet_id, patient_id, status, total_amount, currency, sent_at) \
         VALUES ($1, $2, $3, 'sent', 10.00, 'EUR', now() - interval '1 day')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        prac_a_id,
        prac_b_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
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
    sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
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
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn get_overview(state: AppState, token: &str, query: &str) -> serde_json::Value {
    let uri = if query.is_empty() {
        "/v1/cabinet/quotes/overview".to_string()
    } else {
        format!("/v1/cabinet/quotes/overview?{query}")
    };
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(uri)
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&body).unwrap()
}

fn status_count<'a>(v: &'a serde_json::Value, status: &str) -> &'a serde_json::Value {
    v["by_status"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["status"] == status)
        .unwrap_or_else(|| panic!("statut {status} absent de by_status"))
}

#[tokio::test]
async fn overview_aggregates_cabinet_wide_by_status_and_practitioner() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = insert_fixtures(&owner_db).await;
    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "admin");

    let body = get_overview(state_with(app_pool().await), &token, "").await;

    // by_status couvre les 5 statuts, même ceux à 0 (`expired`).
    assert_eq!(status_count(&body, "draft")["count"], 1);
    assert_eq!(status_count(&body, "draft")["amount_cents"], 3000);
    assert_eq!(status_count(&body, "sent")["count"], 2);
    assert_eq!(status_count(&body, "sent")["amount_cents"], 6000);
    assert_eq!(status_count(&body, "signed")["count"], 1);
    assert_eq!(status_count(&body, "signed")["amount_cents"], 10000);
    assert_eq!(status_count(&body, "refused")["count"], 1);
    assert_eq!(status_count(&body, "refused")["amount_cents"], 2000);
    assert_eq!(status_count(&body, "expired")["count"], 0);
    assert_eq!(status_count(&body, "expired")["amount_cents"], 0);

    // Cabinet entier : 1 signé sur 4 (sent+signed+refused+expired) = 0.25.
    assert!((body["signature_rate"].as_f64().unwrap() - 0.25).abs() < 1e-9);
    // Un seul devis signé, délai ~48h.
    let avg_hours = body["avg_time_to_sign_hours"].as_f64().unwrap();
    assert!((avg_hours - 48.0).abs() < 0.1, "avg_hours={avg_hours}");

    // by_practitioner : 2 entrées (le devis sans praticien est exclu),
    // triées par count décroissant — ici A et B sont à égalité (2 chacun),
    // on vérifie donc par recherche plutôt que par position.
    let by_prac = body["by_practitioner"].as_array().unwrap();
    assert_eq!(by_prac.len(), 2);

    let prac_a = by_prac
        .iter()
        .find(|p| p["practitioner_id"] == f.prac_a_id.to_string())
        .unwrap();
    assert_eq!(prac_a["practitioner_name"], "Dr A Overview");
    assert_eq!(prac_a["count"], 2);
    assert_eq!(prac_a["amount_cents"], 15000);
    assert_eq!(prac_a["signed_count"], 1);
    assert!((prac_a["signature_rate"].as_f64().unwrap() - 0.5).abs() < 1e-9);
    let prac_a_avg = prac_a["avg_time_to_sign_hours"].as_f64().unwrap();
    assert!((prac_a_avg - 48.0).abs() < 0.1);

    let prac_b = by_prac
        .iter()
        .find(|p| p["practitioner_id"] == f.prac_b_id.to_string())
        .unwrap();
    assert_eq!(prac_b["practitioner_name"], "Dr B Overview");
    assert_eq!(prac_b["count"], 2);
    assert_eq!(prac_b["amount_cents"], 5000);
    assert_eq!(prac_b["signed_count"], 0);
    assert!((prac_b["signature_rate"].as_f64().unwrap() - 0.0).abs() < 1e-9);
    assert!(prac_b["avg_time_to_sign_hours"].is_null());

    cleanup(&owner_db, &f).await;
}

#[tokio::test]
async fn overview_provider_filter_isolates_one_practitioner() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = insert_fixtures(&owner_db).await;
    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "admin");

    let body = get_overview(
        state_with(app_pool().await),
        &token,
        &format!("provider={}", f.prac_a_id),
    )
    .await;

    assert_eq!(status_count(&body, "sent")["count"], 1);
    assert_eq!(status_count(&body, "signed")["count"], 1);
    assert_eq!(status_count(&body, "draft")["count"], 0);
    assert_eq!(status_count(&body, "refused")["count"], 0);

    assert!((body["signature_rate"].as_f64().unwrap() - 0.5).abs() < 1e-9);

    let by_prac = body["by_practitioner"].as_array().unwrap();
    assert_eq!(by_prac.len(), 1);
    assert_eq!(by_prac[0]["practitioner_id"], f.prac_a_id.to_string());

    cleanup(&owner_db, &f).await;
}

#[tokio::test]
async fn overview_rejects_malformed_period() {
    if !db_available() {
        return;
    }
    let cabinet_id = Uuid::new_v4();
    let token = make_pro_jwt(Uuid::new_v4(), cabinet_id, "admin");

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/quotes/overview?period=not-a-month")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}
