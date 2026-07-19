//! Tests d'intégration : GET/PUT /v1/account/referring-doctor
//!
//! Couvre les deux cas de la déclaration de médecin traitant (issue #3451) :
//! - référence vers un praticien existant (`provider_id`) ;
//! - saisie libre pour un médecin hors base (`free_name` + coordonnées).

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

const JWT_SECRET: &str = "test-jwt-secret-referring-doctor";

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

fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

async fn create_patient_account(db: &PgPool) -> (Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("ref-doc+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Dupont')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();

    (user_id, account_id)
}

/// Crée un provider listé (annuaire public) et retourne son id.
async fn create_listed_provider(db: &PgPool) -> Uuid {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("ref-doc-prac+{}@nubia.test", prac_user_id))
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
        .bind(format!("Cabinet Ref Doc Test {}", cabinet_id))
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
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, is_listed, rpps_verified) \
         VALUES ($1, $2, $3, $4, 'Dr. Traitant', true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    provider_id
}

fn test_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

// ── Cas 1 : praticien référencé (provider_id) ────────────────────────────────

#[tokio::test]
async fn put_referring_doctor_with_provider_id_returns_200_and_persists() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let (user_id, account_id) = create_patient_account(&owner_db).await;
    let provider_id = create_listed_provider(&owner_db).await;

    let state = test_state(app_pool().await);

    let put_response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/referring-doctor")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({"provider_id": provider_id})).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(put_response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(put_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["provider_id"], provider_id.to_string());
    assert!(v["free_name"].is_null());

    let get_response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/referring-doctor")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_response.status(), StatusCode::OK);
    let get_body = axum::body::to_bytes(get_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let gv: serde_json::Value = serde_json::from_slice(&get_body).unwrap();
    assert_eq!(gv["provider_id"], provider_id.to_string());

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&owner_db)
        .await
        .ok();
}

// ── Cas 2 : médecin hors base (saisie libre) ─────────────────────────────────

#[tokio::test]
async fn put_referring_doctor_with_free_name_returns_200_without_provider_ref() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let (user_id, account_id) = create_patient_account(&owner_db).await;

    let state = test_state(app_pool().await);

    let put_response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/referring-doctor")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "free_name": "Dr Martin (hors Nubia)",
                        "free_phone": "+33612345678",
                        "free_address": "12 rue de la Paix, Paris"
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(put_response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(put_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(v["provider_id"].is_null());
    assert_eq!(v["free_name"], "Dr Martin (hors Nubia)");
    assert_eq!(v["free_phone"], "+33612345678");

    let get_response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/referring-doctor")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_response.status(), StatusCode::OK);
    let get_body = axum::body::to_bytes(get_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let gv: serde_json::Value = serde_json::from_slice(&get_body).unwrap();
    assert_eq!(gv["free_name"], "Dr Martin (hors Nubia)");

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&owner_db)
        .await
        .ok();
}

// ── Cas invalides : ni provider_id ni free_name, ou les deux à la fois ───────

#[tokio::test]
async fn put_referring_doctor_without_provider_or_free_name_returns_422() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let (user_id, account_id) = create_patient_account(&owner_db).await;

    let state = test_state(app_pool().await);

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/referring-doctor")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(serde_json::to_string(&json!({})).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&owner_db)
        .await
        .ok();
}

#[tokio::test]
async fn put_referring_doctor_with_both_provider_and_free_name_returns_422() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let (user_id, account_id) = create_patient_account(&owner_db).await;
    let provider_id = create_listed_provider(&owner_db).await;

    let state = test_state(app_pool().await);

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/referring-doctor")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "provider_id": provider_id,
                        "free_name": "Dr Martin"
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&owner_db)
        .await
        .ok();
}

// ── provider_id + free_phone/free_address (sans free_name) : exclusivité (#3798) ─
//
// La garde provider_id.is_some() == free_name.is_some() ne compare que ces deux
// champs : provider_id + free_phone/free_address sans free_name la contourne.
// Le backend doit ignorer free_phone/free_address quand provider_id est fourni,
// pas les stocker à côté d'une référence provider.

#[tokio::test]
async fn put_referring_doctor_with_provider_id_and_free_phone_ignores_free_phone() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let (user_id, account_id) = create_patient_account(&owner_db).await;
    let provider_id = create_listed_provider(&owner_db).await;

    let state = test_state(app_pool().await);

    let put_response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/referring-doctor")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "provider_id": provider_id,
                        "free_phone": "+33612345678",
                        "free_address": "12 rue de la Paix, Paris"
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(put_response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(put_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["provider_id"], provider_id.to_string());
    assert!(
        v["free_phone"].is_null(),
        "free_phone ne doit pas être stocké aux côtés d'un provider_id"
    );
    assert!(
        v["free_address"].is_null(),
        "free_address ne doit pas être stocké aux côtés d'un provider_id"
    );

    let get_response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/referring-doctor")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(get_response.status(), StatusCode::OK);
    let get_body = axum::body::to_bytes(get_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let gv: serde_json::Value = serde_json::from_slice(&get_body).unwrap();
    assert!(gv["free_phone"].is_null());
    assert!(gv["free_address"].is_null());

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&owner_db)
        .await
        .ok();
}

// ── provider_id inconnu → 404 ─────────────────────────────────────────────────

#[tokio::test]
async fn put_referring_doctor_with_unknown_provider_id_returns_404() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let (user_id, account_id) = create_patient_account(&owner_db).await;

    let state = test_state(app_pool().await);

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/referring-doctor")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({"provider_id": Uuid::new_v4()})).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&owner_db)
        .await
        .ok();
}

// ── Sans JWT → 401 ────────────────────────────────────────────────────────────

#[tokio::test]
async fn put_referring_doctor_no_jwt_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = test_state(db);

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri("/v1/account/referring-doctor")
                .header("Content-Type", "application/json")
                .body(Body::from(r#"{"free_name":"Dr Martin"}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}
