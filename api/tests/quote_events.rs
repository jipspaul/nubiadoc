//! Tests d'intégration : journal du devis (#7176, DP-F15.b).
//!
//! Timeline complète (`GET /v1/quotes/:id/events`) sur un devis de test :
//! envoi (cabinet), ouverture (patient), relance (worker), signature
//! (patient) — dans cet ordre chronologique.

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

use nubia_api::{app, dispatch_quote_relances, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-quote-events";

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

struct Fixtures {
    cabinet_id: Uuid,
    patient_user_id: Uuid,
    patient_account_id: Uuid,
    pro_user_id: Uuid,
    quote_id: Uuid,
}

/// Cabinet + patient (compte app lié) + devis `draft`, `sent_days_ago` jours
/// dans le passé une fois envoyé (pour déclencher la relance j3 côté test).
async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let pro_user_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("qe-patient+{patient_user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Journal', 'Devis')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
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
        .bind(format!("Cabinet QE Test {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Journal', 'Patient', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, 'draft', 200.00, 'EUR')",
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
        patient_user_id,
        patient_account_id,
        pro_user_id,
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
    sqlx::query("DELETE FROM quote_event WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_relance WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(f.patient_user_id)
        .bind(f.pro_user_id)
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

async fn get_events(state: AppState, quote_id: Uuid, token: &str) -> Vec<serde_json::Value> {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/quotes/{quote_id}/events"))
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
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    v["data"].as_array().unwrap().clone()
}

// ── Timeline complète : sent → viewed → reminded → signed ────────────────────

#[tokio::test]
async fn quote_timeline_records_every_milestone_in_order() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixtures(&owner_db).await;

    let pro_token = make_pro_jwt(f.pro_user_id, f.cabinet_id, "practitioner");
    let patient_token = make_patient_jwt(f.patient_user_id, f.patient_account_id);

    // 1. Envoi côté cabinet — événement 'sent'.
    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/quotes/{}/send", f.quote_id))
                .header("Authorization", format!("Bearer {pro_token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // 2. Ouverture côté patient — événement 'viewed'.
    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/quotes/{}", f.quote_id))
                .header("Authorization", format!("Bearer {patient_token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // 3. Relance simulée (sent_at forcé à J-4 pour franchir le seuil j3
    //    directement, sans attendre — `dispatch_quote_relances` appelable
    //    en direct par les tests, même convention que
    //    `quote_relance_dispatch.rs`).
    sqlx::query("UPDATE quote SET sent_at = now() - interval '4 days' WHERE id = $1")
        .bind(f.quote_id)
        .execute(&owner_db)
        .await
        .unwrap();
    dispatch_quote_relances(&app_db).await.unwrap();

    // 4. Signature côté patient (stub) — événement 'signed'.
    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/quotes/{}/sign", f.quote_id))
                .header("Authorization", format!("Bearer {patient_token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // Timeline patient-lisible : les 4 jalons, dans l'ordre chronologique.
    let events = get_events(state_with(app_pool().await), f.quote_id, &patient_token).await;
    let kinds: Vec<&str> = events
        .iter()
        .map(|e| e["kind"].as_str().unwrap())
        .collect();
    assert_eq!(kinds, vec!["sent", "viewed", "reminded", "signed"]);

    assert_eq!(events[0]["actor_kind"], "cabinet");
    assert_eq!(events[1]["actor_kind"], "patient");
    assert_eq!(events[2]["actor_kind"], "system");
    assert_eq!(events[3]["actor_kind"], "patient");

    cleanup_fixtures(&owner_db, &f).await;
}

// ── Un devis draft n'expose aucune timeline au patient (RLS) ─────────────────

#[tokio::test]
async fn draft_quote_events_are_hidden_from_patient() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = insert_fixtures(&owner_db).await;
    let patient_token = make_patient_jwt(f.patient_user_id, f.patient_account_id);

    // Un événement existe bel et bien (insert direct, hors hooks applicatifs)
    // sur ce devis resté `draft` — la policy `quote_event_patient_read`
    // (même condition que `quote_patient_read`, migration 0134) doit
    // néanmoins le masquer : liste vide, jamais 404.
    {
        let mut tx = owner_db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO quote_event (quote_id, cabinet_id, kind, actor_kind) \
             VALUES ($1, $2, 'created', 'cabinet')",
        )
        .bind(f.quote_id)
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let events = get_events(state_with(app_pool().await), f.quote_id, &patient_token).await;
    assert!(events.is_empty());

    cleanup_fixtures(&owner_db, &f).await;
}
