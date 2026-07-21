//! Tests d'intégration : avertissement de sous-cotation sur
//! POST /v1/cabinet/consultations/:id/acts (#4162)

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

const JWT_SECRET: &str = "test-secret-acts-underquote";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
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
            "role": "practitioner",
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    patient_id: Uuid,
    appt_id: Uuid,
    session_id: Uuid,
    ccam_code: String,
}

/// `ccam_act` est un référentiel national non tenant, `INSERT` réservé au
/// rôle owner (`GRANT SELECT ON ccam_act TO nubia_app` uniquement, migration
/// 0119) — code de test unique pour ne pas percuter le catalogue seedé.
async fn insert_fixture(db: &PgPool, tag: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();
    let ccam_code = format!("TSTUQ{}", tag.to_uppercase());

    sqlx::query(
        "INSERT INTO ccam_act (code, label, tarif_cents, active) \
         VALUES ($1, 'Acte test sous-cotation', 10000, true)",
    )
    .bind(&ccam_code)
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
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("acts-uq-{}-prac+{}@nubia.test", tag, prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Acts UnderQuote Test', 'dentaire')",
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'UnderQuote')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now(), now() + interval '1 hour', 'in_progress', 'détartrage')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO consultation_session \
         (id, cabinet_id, appointment_id, practitioner_id, status) \
         VALUES ($1, $2, $3, $4, 'in_progress')",
    )
    .bind(session_id)
    .bind(cabinet_id)
    .bind(appt_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
        ccam_code,
    }
}

async fn cleanup_fixture(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_session WHERE id = $1")
        .bind(f.session_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_act WHERE appointment_id = $1")
        .bind(f.appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(f.appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(f.prac_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM ccam_act WHERE code = $1")
        .bind(&f.ccam_code)
        .execute(db)
        .await
        .ok();
}

// ── amount_cents très inférieur au tarif de référence (10000c) → warning ────

#[tokio::test]
async fn add_act_significantly_underquoted_returns_warning() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "low").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // 50% du tarif de référence (10000c) → bien en dessous du seuil (80%).
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", f.session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(f.prac_user_id, f.cabinet_id)
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "ccam_code": f.ccam_code,
                        "label": "Acte test",
                        "amount_cents": 5000
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(
        v["warning"]
            .as_str()
            .is_some_and(|w| w.contains(&f.ccam_code)),
        "un avertissement de sous-cotation est attendu, réponse : {v}"
    );

    cleanup_fixture(&db, &f).await;
}

// ── amount_cents proche du tarif de référence → pas de warning ──────────────

#[tokio::test]
async fn add_act_amount_close_to_tariff_returns_no_warning() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "ok").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // 95% du tarif de référence (10000c) → au-dessus du seuil (80%).
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", f.session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(f.prac_user_id, f.cabinet_id)
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "ccam_code": f.ccam_code,
                        "label": "Acte test",
                        "amount_cents": 9500
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(
        v.get("warning").is_none(),
        "aucun avertissement attendu, réponse : {v}"
    );

    cleanup_fixture(&db, &f).await;
}

// ── code CCAM hors référentiel (pas de tarif connu) → pas de warning ────────

#[tokio::test]
async fn add_act_unknown_ccam_code_returns_no_warning() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "unk").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", f.session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(f.prac_user_id, f.cabinet_id)
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "ccam_code": "NOTINCATALOG",
                        "label": "Acte hors référentiel",
                        "amount_cents": 1
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v.get("warning").is_none(), "réponse : {v}");

    cleanup_fixture(&db, &f).await;
}
