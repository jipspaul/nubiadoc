//! Tests d'intégration : GET /v1/cabinet/slots — lister les créneaux réservables
//! (admin/secrétariat). Comble la lacune backend #3055 (405 sur GET, seule la
//! route POST était enregistrée).

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

const JWT_SECRET: &str = "test-jwt-secret-slots-get-3055";

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
            "exp": exp,
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    prac_id: Uuid,
}

async fn setup(db: &PgPool, prefix: &str) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

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
    .bind(format!("slots-get-{}-{}@nubia.test", prefix, prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet SlotsGet {} {}", prefix, cabinet_id))
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

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        prac_user_id,
        prac_id,
    }
}

async fn teardown(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM availability_slot WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

async fn create_slot(state: &AppState, cabinet_id: Uuid, prac_id: Uuid, starts: &str, ends: &str) {
    let token = make_pro_jwt(Uuid::new_v4(), cabinet_id, "admin");
    let resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "practitioner_id": prac_id,
                        "starts_at": starts,
                        "ends_at": ends,
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::CREATED);
}

async fn state() -> AppState {
    AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

// ── Test 1 : GET renvoie 200 + le créneau créé (contrat front SlotDto) ────────

#[tokio::test]
async fn get_cabinet_slots_returns_created_slot() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "list").await;
    let st = state().await;

    create_slot(
        &st,
        f.cabinet_id,
        f.prac_id,
        "2035-06-01T09:00:00Z",
        "2035-06-01T10:00:00Z",
    )
    .await;

    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary");
    let resp = app(st.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let arr = v.as_array().expect("réponse doit être un tableau");
    assert_eq!(arr.len(), 1, "un seul créneau attendu");
    let slot = &arr[0];
    assert!(slot["id"].is_string(), "id présent");
    assert_eq!(slot["cabinet_id"], f.cabinet_id.to_string());
    assert_eq!(slot["practitioner_id"], f.prac_id.to_string());
    assert!(slot["starts_at"].is_string(), "starts_at présent");
    assert!(slot["ends_at"].is_string(), "ends_at présent");
    assert_eq!(slot["is_available"], true, "créneau ouvert → is_available");

    teardown(&db, &f).await;
}

// ── Test 2 : filtre practitioner_id ──────────────────────────────────────────

#[tokio::test]
async fn get_cabinet_slots_filters_by_practitioner() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "filter").await;
    let st = state().await;

    create_slot(
        &st,
        f.cabinet_id,
        f.prac_id,
        "2035-08-01T09:00:00Z",
        "2035-08-01T10:00:00Z",
    )
    .await;

    // Filtre sur un praticien inexistant → liste vide.
    let other = Uuid::new_v4();
    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "admin");
    let resp = app(st.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/slots?practitioner_id={}", other))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(
        v.as_array().unwrap().len(),
        0,
        "aucun créneau pour un autre praticien"
    );

    teardown(&db, &f).await;
}
