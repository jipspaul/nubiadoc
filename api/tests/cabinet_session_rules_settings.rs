//! Tests d'intégration : `GET/PUT /v1/cabinet/settings/session-rules`
//! (#7479 — `cabinet_session_rules` n'avait aucune route : les 4 leviers de
//! découpage documentés dans `treatment_sessions.rs` restaient à jamais aux
//! valeurs par défaut qui ne découpent rien).

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

const JWT_SECRET: &str = "test-secret-cabinet-session-rules-settings";

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

fn make_state(db: PgPool) -> AppState {
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

fn make_token(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: role.into(),
            exp: exp(),
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
}

async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("session-rules-settings+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Session-Rules Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(db)
    .await
    .unwrap();

    Fixtures {
        cabinet_id,
        user_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_session_rules WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

async fn request(
    db: PgPool,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        builder = builder.header("authorization", format!("Bearer {t}"));
    }
    let body = match body {
        Some(v) => {
            builder = builder.header("content-type", "application/json");
            Body::from(serde_json::to_vec(&v).unwrap())
        }
        None => Body::empty(),
    };
    let response = app(make_state(db))
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null),
    )
}

// ── Test 1 : GET par défaut → les défauts documentés de `SessionRules` ───────

#[tokio::test]
async fn get_returns_defaults_when_cabinet_never_set_rules() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = insert_fixtures(&owner_db).await;
    let token = make_token(f.user_id, f.cabinet_id, "admin");

    let (status, json) = request(
        app_pool().await,
        "GET",
        "/v1/cabinet/settings/session-rules",
        Some(&token),
        None,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["max_duration_min"], serde_json::Value::Null);
    assert_eq!(json["separate_arches"], false);
    assert_eq!(json["group_by_sector"], false);
    assert_eq!(json["multi_endo"], true);

    cleanup_fixtures(&owner_db, &f).await;
}

// ── Test 2 : secrétaire/praticien → 403 (réservé admin/manager) ──────────────

#[tokio::test]
async fn get_forbidden_for_non_admin_roles() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = insert_fixtures(&owner_db).await;

    for role in ["secretary", "practitioner"] {
        let token = make_token(Uuid::new_v4(), f.cabinet_id, role);
        let (status, _) = request(
            app_pool().await,
            "GET",
            "/v1/cabinet/settings/session-rules",
            Some(&token),
            None,
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "role {role} doit être 403");
    }

    cleanup_fixtures(&owner_db, &f).await;
}

// ── Test 3 : PUT max_duration_min <= 0 → 422 ──────────────────────────────────

#[tokio::test]
async fn put_rejects_non_positive_max_duration() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = insert_fixtures(&owner_db).await;
    let token = make_token(f.user_id, f.cabinet_id, "manager");

    let (status, json) = request(
        app_pool().await,
        "PUT",
        "/v1/cabinet/settings/session-rules",
        Some(&token),
        Some(json!({"max_duration_min": 0, "separate_arches": true})),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(json["code"], "validation_error");

    cleanup_fixtures(&owner_db, &f).await;
}

// ── Test 4 : PUT persiste les 4 leviers → GET les reflète ────────────────────

#[tokio::test]
async fn put_persists_rules_and_get_reflects_them() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = insert_fixtures(&owner_db).await;
    let admin_token = make_token(f.user_id, f.cabinet_id, "admin");

    let (status, json) = request(
        app_pool().await,
        "PUT",
        "/v1/cabinet/settings/session-rules",
        Some(&admin_token),
        Some(json!({
            "max_duration_min": 90,
            "separate_arches": true,
            "group_by_sector": false,
            "multi_endo": false
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["max_duration_min"], 90);
    assert_eq!(json["separate_arches"], true);
    assert_eq!(json["multi_endo"], false);

    let (status, json) = request(
        app_pool().await,
        "GET",
        "/v1/cabinet/settings/session-rules",
        Some(&admin_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["max_duration_min"], 90);
    assert_eq!(json["separate_arches"], true);
    assert_eq!(json["group_by_sector"], false);
    assert_eq!(json["multi_endo"], false);

    // Un second PUT réécrit intégralement la ligne (upsert), pas de patch
    // partiel : une des 4 valeurs change, les autres reviennent à leur
    // défaut si absentes du body.
    let (status, json) = request(
        app_pool().await,
        "PUT",
        "/v1/cabinet/settings/session-rules",
        Some(&admin_token),
        Some(json!({"max_duration_min": null, "multi_endo": true})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(json["max_duration_min"], serde_json::Value::Null);
    assert_eq!(json["separate_arches"], false);
    assert_eq!(json["multi_endo"], true);

    cleanup_fixtures(&owner_db, &f).await;
}
