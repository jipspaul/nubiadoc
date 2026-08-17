//! Tests d'intégration : GET /v1/implant-passport/export

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

use nubia_api::{app, app_with_dispatcher, AppState, StorageSigner, StubJobDispatcher, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-implant-passport-export";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": cabinet_id, "role": "admin",
                "account_id": Uuid::nil(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_app_state() -> AppState {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

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

/// Insère un compte patient + cabinet + patient + implant, retourne
/// `(user_id, account_id, implant_id)`.
async fn seed_patient_with_implant(db: &PgPool, suffix: &str) -> (Uuid, Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let implant_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("ip-export-{}+{}@nubia.test", suffix, user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'Implant')",
    )
    .bind(account_id)
    .bind(user_id)
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
        .bind(format!("Cabinet IP Export Test {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Bob', 'Implant', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO implant_passport \
         (id, cabinet_id, patient_id, implant_ref, brand, lot_number, placement_date, \
          tooth_position, notes) \
         VALUES ($1, $2, $3, 'REF-T5334', 'Straumann', 'LOT-T5334', '2025-01-10', '36', \
                 'Pose nominale')",
    )
    .bind(implant_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (user_id, account_id, implant_id)
}

// ── Test 1 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn implant_passport_export_no_jwt_returns_401() {
    let response = app(make_app_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/implant-passport/export")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 2 : token pro → 403 ──────────────────────────────────────────────────

#[tokio::test]
async fn implant_passport_export_pro_token_returns_403() {
    let token = make_pro_jwt(Uuid::new_v4(), Uuid::new_v4());

    let response = app(make_app_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/implant-passport/export")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 3 : happy path — patient valide → 302 avec Location ─────────────────

#[tokio::test]
async fn implant_passport_export_patient_returns_302_with_location() {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let token = make_patient_jwt(user_id, account_id);

    let response = app(make_app_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/implant-passport/export")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FOUND);

    let location = response
        .headers()
        .get("location")
        .expect("header Location absent")
        .to_str()
        .unwrap();

    // Le StubStorageSigner génère une URL contenant la clé de stockage du compte.
    assert!(
        location.contains(&account_id.to_string()),
        "Location doit contenir l'account_id : {location}"
    );
}

// ── Test 4 : edge case — Cache-Control: no-store présent ─────────────────────

#[tokio::test]
async fn implant_passport_export_response_has_no_store_cache_control() {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let token = make_patient_jwt(user_id, account_id);

    let response = app(make_app_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/implant-passport/export")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FOUND);

    let cache_control = response
        .headers()
        .get("cache-control")
        .expect("header Cache-Control absent")
        .to_str()
        .unwrap();

    assert_eq!(cache_control, "no-store");
}

// ── Test 5 : signer défaillant → 502 Bad Gateway ───────────────────────────────

/// Signer stub qui retourne toujours `None` (simule un signer non configuré / bucket inaccessible).
struct FailingSigner;

impl StorageSigner for FailingSigner {
    fn sign(&self, _storage_key: &str) -> Option<String> {
        None
    }
}

#[tokio::test]
async fn implant_passport_export_failing_signer_returns_502() {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let token = make_patient_jwt(user_id, account_id);

    let response = app_with_dispatcher(
        make_app_state(),
        Arc::new(StubJobDispatcher),
        Arc::new(FailingSigner),
    )
    .oneshot(
        Request::builder()
            .method("GET")
            .uri("/v1/implant-passport/export")
            .header("Authorization", format!("Bearer {}", token))
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::BAD_GATEWAY,
        "signer indisponible (lien jamais généré) doit retourner 502 upstream_unavailable, pas 410 link_expired"
    );
}

// ── Test 6 : #5334 — implant_id du compte → 302 avec Location scopée ─────────

#[tokio::test]
async fn implant_passport_export_with_own_implant_id_returns_302() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (user_id, account_id, implant_id) =
        seed_patient_with_implant(&owner, "own").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/implant-passport/export?implant_id={implant_id}"))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FOUND);

    let location = response
        .headers()
        .get("location")
        .expect("header Location absent")
        .to_str()
        .unwrap();

    assert!(
        location.contains(&implant_id.to_string()),
        "Location doit être scopée à l'implant demandé : {location}"
    );
}

// ── Test 7 : #5334 — implant_id d'un autre compte → 404 ──────────────────────

#[tokio::test]
async fn implant_passport_export_with_foreign_implant_id_returns_404() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let (_other_user_id, _other_account_id, foreign_implant_id) =
        seed_patient_with_implant(&owner, "foreign").await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/implant-passport/export?implant_id={foreign_implant_id}"
                ))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "un implant hors compte ne doit jamais être exportable, même via implant_id"
    );
}
