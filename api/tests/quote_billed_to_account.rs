//! Tests d'intégration : facturation d'un devis au responsable légal (#4098).
//!
//! Spec exacte de l'issue : un devis pour un patient rattaché à un compte
//! `dependent_account_id` apparaît dans `GET /v1/quotes` du tuteur quand
//! `billed_to_account_id` est renseigné (résolu à la création via
//! `account_guardianship`).

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

const JWT_SECRET: &str = "test-jwt-secret-quote-billed-to-account";

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

struct Fixture {
    cabinet_id: Uuid,
    practitioner_user_id: Uuid,
    dependent_user_id: Uuid,
    guardian_user_id: Uuid,
    guardian_account_id: Uuid,
    cabinet_patient_id: Uuid,
}

/// Cabinet + praticien + patient cabinet rattaché à un compte "dépendant"
/// lui-même sous tutelle d'un compte "responsable légal".
async fn insert_fixture(db: &PgPool, tag: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let practitioner_user_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();
    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let cabinet_patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(practitioner_user_id)
    .bind(format!("quote-billed-prat-{tag}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_user_id)
    .bind(format!("quote-billed-dependent-{tag}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_user_id)
    .bind(format!("quote-billed-guardian-{tag}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Léa', 'Mineure')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Paul', 'Tuteur')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO account_guardianship \
         (guardian_account_id, dependent_account_id, relationship, active) \
         VALUES ($1, $2, 'parent', true)",
    )
    .bind(guardian_account_id)
    .bind(dependent_account_id)
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet QuoteBilledTo {tag}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(practitioner_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Léa', 'Mineure', $3)",
    )
    .bind(cabinet_patient_id)
    .bind(cabinet_id)
    .bind(dependent_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        practitioner_user_id,
        dependent_user_id,
        guardian_user_id,
        guardian_account_id,
        cabinet_patient_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.cabinet_patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();

    sqlx::query("DELETE FROM account_guardianship WHERE guardian_account_id = $1")
        .bind(f.guardian_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE app_user_id IN ($1, $2)")
        .bind(f.dependent_user_id)
        .bind(f.guardian_user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id IN ($1, $2, $3)")
        .bind(f.practitioner_user_id)
        .bind(f.dependent_user_id)
        .bind(f.guardian_user_id)
        .execute(db)
        .await
        .ok();
}

/// Spec exacte de l'issue : un devis pour un patient rattaché à un compte
/// dépendant apparaît dans GET /v1/quotes du tuteur, billed_to_account_id
/// résolu automatiquement à la création.
#[tokio::test]
async fn quote_for_dependent_appears_in_guardian_quotes_list() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, &Uuid::new_v4().to_string()).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // POST /v1/cabinet/quotes — billed_to_account_id résolu via account_guardianship.
    let create_response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/quotes")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(f.practitioner_user_id, f.cabinet_id, "practitioner")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "patient_id": f.cabinet_patient_id,
                        "items": [{"label": "Consultation", "amount_cents": 5000}]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(create_response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(create_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let created: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let quote_id = created["quote_id"].as_str().unwrap().to_string();

    let billed_to: Uuid =
        sqlx::query_scalar("SELECT billed_to_account_id FROM quote WHERE id = $1::uuid")
            .bind(&quote_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(
        billed_to, f.guardian_account_id,
        "billed_to_account_id doit être résolu au tuteur actif"
    );

    // draft → sent (quote_patient_read exclut les brouillons, #3487).
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query("UPDATE quote SET status = 'sent' WHERE id = $1::uuid")
            .bind(&quote_id)
            .execute(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
    }

    // GET /v1/quotes en tant que tuteur.
    let list_response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/quotes")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_patient_jwt(f.guardian_user_id, f.guardian_account_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(list_response.status(), StatusCode::OK);
    let list_bytes = axum::body::to_bytes(list_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let list_body: serde_json::Value = serde_json::from_slice(&list_bytes).unwrap();
    let quotes = list_body["data"].as_array().unwrap();
    assert!(
        quotes.iter().any(|q| q["id"] == quote_id),
        "le devis du dépendant doit apparaître dans GET /v1/quotes du tuteur : {list_body}"
    );

    cleanup(&db, &f).await;
}
