//! Tests d'intégration : PATCH /v1/account/dependents/{id}

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

const JWT_SECRET: &str = "test-jwt-secret-dependents-patch";

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

// ── Test 1 : happy path — mise à jour des champs + couverture ─────────────────

#[tokio::test]
async fn dependent_patch_happy_path_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_user_id)
    .bind(format!("guardian-patch+{}@nubia.test", guardian_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Guardian')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_user_id)
    .bind(format!("dependent-patch+{}@nubia.test", dependent_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name, birth_date) \
         VALUES ($1, $2, 'Bob', 'Proche', '2015-03-10')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(&db)
    .await
    .unwrap();

    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'enfant', true)",
        )
        .bind(guardian_account_id)
        .bind(dependent_account_id)
        .execute(&rls_db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(guardian_user_id, guardian_account_id);

    let body = json!({
        "first_name": "Bobby",
        "last_name": "Updated",
        "birth_date": "2016-06-15",
        "relationship": "enfant",
        "coverage": {
            "tiers_payant": true,
            "amc": "MGEN"
        }
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/account/dependents/{}", dependent_account_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    assert_eq!(
        json["dependent_account_id"],
        dependent_account_id.to_string()
    );
    assert_eq!(json["first_name"], "Bobby");
    assert_eq!(json["last_name"], "Updated");
    assert_eq!(json["birth_date"], "2016-06-15");
    assert_eq!(json["relationship"], "enfant");
    assert_eq!(json["coverage"]["amc"], "MGEN");
    assert_eq!(json["coverage"]["tiers_payant"], true);
}

// ── Test 1b : NSS malformé dans coverage → 422 (#4312, parité couverture perso) ──

#[tokio::test]
async fn dependent_patch_invalid_nss_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_user_id)
    .bind(format!(
        "guardian-patch-nss+{}@nubia.test",
        guardian_user_id
    ))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Guardian')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_user_id)
    .bind(format!(
        "dependent-patch-nss+{}@nubia.test",
        dependent_user_id
    ))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name, birth_date) \
         VALUES ($1, $2, 'Bob', 'Proche', '2015-03-10')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(&db)
    .await
    .unwrap();

    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'enfant', true)",
        )
        .bind(guardian_account_id)
        .bind(dependent_account_id)
        .execute(&rls_db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(guardian_user_id, guardian_account_id);

    let body = json!({
        "coverage": {
            "regime_obligatoire": "regime_general",
            "nss": "@@@notdigits@@@"
        }
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/account/dependents/{}", dependent_account_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM patient_coverage WHERE patient_account_id = $1")
            .bind(dependent_account_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(
        count, 0,
        "aucune couverture ne doit être persistée si le NSS est invalide"
    );
}

// ── Test 1c : relationship → adulte (#7009/#7305) : PATCH doit refuser tout
//    comme POST — un enfant ne doit pas devenir conjoint/parent/autre sans
//    passer par POST /v1/account/access-requests ───────────────────────────

#[tokio::test]
async fn dependent_patch_relationship_to_adult_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_user_id)
    .bind(format!("guardian-patch-adult+{}@nubia.test", guardian_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Guardian')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_user_id)
    .bind(format!(
        "dependent-patch-adult+{}@nubia.test",
        dependent_user_id
    ))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name, birth_date) \
         VALUES ($1, $2, 'QA80', 'BypassTest', '2016-03-04')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(&db)
    .await
    .unwrap();

    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'enfant', true)",
        )
        .bind(guardian_account_id)
        .bind(dependent_account_id)
        .execute(&rls_db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(guardian_user_id, guardian_account_id);

    for rel in ["conjoint", "parent", "autre"] {
        let body = json!({"relationship": rel});

        let response = app(state.clone())
            .oneshot(
                Request::builder()
                    .method("PATCH")
                    .uri(format!("/v1/account/dependents/{}", dependent_account_id))
                    .header("Authorization", format!("Bearer {}", token))
                    .header("Content-Type", "application/json")
                    .body(Body::from(serde_json::to_vec(&body).unwrap()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(
            response.status(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "relationship={rel} doit être refusé par PATCH comme par POST"
        );

        let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        assert_eq!(json["code"], "adult_requires_consent");
    }

    let relationship: String = sqlx::query_scalar(
        "SELECT relationship FROM account_guardianship \
         WHERE guardian_account_id = $1 AND dependent_account_id = $2 AND active = true",
    )
    .bind(guardian_account_id)
    .bind(dependent_account_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(
        relationship, "enfant",
        "la relation ne doit pas avoir été modifiée en base"
    );
}

// ── Test 1d : birth_date → majorité (#7009/#7305) : un mineur ne doit pas
//    pouvoir devenir adulte via PATCH ────────────────────────────────────────

#[tokio::test]
async fn dependent_patch_birth_date_to_adult_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_user_id)
    .bind(format!("guardian-patch-age+{}@nubia.test", guardian_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Guardian')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_user_id)
    .bind(format!(
        "dependent-patch-age+{}@nubia.test",
        dependent_user_id
    ))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name, birth_date) \
         VALUES ($1, $2, 'QA80', 'BypassTest', '2016-03-04')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(&db)
    .await
    .unwrap();

    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'enfant', true)",
        )
        .bind(guardian_account_id)
        .bind(dependent_account_id)
        .execute(&rls_db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(guardian_user_id, guardian_account_id);

    let body = json!({"birth_date": "1970-01-01"});

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/account/dependents/{}", dependent_account_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(json["code"], "adult_requires_consent");

    let birth_date: chrono::NaiveDate =
        sqlx::query_scalar("SELECT birth_date FROM patient_account WHERE id = $1")
            .bind(dependent_account_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(
        birth_date,
        "2016-03-04".parse::<chrono::NaiveDate>().unwrap(),
        "la date de naissance ne doit pas avoir été modifiée en base"
    );
}

// ── Test 1e : proche adulte déjà rattaché (#7305 repro étape 7) — la garde
//    s'applique aussi sur relationship déjà != enfant ──────────────────────

#[tokio::test]
async fn dependent_patch_already_adult_relationship_change_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_user_id)
    .bind(format!(
        "guardian-patch-existing-adult+{}@nubia.test",
        guardian_user_id
    ))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Guardian')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_user_id)
    .bind(format!(
        "dependent-patch-existing-adult+{}@nubia.test",
        dependent_user_id
    ))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name, birth_date) \
         VALUES ($1, $2, 'QA16', 'AdulteSansAccord', '1985-04-12')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(&db)
    .await
    .unwrap();

    // Lien préexistant déjà vers un adulte (simule un état legacy antérieur au fix).
    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'conjoint', true)",
        )
        .bind(guardian_account_id)
        .bind(dependent_account_id)
        .execute(&rls_db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(guardian_user_id, guardian_account_id);

    let body = json!({"relationship": "parent"});

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/account/dependents/{}", dependent_account_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 2 : proche hors tutelle → 404 ───────────────────────────────────────

#[tokio::test]
async fn dependent_patch_no_guardianship_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("no-guardian-patch+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Solo', 'Patient')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(user_id, account_id);
    let unknown_id = Uuid::new_v4();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/account/dependents/{}", unknown_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(b"{}".as_ref()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);
}
