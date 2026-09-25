//! Tests d'intégration : `/v1/cabinet/staff/leave-requests` — workflow
//! congé demande → validation manager → décision (DP-F27.b, #7144).

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

const JWT_SECRET: &str = "test-secret-staff-leave";

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
    admin_id: Uuid,
    practitioner_id: Uuid,
    other_practitioner_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let admin_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let other_practitioner_id = Uuid::new_v4();

    for user_id in [admin_id, practitioner_id, other_practitioner_id] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(user_id)
        .bind(format!("staff-leave+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Staff Leave Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    for (user_id, role) in [
        (admin_id, "admin"),
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
        admin_id,
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
    sqlx::query("DELETE FROM leave_request WHERE cabinet_id = $1")
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

    for user_id in [f.admin_id, f.practitioner_id, f.other_practitioner_id] {
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

async fn create_pending(f: &Fixture, token: &str) -> String {
    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/leave-requests",
        token,
        Some(json!({
            "starts_at": "2026-11-02T00:00:00Z",
            "ends_at": "2026-11-06T00:00:00Z",
            "kind": "paid_leave",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{created:?}");
    let _ = f;
    created["id"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn create_leave_request_rejects_unknown_kind() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/staff/leave-requests",
        &token,
        Some(json!({
            "starts_at": "2026-11-02T00:00:00Z",
            "ends_at": "2026-11-06T00:00:00Z",
            "kind": "vacances",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn practitioner_sees_only_own_requests() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");
    let other_token = make_pro_token(f.other_practitioner_id, f.cabinet_id, "practitioner");

    create_pending(&f, &token).await;
    create_pending(&f, &other_token).await;

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/staff/leave-requests",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = list.as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(
        items[0]["user_id"].as_str().unwrap(),
        f.practitioner_id.to_string()
    );

    // L'admin voit tout le cabinet.
    let admin_token = make_pro_token(f.admin_id, f.cabinet_id, "admin");
    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/staff/leave-requests",
        &admin_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 2);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn secretary_role_cannot_decide_only_admin_or_manager() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");
    let leave_id = create_pending(&f, &token).await;

    let secretary_token = make_pro_token(f.other_practitioner_id, f.cabinet_id, "secretary");
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/staff/leave-requests/{leave_id}/decide"),
        &secretary_token,
        Some(json!({ "approve": true })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn admin_approves_then_second_decision_conflicts() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");
    let leave_id = create_pending(&f, &token).await;

    let admin_token = make_pro_token(f.admin_id, f.cabinet_id, "admin");
    let (status, decided) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/staff/leave-requests/{leave_id}/decide"),
        &admin_token,
        Some(json!({ "approve": true })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(decided["status"].as_str().unwrap(), "approved");
    assert_eq!(
        decided["decided_by"].as_str().unwrap(),
        f.admin_id.to_string()
    );

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/staff/leave-requests/{leave_id}/decide"),
        &admin_token,
        Some(json!({ "approve": false })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn requester_cancels_own_request_but_not_someone_elses() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.practitioner_id, f.cabinet_id, "practitioner");
    let other_token = make_pro_token(f.other_practitioner_id, f.cabinet_id, "practitioner");
    let leave_id = create_pending(&f, &token).await;

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/staff/leave-requests/{leave_id}/cancel"),
        &other_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, cancelled) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/staff/leave-requests/{leave_id}/cancel"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(cancelled["status"].as_str().unwrap(), "cancelled");

    cleanup(&db, &f).await;
}
