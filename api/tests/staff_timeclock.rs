//! Tests d'intégration : `/v1/cabinet/staff/time-clock` — pointage par QR
//! tournant (TOTP 60 s) et saisie manuelle autorisée (DP-F27.b, #7144).

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

const JWT_SECRET: &str = "test-secret-staff-timeclock";

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

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900
}

fn make_pro_token(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": role,
            "exp": exp(),
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    secretary_id: Uuid,
    practitioner_id: Uuid,
    other_practitioner_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let secretary_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let other_practitioner_id = Uuid::new_v4();

    for user_id in [secretary_id, practitioner_id, other_practitioner_id] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(user_id)
        .bind(format!("staff-timeclock+{user_id}@nubia.test"))
        .execute(db)
        .await
        .unwrap();
    }

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Staff Timeclock Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    for (user_id, role) in [
        (secretary_id, "secretary"),
        (practitioner_id, "practitioner"),
        (other_practitioner_id, "practitioner"),
    ] {
        sqlx::query(
            "INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES ($1, $2, $3)",
        )
        .bind(cabinet_id)
        .bind(user_id)
        .bind(role)
        .execute(&mut *tx)
        .await
        .unwrap();
    }
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        secretary_id,
        practitioner_id,
        other_practitioner_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM time_clock_entry WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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

    for user_id in [f.secretary_id, f.practitioner_id, f.other_practitioner_id] {
        sqlx::query("DELETE FROM app_user WHERE id = $1")
            .bind(user_id)
            .execute(db)
            .await
            .ok();
    }
}

async fn call(
    state: AppState,
    method: &str,
    uri: &str,
    token: &str,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("Authorization", format!("Bearer {token}"));
    let body = match body {
        Some(v) => {
            builder = builder.header("Content-Type", "application/json");
            Body::from(v.to_string())
        }
        None => Body::empty(),
    };
    let response = app(state)
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

async fn current_code(token: &str) -> String {
    let (status, resp) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/staff/time-clock/code",
        token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{resp:?}");
    resp["code"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn time_clock_code_is_a_six_digit_totp() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");

    let (status, resp) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/staff/time-clock/code",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let code = resp["code"].as_str().unwrap();
    assert_eq!(code.len(), 6);
    assert!(code.chars().all(|c| c.is_ascii_digit()));
    assert!(resp["expires_in_seconds"].as_u64().unwrap() <= 60);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn clock_in_with_qr_code_is_for_self_then_double_entry_conflicts() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");
    let code = current_code(&token).await;

    let (status, entry) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/time-clock/in",
        &token,
        Some(json!({ "code": code })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{entry:?}");
    assert_eq!(
        entry["user_id"].as_str().unwrap(),
        f.practitioner_id.to_string()
    );
    assert_eq!(entry["source"].as_str().unwrap(), "mobile");

    // Second badge sans avoir badgé la sortie → conflit.
    let code = current_code(&token).await;
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/time-clock/in",
        &token,
        Some(json!({ "code": code })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn clock_in_with_wrong_code_is_rejected() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/time-clock/in",
        &token,
        Some(json!({ "code": "000000" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn clock_out_closes_the_open_entry() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");
    let code = current_code(&token).await;

    call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/time-clock/in",
        &token,
        Some(json!({ "code": code })),
    )
    .await;

    let code = current_code(&token).await;
    let (status, entry) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/time-clock/out",
        &token,
        Some(json!({ "code": code })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{entry:?}");
    assert!(entry["clock_out"].is_string());

    // Plus aucune entrée ouverte → nouvelle sortie = 404.
    let code = current_code(&token).await;
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/time-clock/out",
        &token,
        Some(json!({ "code": code })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn manual_entry_requires_an_elevated_role() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let practitioner_token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");

    // Un praticien ne peut pas se déclarer manuellement présent.
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/time-clock/in",
        &practitioner_token,
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // Le secrétariat peut badger manuellement pour un membre du cabinet.
    let secretary_token = make_pro_token(f.secretary_id, f.cabinet_id, "secretary");
    let (status, entry) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/time-clock/in",
        &secretary_token,
        Some(json!({ "user_id": f.other_practitioner_id })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{entry:?}");
    assert_eq!(entry["source"].as_str().unwrap(), "manual");
    assert_eq!(
        entry["user_id"].as_str().unwrap(),
        f.other_practitioner_id.to_string()
    );

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn list_time_clock_filters_by_user() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");
    let code = current_code(&token).await;
    call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/time-clock/in",
        &token,
        Some(json!({ "code": code })),
    )
    .await;

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        &format!(
            "/v1/cabinet/staff/time-clock?user_id={}",
            f.other_practitioner_id
        ),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(list.as_array().unwrap().is_empty());

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/staff/time-clock?user_id={}", f.practitioner_id),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 1);

    cleanup(&db, &f).await;
}
