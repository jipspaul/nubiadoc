//! Tests d'intégration : POST /v1/cabinet/slots (issue #2510)
//!
//! Couvre :
//! - Admin crée un créneau → 201
//! - Secrétariat crée un créneau → 201
//! - Praticien → 403
//! - Chevauchement de créneaux (23P01 EXCLUDE) → 409 slot_taken

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

const JWT_SECRET: &str = "test-secret";

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
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    }
}

/// Enregistre un pro, renvoie `(access_token, account_id, cabinet_id, provider_id)`.
async fn register_pro(db: PgPool, email: &str) -> (String, Uuid, Uuid, Uuid) {
    let body = json!({
        "email": email,
        "password": "password1",
        "cabinet": { "raison_sociale": "Cabinet Slots Test", "siret": null, "specialite": "dentaire" },
        "practitioner": { "first_name": "Test", "last_name": "Pro", "rpps": null, "adeli": null }
    });
    let response = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/pro/register")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let token = v["access_token"].as_str().unwrap().to_string();
    let account_id: Uuid = v["account_id"].as_str().unwrap().parse().unwrap();
    let cabinet_id: Uuid = v["cabinet_id"].as_str().unwrap().parse().unwrap();
    let provider_id: Uuid = v["provider_id"].as_str().unwrap().parse().unwrap();
    (token, account_id, cabinet_id, provider_id)
}

fn make_token(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
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
            "role": role,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct SlotFixture {
    cabinet_id: Uuid,
    provider_id: Uuid,
    user_id: Uuid,
}

/// Crée un cabinet + praticien + provider avec `practitioner_id` renseigné.
/// Nécessaire pour que la contrainte EXCLUDE se déclenche sur les chevauchements.
async fn insert_slot_fixture(db: &PgPool) -> SlotFixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
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
    .bind(user_id)
    .bind(format!("slots-fixture+{}@nubia.test", user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Slots {}", cabinet_id))
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

    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, specialite, is_listed) \
         VALUES ($1, $2, $3, $4, $5, 'dentaire', false)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(user_id)
    .bind(format!("Dr Slots {}", prac_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    SlotFixture {
        cabinet_id,
        provider_id,
        user_id,
    }
}

async fn cleanup_by_email(db: &PgPool, email: &str) {
    sqlx::query("DELETE FROM app_user WHERE email = $1")
        .bind(email)
        .execute(db)
        .await
        .ok();
}

async fn cleanup_fixture(db: &PgPool, cabinet_id: Uuid, user_id: Uuid) {
    sqlx::query("DELETE FROM availability_slot WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : admin crée un créneau → 201 ─────────────────────────────────────

#[tokio::test]
async fn create_slot_admin_returns_201() {
    if !db_available() {
        return;
    }
    let email = format!("slot_admin_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (token, _account_id, _cabinet_id, provider_id) = register_pro(db.clone(), &email).await;

    let starts_at = "2030-01-15T09:00:00Z";
    let ends_at = "2030-01-15T09:30:00Z";

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({
                        "provider_id": provider_id,
                        "starts_at": starts_at,
                        "ends_at": ends_at,
                        "capacity": 1
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["id"].as_str().is_some(), "id attendu");
    assert_eq!(v["capacity"], 1);
    assert!(v["starts_at"].as_str().is_some());
    assert!(v["ends_at"].as_str().is_some());
    assert!(v["status"].as_str().is_some());

    cleanup_by_email(&owner_pool().await, &email).await;
}

// ── Test 2 : secrétariat crée un créneau → 201 ───────────────────────────────

#[tokio::test]
async fn create_slot_secretary_returns_201() {
    if !db_available() {
        return;
    }
    let email = format!("slot_secretary_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_admin_token, account_id, cabinet_id, provider_id) =
        register_pro(db.clone(), &email).await;

    let secretary_token = make_token(account_id, cabinet_id, "secretary");

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", secretary_token))
                .body(Body::from(
                    json!({
                        "provider_id": provider_id,
                        "starts_at": "2030-02-10T14:00:00Z",
                        "ends_at": "2030-02-10T14:30:00Z",
                        "capacity": 1
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);

    cleanup_by_email(&owner_pool().await, &email).await;
}

// ── Test 3 : praticien → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn create_slot_practitioner_returns_403() {
    if !db_available() {
        return;
    }
    let email = format!("slot_prac_403_{}@test.local", Uuid::new_v4());
    let db = app_pool().await;
    let (_admin_token, account_id, cabinet_id, provider_id) =
        register_pro(db.clone(), &email).await;

    let prac_token = make_token(account_id, cabinet_id, "practitioner");

    let resp = app(make_state(db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", prac_token))
                .body(Body::from(
                    json!({
                        "provider_id": provider_id,
                        "starts_at": "2030-03-01T10:00:00Z",
                        "ends_at": "2030-03-01T10:30:00Z",
                        "capacity": 1
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup_by_email(&owner_pool().await, &email).await;
}

// ── Test 4 : chevauchement EXCLUDE → 409 slot_taken ──────────────────────────

#[tokio::test]
async fn create_slot_overlap_returns_409() {
    if !db_available() {
        return;
    }
    let db = app_pool().await;
    let fixture = insert_slot_fixture(&db).await;
    let token = make_token(fixture.user_id, fixture.cabinet_id, "admin");

    let body_first = json!({
        "provider_id": fixture.provider_id,
        "starts_at": "2030-04-05T08:00:00Z",
        "ends_at":   "2030-04-05T09:00:00Z",
        "capacity": 1
    })
    .to_string();

    let body_overlap = json!({
        "provider_id": fixture.provider_id,
        "starts_at": "2030-04-05T08:30:00Z",
        "ends_at":   "2030-04-05T09:30:00Z",
        "capacity": 1
    })
    .to_string();

    let state = make_state(db.clone());

    let resp1 = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body_first))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        resp1.status(),
        StatusCode::CREATED,
        "premier créneau doit être créé"
    );

    let resp2 = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body_overlap))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        resp2.status(),
        StatusCode::CONFLICT,
        "chevauchement doit retourner 409"
    );
    let bytes = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "slot_taken");

    cleanup_fixture(&owner_pool().await, fixture.cabinet_id, fixture.user_id).await;
}
