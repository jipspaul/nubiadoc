//! Tests d'intégration : POST /v1/cabinet/appointments/:id/notify-practitioner
//! (#6696) — le CTA « Prévenir le praticien » du bandeau d'escalade de la
//! salle d'attente (#5170) n'émettait jusqu'ici aucune requête ; cet endpoint
//! insère une notification in-app pour le praticien concerné.

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

const JWT_SECRET: &str = "test-secret-notify-practitioner";

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

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900
}

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid, secretariat_id: Option<Uuid>) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": "secretary",
            "secretariat_id": secretariat_id,
            "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_patient_token(sub: Uuid, account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({ "sub": sub, "kind": "patient", "account_id": account_id, "exp": exp() }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn count_notifications(db: &PgPool, app_user_id: Uuid, kind: &str) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM notification WHERE app_user_id = $1 AND kind = $2")
        .bind(app_user_id)
        .bind(kind)
        .fetch_one(db)
        .await
        .unwrap()
}

/// Insère cabinet + praticien (+ provider/secrétariat scopés) + patient +
/// rendez-vous `checked_in`. Retourne
/// `(cabinet_id, prac_user_id, secretariat_id, patient_id, appt_id)`.
async fn insert_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("notify-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet Notify', 'dentaire')",
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
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, specialite, is_listed) \
         VALUES ($1, $2, $3, $4, 'Dr Notify', 'dentaire', false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec Notify')")
        .bind(secretariat_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO provider_secretariat (provider_id, secretariat_id, active) \
         VALUES ($1, $2, true)",
    )
    .bind(provider_id)
    .bind(secretariat_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Dupont')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif, checkin_at) \
         VALUES ($1, $2, $3, $4, now() - interval '45 minutes', now() + interval '15 minutes', \
                 'checked_in', 'détartrage', now() - interval '45 minutes')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (cabinet_id, prac_user_id, secretariat_id, patient_id, appt_id)
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    secretariat_id: Uuid,
    patient_id: Uuid,
    appt_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM notification WHERE app_user_id = $1")
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider_secretariat WHERE secretariat_id = $1")
        .bind(secretariat_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM secretariat WHERE id = $1")
        .bind(secretariat_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

// ── Test 1 : secrétaire scopée sur le praticien → 200 + notification insérée ──

#[tokio::test]
async fn notify_practitioner_secretary_in_scope_happy_path() {
    if !db_available() {
        return;
    }

    let owner_db = owner_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_user_id, secretariat_id, patient_id, appt_id) =
        insert_fixture(&owner_db).await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let token = make_secretary_token(Uuid::new_v4(), cabinet_id, Some(secretariat_id));
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/appointments/{}/notify-practitioner", appt_id))
                .header("Authorization", format!("Bearer {}", token))
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
    assert_eq!(body["notified"], true);

    assert_eq!(
        count_notifications(&owner_db, prac_user_id, "waiting_room_overdue").await,
        1,
        "une notification 'waiting_room_overdue' doit être insérée pour le praticien"
    );

    cleanup_fixture(&owner_db, cabinet_id, prac_user_id, secretariat_id, patient_id, appt_id)
        .await;
}

// ── Test 2 : rendez-vous inconnu → 404, aucune notification ──────────────────

#[tokio::test]
async fn notify_practitioner_unknown_appointment_returns_404() {
    if !db_available() {
        return;
    }

    let app_db = app_pool().await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let token = make_secretary_token(Uuid::new_v4(), Uuid::new_v4(), Some(Uuid::new_v4()));
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/appointments/{}/notify-practitioner",
                    Uuid::new_v4()
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}

// ── Test 3 : token patient → 403 ─────────────────────────────────────────────

#[tokio::test]
async fn notify_practitioner_patient_token_returns_403() {
    if !db_available() {
        return;
    }

    let app_db = app_pool().await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let patient_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let token = make_patient_token(patient_user_id, account_id);

    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/appointments/{}/notify-practitioner",
                    Uuid::new_v4()
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}
