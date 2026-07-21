//! Tests d'intégration : GET /v1/cabinet/quotes/export.csv (#4154)

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-quotes-export-csv";

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

// ── Test 1 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn cabinet_quotes_export_csv_no_jwt_returns_401() {
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
                .method("GET")
                .uri("/v1/cabinet/quotes/export.csv")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 2 : rôle non-admin (practitioner) → 403 ─────────────────────────────

#[tokio::test]
async fn cabinet_quotes_export_csv_practitioner_returns_403() {
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
                .method("GET")
                .uri("/v1/cabinet/quotes/export.csv")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "practitioner")
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 3 : rôle admin, devis seedés → 200 text/csv, une ligne par devis ───

#[tokio::test]
async fn cabinet_quotes_export_csv_admin_returns_csv_matching_seeded_rows() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_sent = Uuid::new_v4();
    let quote_draft = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("cq-export-csv+{}@nubia.test", user_id))
    .execute(&db)
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
        .bind(format!("Cabinet CQ Export CSV Test {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
             VALUES ($1, $2, 'Bernard', 'Export, Test')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
             VALUES ($1, $2, $3, 'sent', 150.00, 'EUR')",
        )
        .bind(quote_sent)
        .bind(cabinet_id)
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
             VALUES ($1, $2, $3, 'draft', 90.00, 'EUR')",
        )
        .bind(quote_draft)
        .bind(cabinet_id)
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Sans filtre : les 2 devis apparaissent (+ header = 3 lignes).
    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/quotes/export.csv")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(user_id, cabinet_id, "admin")),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response
            .headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok()),
        Some("text/csv; charset=utf-8")
    );

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body = String::from_utf8(bytes.to_vec()).unwrap();
    let lines: Vec<&str> = body.trim_end().split('\n').collect();
    // 1 ligne d'en-tête + 2 devis seedés.
    assert_eq!(
        lines.len(),
        3,
        "en-tête + 2 devis attendus, corps :\n{body}"
    );
    assert_eq!(
        lines[0],
        "id,patient_id,patient_name,status,total_amount_cents,created_at"
    );
    assert!(
        body.contains(&quote_sent.to_string()),
        "le devis sent doit apparaître"
    );
    assert!(
        body.contains(&quote_draft.to_string()),
        "le devis draft doit apparaître"
    );
    // Nom patient contenant une virgule → doit être quoté (RFC 4180).
    assert!(
        body.contains("\"Bernard\"") || body.contains("\"Export, Test Bernard\"") || {
            // trim(concat(first_name, ' ', last_name)) => "Bernard Export, Test"
            body.contains("\"Bernard Export, Test\"")
        },
        "le nom patient contenant une virgule doit être échappé, corps :\n{body}"
    );

    // Avec filtre ?status=sent : un seul devis (+ header = 2 lignes).
    let response2 = app(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/quotes/export.csv?status=sent")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(user_id, cabinet_id, "admin")),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response2.status(), StatusCode::OK);
    let bytes2 = axum::body::to_bytes(response2.into_body(), usize::MAX)
        .await
        .unwrap();
    let body2 = String::from_utf8(bytes2.to_vec()).unwrap();
    let lines2: Vec<&str> = body2.trim_end().split('\n').collect();
    assert_eq!(lines2.len(), 2, "en-tête + 1 devis sent, corps :\n{body2}");
    assert!(body2.contains(&quote_sent.to_string()));
    assert!(!body2.contains(&quote_draft.to_string()));

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM patient WHERE id = $1")
            .bind(patient_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM cabinet WHERE id = $1")
            .bind(cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test : ?status= hors énum → 400 ──────────────────────────────────────────

#[tokio::test]
async fn cabinet_quotes_export_csv_invalid_status_filter_returns_400() {
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
                .method("GET")
                .uri("/v1/cabinet/quotes/export.csv?status=paid")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "admin")
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "invalid_status_filter");
}

// ── Test : ?date_from= non parsable → 422 ────────────────────────────────────

#[tokio::test]
async fn cabinet_quotes_export_csv_invalid_date_returns_422() {
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
                .method("GET")
                .uri("/v1/cabinet/quotes/export.csv?date_from=not-a-date")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), Uuid::new_v4(), "admin")
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}
