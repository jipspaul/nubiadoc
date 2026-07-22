//! Test d'intégration : POST /v1/cabinet/quotes — amo_part+amc_part > amount_cents (#4309)
//!
//! Fichier dédié : `cabinet_quotes_post.rs` est déjà au plafond de taille
//! (756 lignes > 700, CLAUDE.md), même pattern que
//! `cabinet_patient_documents_upload_guard.rs`.

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-quotes-parts-overflow";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
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
            "role": "practitioner",
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── Test : amo_part_cents + amc_part_cents > amount_cents -> 422 ────────────
//
// Reproduit exactement le repro de l'issue : amount=10000, amo=9000,
// amc=9000 (somme 18000 > 10000) — avant #4309, accepté en 201 avec
// patient_share_cents=-8000 (reste à charge négatif).

#[tokio::test]
async fn create_quote_with_amo_amc_exceeding_amount_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("cq-overflow+{user_id}@nubia.test"))
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
        .bind(format!("Cabinet Overflow Test {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
             VALUES ($1, $2, 'Test', 'Overflow')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
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

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/quotes")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(user_id, cabinet_id)),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "patient_id": patient_id,
                        "items": [{
                            "label": "QA overpart",
                            "amount_cents": 10000,
                            "amo_part_cents": 9000,
                            "amc_part_cents": 9000
                        }]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    // Rien ne doit avoir été inséré (validation avant toute écriture DB).
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM quote WHERE patient_id = $1")
        .bind(patient_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(count, 0, "aucun devis ne doit avoir été créé");

    // Cleanup
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
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
