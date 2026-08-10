//! Tests d'intégration : GET /v1/appointments/:id/consultation-clinique
//! (#4646 — lecture patient du compte-rendu clinique finalisé).

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

const JWT_SECRET: &str = "test-jwt-secret-cc-read";

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

/// Fixture : cabinet + praticien + provider + patient + RDV.
/// Retourne (cabinet_id, prac_id, patient_id, appt_id).
async fn insert_appointment_fixture(
    db: &PgPool,
    prac_user_id: Uuid,
    patient_account_id: Uuid,
) -> (Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet CC Read Test {}", cabinet_id))
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
         VALUES ($1, $2, 'Test', 'Patient', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, \
                 now() - interval '1 day', now() - interval '1 day' + interval '1 hour', \
                 'done', 'détartrage')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    (cabinet_id, prac_id, patient_id, appt_id)
}

async fn insert_consultation_clinique(
    db: &PgPool,
    cabinet_id: Uuid,
    appt_id: Uuid,
    prac_id: Uuid,
    status: &str,
) -> Uuid {
    let cc_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO consultation_clinique \
         (id, cabinet_id, appointment_id, practitioner_id, content_ciphertext, content_key_ref, status) \
         VALUES ($1, $2, $3, $4, $5, 'stub-key', $6)",
    )
    .bind(cc_id)
    .bind(cabinet_id)
    .bind(appt_id)
    .bind(prac_id)
    .bind(
        {
            let plain = b"RAS, controle dans 6 mois.";
            let mut buf = b"STUB_ENC:".to_vec();
            buf.extend(plain.iter().map(|b| b ^ 0xFF));
            buf
        },
    )
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    cc_id
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
    appt_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_clinique WHERE appointment_id = $1")
        .bind(appt_id)
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

// ── Test 1 : compte-rendu finalisé → 200 avec contenu déchiffré ─────────────

#[tokio::test]
async fn consultation_clinique_finalized_returns_200_with_content() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("cc-read+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'CC', 'Read')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("cc-read-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    let (cabinet_id, prac_id, patient_id, appt_id) =
        insert_appointment_fixture(&db, prac_user_id, account_id).await;
    insert_consultation_clinique(&db, cabinet_id, appt_id, prac_id, "finalized").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/appointments/{}/consultation-clinique",
                    appt_id
                ))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
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

    assert_eq!(v["appointment_id"], appt_id.to_string());
    assert_eq!(v["status"], "finalized");
    assert_eq!(v["content"], "RAS, controle dans 6 mois.");

    cleanup_fixture(&db, cabinet_id, prac_id, patient_id, appt_id).await;
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : compte-rendu encore en brouillon → 404 (invisible au patient) ──

#[tokio::test]
async fn consultation_clinique_draft_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("cc-draft+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'CC', 'Draft')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("cc-draft-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    let (cabinet_id, prac_id, patient_id, appt_id) =
        insert_appointment_fixture(&db, prac_user_id, account_id).await;
    insert_consultation_clinique(&db, cabinet_id, appt_id, prac_id, "draft").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/appointments/{}/consultation-clinique",
                    appt_id
                ))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "un compte-rendu draft doit rester invisible au patient"
    );

    cleanup_fixture(&db, cabinet_id, prac_id, patient_id, appt_id).await;
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(user_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3 : RDV d'un autre patient → 404 (anti-énumération, RLS) ───────────

#[tokio::test]
async fn consultation_clinique_other_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_a_id = Uuid::new_v4();
    let account_a_id = Uuid::new_v4();
    let user_b_id = Uuid::new_v4();
    let account_b_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();

    for (uid, email, kind) in [
        (
            user_a_id,
            format!("cc-a+{}@nubia.test", user_a_id),
            "patient",
        ),
        (
            user_b_id,
            format!("cc-b+{}@nubia.test", user_b_id),
            "patient",
        ),
        (
            prac_user_id,
            format!("cc-prac2+{}@nubia.test", prac_user_id),
            "pro",
        ),
    ] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(uid)
        .bind(&email)
        .bind(kind)
        .execute(&db)
        .await
        .unwrap();
    }

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'A')",
    )
    .bind(account_a_id)
    .bind(user_a_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'B')",
    )
    .bind(account_b_id)
    .bind(user_b_id)
    .execute(&db)
    .await
    .unwrap();

    let (cabinet_id, prac_id, patient_id, appt_b_id) =
        insert_appointment_fixture(&db, prac_user_id, account_b_id).await;
    insert_consultation_clinique(&db, cabinet_id, appt_b_id, prac_id, "finalized").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/appointments/{}/consultation-clinique",
                    appt_b_id
                ))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_a_id, account_a_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "compte-rendu d'un autre patient doit retourner 404 (anti-énumération)"
    );

    cleanup_fixture(&db, cabinet_id, prac_id, patient_id, appt_b_id).await;
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2 OR id = $3")
        .bind(user_a_id)
        .bind(user_b_id)
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test auth : sans JWT → 401 ───────────────────────────────────────────────

#[tokio::test]
async fn consultation_clinique_no_jwt_returns_401() {
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
                .uri(format!(
                    "/v1/appointments/{}/consultation-clinique",
                    Uuid::new_v4()
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
