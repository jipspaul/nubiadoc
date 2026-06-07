//! Tests d'intégration : POST /v1/cabinet/prescriptions/{id}/sign

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-prescriptions-sign";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "practitioner".into(),
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "secretary".into(),
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Fixture minimale : cabinet + praticien + patient + prescription en `draft`.
/// Retourne `(cabinet_id, prac_user_id, prac_id, patient_id, prescription_id)`.
async fn insert_prescription_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prescription_id = Uuid::new_v4();

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
    .bind(format!("presc-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Prescription Test', 'dentaire')",
    )
    .bind(cabinet_id)
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'Prescription')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO prescription \
         (id, cabinet_id, patient_id, practitioner_id, status) \
         VALUES ($1, $2, $3, $4, 'draft')",
    )
    .bind(prescription_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (
        cabinet_id,
        prac_user_id,
        prac_id,
        patient_id,
        prescription_id,
    )
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
    prescription_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();

    // Supprime la prescription (et ses références document/signature).
    sqlx::query("UPDATE prescription SET document_id = NULL, signature_id = NULL WHERE id = $1")
        .bind(prescription_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM prescription WHERE id = $1")
        .bind(prescription_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM document WHERE patient_id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM signature WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();

    tx.commit().await.ok();
}

// ── Test 1 : praticien → 200, prescription.status='signed' ───────────────────

#[tokio::test]
async fn prescription_sign_practitioner_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_user_id, prac_id, patient_id, prescription_id) =
        insert_prescription_fixture(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/prescriptions/{}/sign",
                    prescription_id
                ))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert!(v["signed_at"].is_string(), "signed_at doit être une chaîne");
    assert!(
        Uuid::parse_str(v["document_id"].as_str().unwrap_or("")).is_ok(),
        "document_id doit être un UUID valide"
    );

    // Vérifie en base que la prescription est bien passée en 'signed'.
    let row = sqlx::query("SELECT status FROM prescription WHERE id = $1")
        .bind(prescription_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let status: String = sqlx::Row::try_get(&row, "status").unwrap();
    assert_eq!(status, "signed");

    cleanup_fixture(
        &db,
        cabinet_id,
        prac_user_id,
        prac_id,
        patient_id,
        prescription_id,
    )
    .await;
}

// ── Test 2 : ordonnance déjà signée → 409 ─────────────────────────────────────

#[tokio::test]
async fn prescription_sign_already_signed_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_user_id, prac_id, patient_id, prescription_id) =
        insert_prescription_fixture(&db).await;

    // Passe la prescription directement en `signed` en base.
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("UPDATE prescription SET status = 'signed', signed_at = now() WHERE id = $1")
        .bind(prescription_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/prescriptions/{}/sign",
                    prescription_id
                ))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CONFLICT);

    cleanup_fixture(
        &db,
        cabinet_id,
        prac_user_id,
        prac_id,
        patient_id,
        prescription_id,
    )
    .await;
}

// ── Test 3 : token secrétaire → 403 ───────────────────────────────────────────

#[tokio::test]
async fn prescription_sign_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_user_id, prac_id, patient_id, prescription_id) =
        insert_prescription_fixture(&db).await;

    let secretary_id = Uuid::new_v4();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/prescriptions/{}/sign",
                    prescription_id
                ))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_secretary_token(secretary_id, cabinet_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup_fixture(
        &db,
        cabinet_id,
        prac_user_id,
        prac_id,
        patient_id,
        prescription_id,
    )
    .await;
}
