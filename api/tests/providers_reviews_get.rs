//! Tests d'intégration : GET /v1/providers/:id/reviews
//!
//! Couvre :
//! - 200 avec données conformes (happy path, avis publiés).
//! - 400/422 si UUID du chemin invalide.
//! - 200 + liste vide si provider inconnu (le handler ne 404 pas).
//! - Seuls les avis `published` sont exposés (avis `pending` masqués).
//! - Route publique : 200 sans Authorization header.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

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

// ── Fixture ──────────────────────────────────────────────────────────────────

struct Fixture {
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    patient_user_id: Uuid,
    patient_account_id: Uuid,
    patient_id: Uuid,
    /// Premier RDV (pour le premier avis).
    appointment_id: Uuid,
    /// Deuxième RDV (pour un second avis quand nécessaire).
    appointment2_id: Uuid,
    /// ID explicite du provider — utilisé dans l'URL et les INSERT review.
    provider_id: Uuid,
}

async fn setup_fixture(db: &PgPool, tag: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appointment_id = Uuid::new_v4();
    let appointment2_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("revget-pat+{}@nubia.test", patient_user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Dupont')",
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
    .bind(format!("revget-prac+{}@nubia.test", prac_user_id))
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
        .bind(format!("Cabinet RevGet {} {}", tag, cabinet_id))
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

        // provider avec id explicite pour pouvoir construire l'URL de test.
        sqlx::query(
            "INSERT INTO provider \
             (id, cabinet_id, practitioner_id, user_id, display_name, is_listed, rpps_verified) \
             VALUES ($1, $2, $3, $4, $5, true, true)",
        )
        .bind(provider_id)
        .bind(cabinet_id)
        .bind(prac_id)
        .bind(prac_user_id)
        .bind(format!("Dr RevGet {}", tag))
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'Alice', 'Dupont', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(patient_account_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO appointment \
             (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
             VALUES ($1, $2, $3, $4, \
                     now() - interval '7 days', now() - interval '7 days' + interval '1 hour', \
                     'done')",
        )
        .bind(appointment_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO appointment \
             (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
             VALUES ($1, $2, $3, $4, \
                     now() - interval '14 days', now() - interval '14 days' + interval '1 hour', \
                     'done')",
        )
        .bind(appointment2_id)
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
        appointment2_id,
        provider_id,
    }
}

/// Insère un avis directement en base (court-circuit le POST /v1/reviews).
async fn insert_review(
    db: &PgPool,
    provider_id: Uuid,
    patient_account_id: Uuid,
    appointment_id: Uuid,
    rating: i32,
    status: &str,
) {
    sqlx::query(
        "INSERT INTO review \
         (provider_id, patient_account_id, appointment_id, rating, \
          status, author_display, idempotency_key) \
         VALUES ($1, $2, $3, $4, $5, 'Alice D.', $6)",
    )
    .bind(provider_id)
    .bind(patient_account_id)
    .bind(appointment_id)
    .bind(rating)
    .bind(status)
    .bind(Uuid::new_v4().to_string())
    .execute(db)
    .await
    .unwrap();
}

async fn cleanup_fixture(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    // reviews d'abord (FK sur appointment)
    sqlx::query("DELETE FROM review WHERE appointment_id = $1 OR appointment_id = $2")
        .bind(f.appointment_id)
        .bind(f.appointment2_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1 OR id = $2")
        .bind(f.appointment_id)
        .bind(f.appointment2_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(f.provider_id)
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

// ── Test 1 : happy path — avis publiés → 200 + body conforme ─────────────────

#[tokio::test]
async fn get_provider_reviews_happy_path_returns_200_with_data() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup_fixture(&db, "happy").await;
    insert_review(
        &db,
        f.provider_id,
        f.patient_account_id,
        f.appointment_id,
        5,
        "published",
    )
    .await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/providers/{}/reviews", f.provider_id))
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

    assert!(v["data"].is_array(), "data doit être un tableau");
    let data = v["data"].as_array().unwrap();
    assert_eq!(data.len(), 1, "1 avis publié attendu");

    let item = &data[0];
    assert_eq!(item["rating"].as_i64().unwrap(), 5, "rating=5");
    assert!(item["author_display"].is_string(), "author_display présent");
    assert!(item["created_at"].is_string(), "created_at présent");

    assert_eq!(v["page"]["total"].as_i64().unwrap(), 1, "total=1");
    assert_eq!(v["page"]["page"].as_i64().unwrap(), 1, "page=1 par défaut");
    assert_eq!(
        v["page"]["per_page"].as_i64().unwrap(),
        20,
        "per_page=20 par défaut"
    );

    cleanup_fixture(&db, &f).await;
}

// ── Test 2 : UUID invalide dans le chemin → 400 ou 422 ───────────────────────

#[tokio::test]
async fn get_provider_reviews_invalid_uuid_returns_error() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri("/v1/providers/not-a-uuid/reviews")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    let status = response.status().as_u16();
    assert!(
        status == 400 || status == 422,
        "UUID invalide → 400 ou 422, got {}",
        status
    );
}

// ── Test 3 : provider inconnu → 200 + liste vide (pas de 404) ────────────────

#[tokio::test]
async fn get_provider_reviews_unknown_provider_returns_empty_list() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/providers/{}/reviews", Uuid::new_v4()))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::OK,
        "provider inconnu → 200 (liste vide, pas 404)"
    );

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(
        v["data"].as_array().unwrap().len(),
        0,
        "data vide pour provider inconnu"
    );
    assert_eq!(v["page"]["total"].as_i64().unwrap(), 0, "total=0");
}

// ── Test 4 (edge) : avis `pending` non exposés, seul `published` sort ────────

#[tokio::test]
async fn get_provider_reviews_pending_reviews_not_exposed() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup_fixture(&db, "pending").await;

    // 1 avis publié + 1 avis en attente de modération.
    insert_review(
        &db,
        f.provider_id,
        f.patient_account_id,
        f.appointment_id,
        5,
        "published",
    )
    .await;
    insert_review(
        &db,
        f.provider_id,
        f.patient_account_id,
        f.appointment2_id,
        2,
        "pending",
    )
    .await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/providers/{}/reviews", f.provider_id))
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

    assert_eq!(
        v["data"].as_array().unwrap().len(),
        1,
        "seul l'avis published doit apparaître (pending masqué)"
    );
    assert_eq!(
        v["data"][0]["rating"].as_i64().unwrap(),
        5,
        "c'est bien l'avis published (rating=5) qui sort"
    );
    assert_eq!(v["page"]["total"].as_i64().unwrap(), 1, "total=1");

    cleanup_fixture(&db, &f).await;
}

// ── Test 5 (edge) : route publique — 200 sans Authorization header ────────────

#[tokio::test]
async fn get_provider_reviews_no_jwt_is_public() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup_fixture(&db, "public").await;
    insert_review(
        &db,
        f.provider_id,
        f.patient_account_id,
        f.appointment_id,
        4,
        "published",
    )
    .await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    // Aucun header Authorization — la route doit être accessible sans JWT.
    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/providers/{}/reviews", f.provider_id))
                // pas de header Authorization
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::OK,
        "route publique → 200 sans JWT"
    );

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(
        v["data"].as_array().unwrap().len(),
        1,
        "1 avis visible sans JWT"
    );

    cleanup_fixture(&db, &f).await;
}
