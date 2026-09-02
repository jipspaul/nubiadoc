//! Tests d'intégration : notifications du cycle de vie d'un devis cabinet
//! (#6262) — `POST /v1/cabinet/quotes/:id/send` notifie le patient
//! (`quote_received`), `POST /v1/quotes/:id/sign` notifie le praticien +
//! le secrétariat (`quote_signed`). Avant #6262, `cabinet_quotes.rs`
//! n'appelait aucun `notify_*` (seule la relance `quote_relance_dispatch`
//! notifiait).

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

const JWT_SECRET: &str = "test-jwt-secret-quote-lifecycle-notifications";

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

struct Fixture {
    cabinet_id: Uuid,
    practitioner_user_id: Uuid,
    secretary_user_id: Uuid,
    patient_account_user_id: Uuid,
    patient_account_id: Uuid,
    patient_id: Uuid,
    quote_id: Uuid,
}

/// Seed : cabinet + un membre `practitioner` + un membre `secretary` +
/// patient (compte app + fiche) + devis au statut `status`.
async fn seed(db: &PgPool, status: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let practitioner_user_id = Uuid::new_v4();
    let secretary_user_id = Uuid::new_v4();
    let patient_account_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(practitioner_user_id)
    .bind(format!(
        "quote-lifecycle-practitioner+{practitioner_user_id}@nubia.test"
    ))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(secretary_user_id)
    .bind(format!(
        "quote-lifecycle-secretary+{secretary_user_id}@nubia.test"
    ))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_account_user_id)
    .bind(format!(
        "quote-lifecycle-patient+{patient_account_user_id}@nubia.test"
    ))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Lifecycle')",
    )
    .bind(patient_account_id)
    .bind(patient_account_user_id)
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
        .bind(format!("Cabinet Lifecycle {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) \
         VALUES ($1, $2, 'practitioner', true)",
    )
    .bind(cabinet_id)
    .bind(practitioner_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) \
         VALUES ($1, $2, 'secretary', true)",
    )
    .bind(cabinet_id)
    .bind(secretary_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Test', 'Lifecycle', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, $4, 150.00, 'EUR')",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        practitioner_user_id,
        secretary_user_id,
        patient_account_user_id,
        patient_account_id,
        patient_id,
        quote_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE id = $1")
        .bind(f.quote_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_membership WHERE cabinet_id = $1")
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

    sqlx::query("DELETE FROM notification WHERE app_user_id IN ($1, $2, $3)")
        .bind(f.practitioner_user_id)
        .bind(f.secretary_user_id)
        .bind(f.patient_account_user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id IN ($1, $2, $3)")
        .bind(f.practitioner_user_id)
        .bind(f.secretary_user_id)
        .bind(f.patient_account_user_id)
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

async fn send_quote(
    state: AppState,
    quote_id: Uuid,
    token: String,
) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/quotes/{quote_id}/send"))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

async fn sign_quote(
    state: AppState,
    quote_id: Uuid,
    token: String,
) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/quotes/{quote_id}/sign"))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

async fn count_notifications(db: &PgPool, app_user_id: Uuid, kind: &str) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM notification WHERE app_user_id = $1 AND kind = $2")
        .bind(app_user_id)
        .bind(kind)
        .fetch_one(db)
        .await
        .unwrap()
}

// ── Test 1 : envoi d'un devis brouillon → le patient reçoit quote_received ──

#[tokio::test]
async fn sending_quote_notifies_patient() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "draft").await;

    let (status, _) = send_quote(
        state_with(app_pool().await),
        f.quote_id,
        make_pro_jwt(f.practitioner_user_id, f.cabinet_id, "practitioner"),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        count_notifications(&db, f.patient_account_user_id, "quote_received").await,
        1
    );

    cleanup(&db, &f).await;
}

// ── Test 2 : signature d'un devis envoyé → praticien + secrétariat notifiés ─

#[tokio::test]
async fn signing_quote_notifies_practitioner_and_secretary() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "sent").await;

    let (status, body) = sign_quote(
        state_with(app_pool().await),
        f.quote_id,
        make_patient_jwt(f.patient_account_user_id, f.patient_account_id),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["signed"], true);

    assert_eq!(
        count_notifications(&db, f.practitioner_user_id, "quote_signed").await,
        1
    );
    assert_eq!(
        count_notifications(&db, f.secretary_user_id, "quote_signed").await,
        1
    );

    cleanup(&db, &f).await;
}

// ── Test 3 : idempotence — re-signer un devis déjà signé ne renotifie pas ──

#[tokio::test]
async fn re_signing_already_signed_quote_does_not_renotify() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;

    let (status, _) = sign_quote(
        state_with(app_pool().await),
        f.quote_id,
        make_patient_jwt(f.patient_account_user_id, f.patient_account_id),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        count_notifications(&db, f.practitioner_user_id, "quote_signed").await,
        0
    );
    assert_eq!(
        count_notifications(&db, f.secretary_user_id, "quote_signed").await,
        0
    );

    cleanup(&db, &f).await;
}
