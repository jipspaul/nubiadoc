//! Tests d'intégration : POST /v1/cabinet/slots — créer un créneau (admin/secrétariat, T2510.c, #2547)

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

const JWT_SECRET: &str = "test-jwt-secret-slots-create-2547";

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
    .bind(format!(
        "slots-create-{}-{}@nubia.test",
        prefix, prac_user_id
    ))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Slots {} {}", prefix, cabinet_id))
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

// ── Test 1 : admin crée un créneau → 201 + payload correct ───────────────────

#[tokio::test]
async fn admin_creates_slot_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "admin").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "admin");

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "practitioner_id": f.prac_id,
                        "starts_at": "2035-06-01T09:00:00Z",
                        "ends_at": "2035-06-01T10:00:00Z",
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["id"].is_string(), "id doit être présent");
    assert_eq!(v["practitioner_id"], f.prac_id.to_string());
    assert_eq!(v["status"], "open");
    assert_eq!(v["online_booking"], false);
    assert!(v["starts_at"].is_string(), "starts_at doit être présent");
    assert!(v["ends_at"].is_string(), "ends_at doit être présent");

    teardown(&db, &f).await;
}

// ── Test 2 : secrétariat crée un créneau → 201 + payload correct ─────────────

#[tokio::test]
async fn secretary_creates_slot_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "secretary").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary");

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "practitioner_id": f.prac_id,
                        "starts_at": "2035-07-01T09:00:00Z",
                        "ends_at": "2035-07-01T10:00:00Z",
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["id"].is_string(), "id doit être présent");
    assert_eq!(v["practitioner_id"], f.prac_id.to_string());
    assert_eq!(v["status"], "open");

    teardown(&db, &f).await;
}

// ── Test 3 : practitioner tente de créer → 403 ───────────────────────────────

#[tokio::test]
async fn practitioner_creates_slot_returns_403() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let token = make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "practitioner");

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "practitioner_id": Uuid::new_v4(),
                        "starts_at": "2035-08-01T09:00:00Z",
                        "ends_at": "2035-08-01T10:00:00Z",
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Régression #3413 : corps invalide → 422 JSON `AppError`, jamais du texte brut ──
//
// Avant le correctif, l'extracteur `Json<CreateSlotBody>` rejetait un corps invalide
// avec un 422 `text/plain` (« Failed to deserialize the JSON body… ») qui cassait le
// front. Le handler doit désormais renvoyer le corps JSON standard.
// Ne nécessite pas de DB : le rejet du corps survient avant tout accès Postgres.
#[tokio::test]
async fn create_slot_invalid_body_returns_json_422() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Token pro valide (admin) mais corps auquel il manque `starts_at`/`ends_at`.
    let token = make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "admin");

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "practitioner_id": Uuid::new_v4(),
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or_default()
        .to_string();
    assert!(
        content_type.starts_with("application/json"),
        "le corps d'erreur doit être JSON, pas du texte brut (content-type = {content_type})"
    );

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value =
        serde_json::from_slice(&bytes).expect("le corps 422 doit être du JSON valide");
    assert_eq!(v["code"], "validation_error");
}

// ── Test 4 : overlap EXCLUDE → 409 slot_taken ────────────────────────────────

#[tokio::test]
async fn create_slot_overlap_returns_409_slot_taken() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "overlap").await;

    let make_state = || AppState {
        db: PgPool::connect_lazy(
            &std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
        )
        .unwrap(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "admin");

    // Premier créneau → 201.
    let r1 = app(make_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "practitioner_id": f.prac_id,
                        "starts_at": "2035-09-01T09:00:00Z",
                        "ends_at": "2035-09-01T10:00:00Z",
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        r1.status(),
        StatusCode::CREATED,
        "premier créneau doit être 201"
    );

    // Créneau chevauchant → EXCLUDE violation → 409 slot_taken.
    let r2 = app(make_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "practitioner_id": f.prac_id,
                        "starts_at": "2035-09-01T09:30:00Z",
                        "ends_at": "2035-09-01T10:30:00Z",
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        r2.status(),
        StatusCode::CONFLICT,
        "chevauchement doit retourner 409"
    );

    let bytes = axum::body::to_bytes(r2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "slot_taken", "code doit être slot_taken (23P01)");

    teardown(&db, &f).await;
}

// ── Test 6 : starts_at dans le passé → 422 (#3808) ───────────────────────────

#[tokio::test]
async fn create_slot_past_starts_at_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "past").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "admin");

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/slots")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "practitioner_id": f.prac_id,
                        "starts_at": "2019-01-01T09:00:00Z",
                        "ends_at": "2019-01-01T10:00:00Z",
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::UNPROCESSABLE_ENTITY,
        "créneau daté dans le passé doit être rejeté (422)"
    );

    teardown(&db, &f).await;
}
