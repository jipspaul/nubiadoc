//! Tests d'intégration : GET /v1/cabinet/waiting-room (§E.2)
//!
//! Couvre :
//! - Pro (praticien) voit le nom complet du patient
//! - Secrétariat voit les initiales (cloisonnement clinique)
//! - 401 sans token

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

const JWT_SECRET: &str = "test-jwt-secret-waiting-room";

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
        + 3600;
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

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid, secretariat_id: Option<Uuid>) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": "secretary",
            "secretariat_id": secretariat_id,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct CabinetFixture {
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    provider_id: Uuid,
}

async fn insert_cabinet(db: &PgPool) -> CabinetFixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

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
    .bind(format!("wr-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet WR {}", cabinet_id))
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
         VALUES ($1, $2, $3, $4, $5, 'dentaire', false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .bind(format!("Dr WR {}", prac_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    CabinetFixture {
        cabinet_id,
        prac_id,
        prac_user_id,
        provider_id,
    }
}

/// Insère un patient nommé et un RDV checked-in pour ce cabinet.
async fn insert_named_patient_appt(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_id: Uuid,
    first_name: &str,
    last_name: &str,
) -> Uuid {
    let appt_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, $3, $4)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(first_name)
    .bind(last_name)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif, checkin_at) \
         VALUES ($1, $2, $3, $4, date_trunc('day', now()) + interval '12 hours', \
                 date_trunc('day', now()) + interval '12 hours 30 minutes', \
                 'checked_in', 'test', now())",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    appt_id
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, prac_user_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider_secretariat WHERE EXISTS (SELECT 1 FROM secretariat s WHERE s.id = provider_secretariat.secretariat_id AND s.cabinet_id = $1)")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM secretariat WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
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

// ── Test 1 : praticien voit le nom complet ────────────────────────────────────

#[tokio::test]
async fn waiting_room_pro_sees_full_name() {
    if !db_available() {
        return;
    }

    let db = owner_pool().await;
    let app_db = app_pool().await;

    let f = insert_cabinet(&db).await;
    insert_named_patient_appt(&db, f.cabinet_id, f.prac_id, "Jean", "Dupont").await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/waiting-room")
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
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let data = v["data"].as_array().unwrap();
    assert!(!data.is_empty(), "au moins 1 entrée attendue");
    assert_eq!(
        data[0]["patient_name_initials"].as_str().unwrap(),
        "Jean Dupont",
        "le praticien doit voir le nom complet"
    );
    assert!(
        data[0].get("wait_minutes").is_some(),
        "wait_minutes doit être présent"
    );

    cleanup(&db, f.cabinet_id, f.prac_user_id).await;
}

// ── Test 2 : secrétariat voit les initiales ───────────────────────────────────

#[tokio::test]
async fn waiting_room_secretary_sees_initials() {
    if !db_available() {
        return;
    }

    let db = owner_pool().await;
    let app_db = app_pool().await;

    let f = insert_cabinet(&db).await;

    let sec_id = Uuid::new_v4();
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec Test Initiales')",
        )
        .bind(sec_id)
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO provider_secretariat (provider_id, secretariat_id, active) \
             VALUES ($1, $2, true)",
        )
        .bind(f.provider_id)
        .bind(sec_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    insert_named_patient_appt(&db, f.cabinet_id, f.prac_id, "Marie", "Dupont").await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let sec_user_id = Uuid::new_v4();
    let token = make_secretary_token(sec_user_id, f.cabinet_id, Some(sec_id));
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/waiting-room")
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
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let data = v["data"].as_array().unwrap();
    assert!(!data.is_empty(), "au moins 1 entrée attendue");
    assert_eq!(
        data[0]["patient_name_initials"].as_str().unwrap(),
        "MD",
        "le secrétariat doit voir les initiales uniquement"
    );

    cleanup(&db, f.cabinet_id, f.prac_user_id).await;
}

// ── Test 3 : 401 sans token ───────────────────────────────────────────────────

#[tokio::test]
async fn waiting_room_no_token_returns_401() {
    if !db_available() {
        return;
    }

    let app_db = app_pool().await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/waiting-room")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
