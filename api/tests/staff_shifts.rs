//! Tests d'intégration : `/v1/cabinet/staff/shifts` — CRUD des créneaux
//! d'équipe + export PDF de la semaine (DP-F27.b, #7144).

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

const JWT_SECRET: &str = "test-secret-staff-shifts";

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

    for (user_id, first, last) in [
        (secretary_id, "Sara", "Secretaire"),
        (practitioner_id, "Paul", "Praticien"),
        (other_practitioner_id, "Otto", "Praticien"),
    ] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind, first_name, last_name) \
             VALUES ($1, $2, 'hash', 'pro', $3, $4)",
        )
        .bind(user_id)
        .bind(format!("staff-shifts+{user_id}@nubia.test"))
        .bind(first)
        .bind(last)
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
         VALUES ($1, 'Cabinet Staff Shifts Test', 'dentaire')",
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
    sqlx::query("DELETE FROM staff_shift WHERE cabinet_id = $1")
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
    let (status, _, bytes) = call_raw(state, method, uri, token, body).await;
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

async fn call_raw(
    state: AppState,
    method: &str,
    uri: &str,
    token: &str,
    body: Option<serde_json::Value>,
) -> (StatusCode, axum::http::HeaderMap, Vec<u8>) {
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
    let headers = response.headers().clone();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (status, headers, bytes.to_vec())
}

// ── CRUD ─────────────────────────────────────────────────────────────────

#[tokio::test]
async fn secretary_creates_shift_for_practitioner_and_lists_it() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.secretary_id, f.cabinet_id, "secretary");

    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/shifts",
        &token,
        Some(json!({
            "user_id": f.practitioner_id,
            "starts_at": "2026-10-05T08:00:00Z",
            "ends_at": "2026-10-05T12:00:00Z",
            "room": "Salle 1",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{created:?}");
    let shift_id = created["id"].as_str().unwrap().to_string();

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/staff/shifts?user_id={}", f.practitioner_id),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = list.as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["id"].as_str().unwrap(), shift_id);
    assert_eq!(items[0]["room"].as_str().unwrap(), "Salle 1");

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn practitioner_cannot_create_shift_for_someone_else() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/shifts",
        &token,
        Some(json!({
            "user_id": f.other_practitioner_id,
            "starts_at": "2026-10-05T08:00:00Z",
            "ends_at": "2026-10-05T12:00:00Z",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn create_shift_rejects_inverted_range() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.secretary_id, f.cabinet_id, "secretary");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/shifts",
        &token,
        Some(json!({
            "user_id": f.practitioner_id,
            "starts_at": "2026-10-05T12:00:00Z",
            "ends_at": "2026-10-05T08:00:00Z",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn patch_and_delete_shift() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.secretary_id, f.cabinet_id, "secretary");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/shifts",
        &token,
        Some(json!({
            "user_id": f.practitioner_id,
            "starts_at": "2026-10-05T08:00:00Z",
            "ends_at": "2026-10-05T12:00:00Z",
        })),
    )
    .await;
    let shift_id = created["id"].as_str().unwrap().to_string();

    let (status, patched) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/staff/shifts/{shift_id}"),
        &token,
        Some(json!({ "room": "Salle 2" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(patched["room"].as_str().unwrap(), "Salle 2");
    // Les horaires non fournis sont conservés (COALESCE).
    assert_eq!(patched["starts_at"], created["starts_at"]);

    let (status, _) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/staff/shifts/{shift_id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/staff/shifts",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(list.as_array().unwrap().is_empty());

    cleanup(&db, &f).await;
}

// ── Export PDF ───────────────────────────────────────────────────────────

#[tokio::test]
async fn shifts_pdf_contains_the_planned_week() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.secretary_id, f.cabinet_id, "secretary");

    call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/shifts",
        &token,
        Some(json!({
            "user_id": f.practitioner_id,
            "starts_at": "2026-10-05T08:00:00Z",
            "ends_at": "2026-10-05T12:00:00Z",
            "room": "Salle 1",
        })),
    )
    .await;

    let (status, headers, pdf) = call_raw(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/staff/shifts/pdf?week_start=2026-10-05",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers["content-type"], "application/pdf");
    assert!(pdf.starts_with(b"%PDF-1.4"));
    assert!(pdf.ends_with(b"%%EOF"));
    // Le nom du membre planifié doit apparaitre dans le flux texte du PDF.
    assert!(windows_contains(&pdf, b"Paul Praticien"));

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn shifts_pdf_rejects_invalid_week_start() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.secretary_id, f.cabinet_id, "secretary");

    let (status, _, _) = call_raw(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/staff/shifts/pdf?week_start=not-a-date",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

fn windows_contains(haystack: &[u8], needle: &[u8]) -> bool {
    haystack.windows(needle.len()).any(|w| w == needle)
}
