//! Tests d'intégration : GET /v1/account/prescriptions (lot F7, issue #3319)

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

const JWT_SECRET: &str = "test-jwt-secret-account-prescriptions";

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

fn patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
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

#[tokio::test]
async fn lists_own_prescriptions_only() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let other_account = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let pro_user_id = Uuid::new_v4();

    for (id, kind) in [(user_id, "patient"), (pro_user_id, "pro")] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(id)
        .bind(format!("ap-{}@nubia.test", id))
        .bind(kind)
        .execute(&db)
        .await
        .unwrap();
    }
    for account in [account_id, other_account] {
        let account_user = if account == account_id {
            user_id
        } else {
            let other_user = Uuid::new_v4();
            sqlx::query(
                "INSERT INTO app_user (id, email, password_hash, kind) \
                 VALUES ($1, $2, 'hash', 'patient')",
            )
            .bind(other_user)
            .bind(format!("ap2-{}@nubia.test", other_user))
            .execute(&db)
            .await
            .unwrap();
            other_user
        };
        sqlx::query(
            "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
             VALUES ($1, $2, 'P', 'A')",
        )
        .bind(account)
        .bind(account_user)
        .execute(&db)
        .await
        .unwrap();
    }
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet AP')")
        .bind(cabinet_id)
        .execute(&db)
        .await
        .unwrap();
    let practitioner_id = Uuid::new_v4();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(pro_user_id)
        .execute(&db)
        .await
        .unwrap();

    let mut mine = Uuid::nil();
    for account in [account_id, other_account] {
        let patient_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'P', 'A', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(account)
        .execute(&db)
        .await
        .unwrap();
        let prescription_id = Uuid::new_v4();
        sqlx::query(
            "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, \
                                       signed_at) \
             VALUES ($1, $2, $3, $4, 'signed', now())",
        )
        .bind(prescription_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(practitioner_id)
        .execute(&db)
        .await
        .unwrap();
        if account == account_id {
            mine = prescription_id;
        }
    }

    let response = app(AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        Request::builder()
            .method("GET")
            .uri("/v1/account/prescriptions")
            .header(
                "Authorization",
                format!("Bearer {}", patient_jwt(user_id, account_id)),
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
    assert!(data.iter().any(|p| p["id"] == json!(mine)));
    assert!(
        data.iter().all(|p| p["id"] == json!(mine)),
        "seules MES ordonnances (RLS) : {v}"
    );
    assert_eq!(data[0]["status"], "signed");
}

/// Régression #6381 : `LIMIT 100` en dur, sans pagination, tronquait
/// silencieusement l'historique au-delà de la 100e ligne. Vérifie qu'un
/// curseur (`?limit=2` puis `?limit=2&cursor=...`) permet d'atteindre
/// l'intégralité des ordonnances.
#[tokio::test]
async fn paginates_beyond_limit_via_cursor() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let pro_user_id = Uuid::new_v4();

    for (id, kind) in [(user_id, "patient"), (pro_user_id, "pro")] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(id)
        .bind(format!("pg-{}@nubia.test", id))
        .bind(kind)
        .execute(&db)
        .await
        .unwrap();
    }
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'P', 'A')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet PG')")
        .bind(cabinet_id)
        .execute(&db)
        .await
        .unwrap();
    let practitioner_id = Uuid::new_v4();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(pro_user_id)
        .execute(&db)
        .await
        .unwrap();
    let patient_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'P', 'A', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&db)
    .await
    .unwrap();

    // created_at décroissants : le plus récent en premier (ORDER BY created_at DESC).
    let created_ats = [
        "2025-06-01 12:02:00+00",
        "2025-06-01 12:01:00+00",
        "2025-06-01 12:00:00+00",
    ];
    let mut prescription_ids = Vec::new();
    for created_at in created_ats {
        let prescription_id = Uuid::new_v4();
        sqlx::query(&format!(
            "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, \
                                       signed_at, created_at) \
             VALUES ($1, $2, $3, $4, 'signed', now(), '{created_at}')"
        ))
        .bind(prescription_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(practitioner_id)
        .execute(&db)
        .await
        .unwrap();
        prescription_ids.push(prescription_id);
    }

    let token = patient_jwt(user_id, account_id);
    let pool = app_pool().await;

    async fn fetch(pool: &PgPool, token: &str, uri: &str) -> serde_json::Value {
        let response = app(AppState {
            db: pool.clone(),
            jwt_secret: JWT_SECRET.to_string(),
            mailer: Arc::new(StubMailer),
        })
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(uri)
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        serde_json::from_slice(&bytes).unwrap()
    }

    let page1 = fetch(&pool, &token, "/v1/account/prescriptions?limit=2").await;
    let data1 = page1["data"].as_array().unwrap();
    assert_eq!(data1.len(), 2, "page 1 : {page1}");
    assert_eq!(data1[0]["id"], json!(prescription_ids[0]));
    assert_eq!(data1[1]["id"], json!(prescription_ids[1]));
    let cursor = page1["page"]["next_cursor"]
        .as_str()
        .expect("has_more -> next_cursor présent");

    let page2 = fetch(
        &pool,
        &token,
        &format!("/v1/account/prescriptions?limit=2&cursor={cursor}"),
    )
    .await;
    let data2 = page2["data"].as_array().unwrap();
    assert_eq!(data2.len(), 1, "page 2 : {page2}");
    assert_eq!(data2[0]["id"], json!(prescription_ids[2]));
    assert!(page2["page"]["next_cursor"].is_null());
}
