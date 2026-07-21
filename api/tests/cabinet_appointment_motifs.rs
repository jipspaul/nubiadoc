//! Tests d'intégration : CRUD `/v1/cabinet/appointment-motifs` (#4085).
//!
//! Couvre les critères d'acceptation de l'issue : 201 à la création (admin),
//! 200 à la liste, 403 pour un rôle secretary sur la création (admin-only).

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

const JWT_SECRET: &str = "test-jwt-secret-appointment-motifs";

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

async fn insert_cabinet(db: &PgPool, tag: &str) -> Uuid {
    let cabinet_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet AppointmentMotifs {tag} {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    cabinet_id
}

async fn cleanup_cabinet(db: &PgPool, cabinet_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment_motif WHERE cabinet_id = $1")
        .bind(cabinet_id)
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

/// Spec de l'issue : 201 à la création (admin).
#[tokio::test]
async fn create_appointment_motif_as_admin_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = insert_cabinet(&db, "create").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointment-motifs")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), cabinet_id, "admin")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"label": "Détartrage", "default_duration_minutes": 30}).to_string(),
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
    assert_eq!(v["label"], "Détartrage");
    assert_eq!(v["default_duration_minutes"], 30);

    cleanup_cabinet(&db, cabinet_id).await;
}

/// Spec de l'issue : 200 à la liste.
#[tokio::test]
async fn list_appointment_motifs_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = insert_cabinet(&db, "list").await;

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO appointment_motif (cabinet_id, label, default_duration_minutes) \
             VALUES ($1, 'Urgence douleur', NULL)",
        )
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
                .method("GET")
                .uri("/v1/cabinet/appointment-motifs")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), cabinet_id, "secretary")
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let data = v["data"].as_array().unwrap();
    assert!(data.iter().any(|m| m["label"] == "Urgence douleur"));

    cleanup_cabinet(&db, cabinet_id).await;
}

/// Spec de l'issue : 403 pour un rôle secretary sur la création (admin-only).
#[tokio::test]
async fn create_appointment_motif_as_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = insert_cabinet(&db, "forbidden").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointment-motifs")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), cabinet_id, "secretary")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"label": "Détartrage"}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup_cabinet(&db, cabinet_id).await;
}

/// Non-régression : label vide → 422.
#[tokio::test]
async fn create_appointment_motif_blank_label_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = insert_cabinet(&db, "blank").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointment-motifs")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), cabinet_id, "admin")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"label": "   "}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_cabinet(&db, cabinet_id).await;
}

/// PATCH + DELETE : cycle complet admin.
#[tokio::test]
async fn patch_then_delete_appointment_motif_as_admin() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let cabinet_id = insert_cabinet(&db, "patchdelete").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let admin_jwt = make_pro_jwt(Uuid::new_v4(), cabinet_id, "admin");

    let create_response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointment-motifs")
                .header("Authorization", format!("Bearer {admin_jwt}"))
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"label": "Consultation"}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(create_response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(create_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let created: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let motif_id = created["id"].as_str().unwrap().to_string();

    let patch_response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/appointment-motifs/{motif_id}"))
                .header("Authorization", format!("Bearer {admin_jwt}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"default_duration_minutes": 20}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(patch_response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(patch_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let patched: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(
        patched["label"], "Consultation",
        "label inchangé (non fourni au PATCH)"
    );
    assert_eq!(patched["default_duration_minutes"], 20);

    let delete_response = app(state)
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/cabinet/appointment-motifs/{motif_id}"))
                .header("Authorization", format!("Bearer {admin_jwt}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(delete_response.status(), StatusCode::NO_CONTENT);

    cleanup_cabinet(&db, cabinet_id).await;
}
