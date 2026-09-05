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

/// Régression #6507 : `GET /v1/account/prescriptions` ne renvoyait qu'une
/// coquille (id/status/document_id/dates), et `GET
/// /v1/account/prescriptions/{id}` n'existait pas (404 routeur). Le patient
/// doit pouvoir lire les lignes (libellé/posologie/durée) et le prescripteur
/// d'une ordonnance signée qui lui appartient — brouillon ou ordonnance
/// d'un autre compte restent invisibles (mêmes bornes que la liste).
#[tokio::test]
async fn reads_own_signed_prescription_detail_with_items() {
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
        .bind(format!("apd-{}@nubia.test", id))
        .bind(kind)
        .execute(&db)
        .await
        .unwrap();
    }
    for (account, owner) in [(account_id, user_id), (other_account, Uuid::new_v4())] {
        if account == other_account {
            sqlx::query(
                "INSERT INTO app_user (id, email, password_hash, kind) \
                 VALUES ($1, $2, 'hash', 'patient')",
            )
            .bind(owner)
            .bind(format!("apd2-{}@nubia.test", owner))
            .execute(&db)
            .await
            .unwrap();
        }
        sqlx::query(
            "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
             VALUES ($1, $2, 'P', 'A')",
        )
        .bind(account)
        .bind(owner)
        .execute(&db)
        .await
        .unwrap();
    }
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet APD')")
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
    sqlx::query(
        "INSERT INTO provider (cabinet_id, practitioner_id, user_id, display_name, is_listed, \
                                rpps_verified) \
         VALUES ($1, $2, $3, 'Dr Hugo Marin', true, true)",
    )
    .bind(cabinet_id)
    .bind(practitioner_id)
    .bind(pro_user_id)
    .execute(&db)
    .await
    .unwrap();

    let mut patient_ids = std::collections::HashMap::new();
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
        patient_ids.insert(account, patient_id);
    }

    let signed_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, \
                                    signed_at) \
         VALUES ($1, $2, $3, $4, 'signed', now())",
    )
    .bind(signed_id)
    .bind(cabinet_id)
    .bind(patient_ids[&account_id])
    .bind(practitioner_id)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO prescription_item (cabinet_id, prescription_id, label, posology, duration) \
         VALUES ($1, $2, 'Amoxicilline 500mg', '1 gelule 3x/jour', '7 jours')",
    )
    .bind(cabinet_id)
    .bind(signed_id)
    .execute(&db)
    .await
    .unwrap();

    let draft_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status) \
         VALUES ($1, $2, $3, $4, 'draft')",
    )
    .bind(draft_id)
    .bind(cabinet_id)
    .bind(patient_ids[&account_id])
    .bind(practitioner_id)
    .execute(&db)
    .await
    .unwrap();

    let others_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, \
                                    signed_at) \
         VALUES ($1, $2, $3, $4, 'signed', now())",
    )
    .bind(others_id)
    .bind(cabinet_id)
    .bind(patient_ids[&other_account])
    .bind(practitioner_id)
    .execute(&db)
    .await
    .unwrap();

    let pool = app_pool().await;
    let token = patient_jwt(user_id, account_id);

    async fn get(pool: &PgPool, token: &str, id: Uuid) -> axum::response::Response {
        app(AppState {
            db: pool.clone(),
            jwt_secret: JWT_SECRET.to_string(),
            mailer: Arc::new(StubMailer),
        })
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/account/prescriptions/{id}"))
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap()
    }

    let response = get(&pool, &token, signed_id).await;
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["id"], json!(signed_id));
    assert_eq!(v["status"], "signed");
    assert_eq!(v["prescriber_name"], "Dr Hugo Marin");
    assert_eq!(v["prescriber_practice"], "Cabinet APD");
    let items = v["items"].as_array().unwrap();
    assert_eq!(items.len(), 1, "items : {v}");
    assert_eq!(items[0]["label"], "Amoxicilline 500mg");
    assert_eq!(items[0]["posology"], "1 gelule 3x/jour");
    assert_eq!(items[0]["duration"], "7 jours");

    let response = get(&pool, &token, draft_id).await;
    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "un brouillon n'est jamais opposable"
    );

    let response = get(&pool, &token, others_id).await;
    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "RLS : ordonnance d'un autre compte invisible"
    );
}
