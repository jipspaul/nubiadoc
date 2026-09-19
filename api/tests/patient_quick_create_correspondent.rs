//! Tests d'intégration : champ « adressé par » sur `POST
//! /v1/cabinet/patients/quick` (#7193, DP-F8.c) — `correspondent_id`
//! optionnel référencant l'annuaire `cabinet_correspondent` (#7194/#7195).

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

const JWT_SECRET: &str = "test-jwt-secret-patient-quick-create-correspondent";

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

/// `secretariat_id`, s'il est fourni, scope le token secrétaire au
/// secrétariat correspondant (R10) — requis pour que `quick_create_patient`
/// pose `created_by_secretariat_id` et que `GET /v1/cabinet/patients/:id`
/// retrouve ensuite ce patient dans le périmètre de ce même secrétariat.
fn make_pro_jwt(
    user_id: Uuid,
    cabinet_id: Uuid,
    role: &str,
    secretariat_id: Option<Uuid>,
) -> String {
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
            "secretariat_id": secretariat_id,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    user_id: Uuid,
    secretariat_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("quick-create-correspondent+{user_id}@nubia.test"))
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
        .bind(format!("Cabinet Quick Create Correspondent {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec Quick Create')")
        .bind(secretariat_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
        secretariat_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM audit_log WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("UPDATE patient SET referred_by_correspondent_id = NULL WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_correspondent WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM secretariat WHERE cabinet_id = $1")
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

// ── Test 1 : correspondent_id valide — persisté et restitué sur GET détail ──

#[tokio::test]
async fn quick_create_with_correspondent_id_persists_and_shows_on_detail() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary", Some(f.secretariat_id));

    let (_, correspondent) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/correspondents",
        &token,
        Some(json!({"display_name": "Dr Adresseur Quick"})),
    )
    .await;
    let correspondent_id = correspondent["id"].as_str().unwrap().to_string();

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/patients/quick",
        &token,
        Some(json!({
            "first_name": "Léa",
            "last_name": "Adressée",
            "correspondent_id": correspondent_id,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{resp}");
    assert_eq!(resp["referred_by_correspondent_id"], correspondent_id);
    let patient_id = resp["id"].as_str().unwrap().to_string();

    let (status, detail) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/patients/{patient_id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{detail}");
    assert_eq!(
        detail["referred_by_correspondent"]["id"],
        correspondent_id
    );
    assert_eq!(
        detail["referred_by_correspondent"]["display_name"],
        "Dr Adresseur Quick"
    );

    cleanup(&db, &f).await;
}

// ── Test 2 : correspondent_id absent — champ omis, pas d'erreur ─────────────

#[tokio::test]
async fn quick_create_without_correspondent_id_omits_field() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary", Some(f.secretariat_id));

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/patients/quick",
        &token,
        Some(json!({"first_name": "Sans", "last_name": "Adressage"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{resp}");
    assert!(resp.get("referred_by_correspondent_id").is_none());

    cleanup(&db, &f).await;
}

// ── Test 3 : correspondent_id inconnu / hors cabinet → 404 ──────────────────

#[tokio::test]
async fn quick_create_with_unknown_correspondent_id_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary", Some(f.secretariat_id));

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/patients/quick",
        &token,
        Some(json!({
            "first_name": "Inconnu",
            "last_name": "Correspondant",
            "correspondent_id": Uuid::new_v4().to_string(),
        })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{resp}");

    // Aucun dossier patient créé malgré le 404 (transaction non commitée).
    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/patients?q=Inconnu",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{list}");
    assert_eq!(list["data"].as_array().unwrap().len(), 0);

    cleanup(&db, &f).await;
}

// ── Test 4 : correspondent_id d'un autre cabinet → 404 (cloisonnement) ──────

#[tokio::test]
async fn quick_create_with_other_cabinet_correspondent_id_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let other = seed(&db).await;
    let token = make_pro_jwt(f.user_id, f.cabinet_id, "secretary", Some(f.secretariat_id));
    let other_token = make_pro_jwt(
        other.user_id,
        other.cabinet_id,
        "secretary",
        Some(other.secretariat_id),
    );

    let (_, other_correspondent) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/correspondents",
        &other_token,
        Some(json!({"display_name": "Dr Autre Cabinet"})),
    )
    .await;
    let other_correspondent_id = other_correspondent["id"].as_str().unwrap().to_string();

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/patients/quick",
        &token,
        Some(json!({
            "first_name": "Cloisonnement",
            "last_name": "Test",
            "correspondent_id": other_correspondent_id,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{resp}");

    cleanup(&db, &f).await;
    cleanup(&db, &other).await;
}
