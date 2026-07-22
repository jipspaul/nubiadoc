//! Tests d'intégration : routes CRUD `cr_template` (#4124)
//! - `GET`/`POST /v1/cabinet/cr-templates`
//! - `PATCH`/`DELETE /v1/cabinet/cr-templates/:id`

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

const JWT_SECRET: &str = "test-jwt-secret-cr-templates";
/// Code CCAM du catalogue seedé (migration 0119) — déjà utilisé par
/// d'autres suites de tests (#4117) comme code valide connu.
const KNOWN_CCAM_CODE: &str = "HBLD001";

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

struct Fixture {
    cabinet_id: Uuid,
    user_id: Uuid,
}

/// Seed : cabinet + practitioner, aucun modèle (créés par les tests eux-mêmes).
async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("cr-tmpl+{user_id}@nubia.test"))
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
        .bind(format!("Cabinet CrTmpl {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cr_template WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.user_id)
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

// ── Test 1 : création (générique + liée à un acte CCAM) puis liste ──────────

#[tokio::test]
async fn create_then_list_returns_both_templates() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/cr-templates",
        &token,
        Some(json!({"title": "CR standard", "body_template": "Compte rendu : {{notes}}"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert!(resp["id"].is_string());

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/cr-templates",
        &token,
        Some(json!({
            "ccam_code": KNOWN_CCAM_CODE,
            "title": "CR pose implant",
            "body_template": "Pose d'implant {{tooth}}"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert!(resp["id"].is_string());

    let (status, resp) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/cr-templates",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let templates = resp.as_array().unwrap();
    assert_eq!(templates.len(), 2);
    assert!(templates
        .iter()
        .any(|t| t["title"] == "CR standard" && t["ccam_code"].is_null()));
    assert!(templates
        .iter()
        .any(|t| t["title"] == "CR pose implant" && t["ccam_code"] == KNOWN_CCAM_CODE));

    cleanup(&db, &f).await;
}

// ── Test 2 : ccam_code inexistant -> 422 ─────────────────────────────────────

#[tokio::test]
async fn create_with_unknown_ccam_code_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/cr-templates",
        &token,
        Some(json!({
            "ccam_code": "CODE_INEXISTANT",
            "title": "Invalide",
            "body_template": "x"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test 3 : PATCH modifie le titre, laisse le reste inchangé ───────────────

#[tokio::test]
async fn patch_updates_title_only() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/cr-templates",
        &token,
        Some(json!({"title": "Brouillon", "body_template": "corps initial"})),
    )
    .await;
    let id = created["id"].as_str().unwrap();

    let (status, _) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/cr-templates/{id}"),
        &token,
        Some(json!({"title": "Titre final"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/cr-templates",
        &token,
        None,
    )
    .await;
    let tmpl = &list.as_array().unwrap()[0];
    assert_eq!(tmpl["title"], "Titre final");
    assert_eq!(tmpl["body_template"], "corps initial");

    cleanup(&db, &f).await;
}

// ── Test 4 : DELETE supprime, un second appel renvoie 404 ───────────────────

#[tokio::test]
async fn delete_then_delete_again_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/cr-templates",
        &token,
        Some(json!({"title": "À supprimer", "body_template": "x"})),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (status, _) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/cr-templates/{id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, _) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/cr-templates/{id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}

// ── Test 5 : RLS — un cabinet ne peut ni PATCH ni DELETE le modèle d'un autre ──

#[tokio::test]
async fn patch_and_delete_template_of_other_cabinet_return_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "practitioner");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/cr-templates",
        &token,
        Some(json!({"title": "Cabinet A", "body_template": "x"})),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let other = seed(&db).await;
    let other_token = make_pro_jwt(other.user_id, other.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/cr-templates/{id}"),
        &other_token,
        Some(json!({"title": "Hijack"})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, _) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/cr-templates/{id}"),
        &other_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &other).await;
    cleanup(&db, &f).await;
}
