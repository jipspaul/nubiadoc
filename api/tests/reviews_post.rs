//! Tests d'intégration : POST /v1/reviews
//!
//! Couvre :
//! - 201 patient ayant consulté (RDV status "done").
//! - 404 patient jamais consulté (appointment_id invalide ou n'appartient pas au patient).
//! - 409 review_already_exists (même appointment_id soumis deux fois).

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

const JWT_SECRET: &str = "test-jwt-secret-reviews-post";

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

/// Crée le jeu de fixtures complet (cabinet + praticien + provider + patient + appointment done).
/// Retourne les IDs utiles. Cleanup doit être appelé en fin de test.
struct Fixture {
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    patient_user_id: Uuid,
    patient_account_id: Uuid,
    patient_id: Uuid,
    appointment_id: Uuid,
}

async fn setup_fixture(db: &PgPool, tag: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appointment_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("review-pat-{}+{}@nubia.test", tag, patient_user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Test')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("review-prac-{}+{}@nubia.test", tag, prac_user_id))
    .execute(db)
    .await
    .unwrap();

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet Review {} {}", tag, cabinet_id))
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
            "INSERT INTO provider (cabinet_id, practitioner_id, user_id, display_name, is_listed, rpps_verified) \
             VALUES ($1, $2, $3, 'Dr. Review', true, true)",
        )
        .bind(cabinet_id)
        .bind(prac_id)
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Alice', 'Test', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(patient_account_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        // RDV passé, statut "done" → éligible à un avis.
        sqlx::query(
            "INSERT INTO appointment \
             (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
             VALUES ($1, $2, $3, $4, \
                     now() - interval '3 days', now() - interval '3 days' + interval '1 hour', \
                     'done')",
        )
        .bind(appointment_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    Fixture {
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_user_id,
        patient_account_id,
        patient_id,
        appointment_id,
    }
}

async fn cleanup_fixture(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM review WHERE appointment_id = $1")
        .bind(f.appointment_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(f.appointment_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE practitioner_id = $1")
        .bind(f.prac_id)
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

    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(f.patient_user_id)
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : patient ayant consulté → 201 { review_id, status:"pending" } ────

#[tokio::test]
async fn post_review_patient_consulted_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup_fixture(&db, "happy").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let idempotency_key = Uuid::new_v4().to_string();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/reviews")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(f.patient_user_id, f.patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .header("Idempotency-Key", &idempotency_key)
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "appointment_id": f.appointment_id,
                        "rating": 5,
                        "comment": "Excellent praticien"
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert!(v["review_id"].is_string(), "review_id doit être présent");
    assert_eq!(v["status"], "pending", "status initial doit être pending");

    cleanup_fixture(&db, &f).await;
}

// ── Test 2 : patient jamais consulté → 404 (appointment inconnu sous sa RLS) ─

#[tokio::test]
async fn post_review_patient_never_consulted_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    // Créer un second patient qui n'a pas de RDV avec ce provider.
    let other_user_id = Uuid::new_v4();
    let other_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(other_user_id)
    .bind(format!("review-other+{}@nubia.test", other_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'Inconnu')",
    )
    .bind(other_account_id)
    .bind(other_user_id)
    .execute(&db)
    .await
    .unwrap();

    // Fixture pour avoir un appointment_id valide (mais appartenant à un autre patient).
    let f = setup_fixture(&db, "noconsult").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Le patient "other" tente de laisser un avis sur l'appointment de "Alice".
    // La RLS (appointment_patient_read) bloque → 404.
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/reviews")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(other_user_id, other_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .header("Idempotency-Key", Uuid::new_v4().to_string())
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "appointment_id": f.appointment_id,
                        "rating": 4
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "appointment d'un autre patient → 404"
    );

    cleanup_fixture(&db, &f).await;
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(other_account_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 3 : review déjà existante → 409 review_already_exists ───────────────

#[tokio::test]
async fn post_review_duplicate_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup_fixture(&db, "dup").await;

    let make_state = || AppState {
        db: PgPool::connect_lazy(
            &std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
        )
        .unwrap(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body_json = serde_json::to_string(&json!({
        "appointment_id": f.appointment_id,
        "rating": 4,
        "comment": "Bien"
    }))
    .unwrap();

    // Premier appel — Idempotency-Key différente pour éviter la branche idempotence.
    let r1 = app(make_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/reviews")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(f.patient_user_id, f.patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .header("Idempotency-Key", Uuid::new_v4().to_string())
                .body(Body::from(body_json.clone()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        r1.status(),
        StatusCode::CREATED,
        "premier avis doit être 201"
    );

    // Deuxième appel — nouvelle Idempotency-Key, même appointment_id → UNIQUE violation.
    let r2 = app(make_state())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/reviews")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(f.patient_user_id, f.patient_account_id)
                    ),
                )
                .header("Content-Type", "application/json")
                .header("Idempotency-Key", Uuid::new_v4().to_string())
                .body(Body::from(body_json))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r2.status(), StatusCode::CONFLICT, "double avis → 409");

    let body2 = axum::body::to_bytes(r2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body2).unwrap();
    assert_eq!(v["code"], "review_already_exists");

    cleanup_fixture(&db, &f).await;
}

// ── Test 4 : token pro → 403 ──────────────────────────────────────────────────

#[tokio::test]
async fn post_review_pro_token_returns_403() {
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

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/reviews")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(Uuid::new_v4(), Uuid::new_v4())),
                )
                .header("Content-Type", "application/json")
                .header("Idempotency-Key", Uuid::new_v4().to_string())
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "appointment_id": Uuid::new_v4(),
                        "rating": 3
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 5 : Idempotency-Key absente → 400 missing_idempotency_key ────────────

#[tokio::test]
async fn post_review_missing_idempotency_key_returns_400() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/reviews")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(user_id, account_id)),
                )
                .header("Content-Type", "application/json")
                // Pas de Idempotency-Key header
                .body(Body::from(
                    serde_json::to_string(&json!({
                        "appointment_id": Uuid::new_v4(),
                        "rating": 3
                    }))
                    .unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["code"], "missing_idempotency_key");
}
