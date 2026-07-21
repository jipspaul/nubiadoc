//! Tests d'intégration : `GET /v1/cabinet/patients/:id` expose `guardians`/
//! `dependents` (#4091).
//!
//! Couvre le critère d'acceptation de l'issue : présence du champ pour un
//! patient mineur rattaché à un tuteur.
//!
//! Token `role: "admin"` : bypass volontaire des gardes de scope
//! secrétariat/relation de soin de `get_cabinet_patient` — hors-sujet ici,
//! même choix que `cabinet_patient_balance.rs` (#4044).

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

const JWT_SECRET: &str = "test-secret-patient-guardianship";

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

fn make_admin_token(sub: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": "admin",
            "exp": exp,
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    admin_user_id: Uuid,
    dependent_app_user_id: Uuid,
    guardian_app_user_id: Uuid,
    dependent_account_id: Uuid,
    guardian_account_id: Uuid,
    /// Patient CABINET rattaché au compte plateforme dépendant (le mineur).
    cabinet_patient_id: Uuid,
}

/// Cabinet + admin + patient cabinet rattaché à un compte plateforme
/// "dépendant" (mineur), lui-même sous tutelle d'un compte "tuteur".
async fn insert_fixture(db: &PgPool, suffix: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let admin_user_id = Uuid::new_v4();
    let dependent_app_user_id = Uuid::new_v4();
    let guardian_app_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let cabinet_patient_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(admin_user_id)
    .bind(format!("guardianship-admin-{suffix}@nubia.test"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_app_user_id)
    .bind(format!("guardianship-dependent-{suffix}@nubia.test"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_app_user_id)
    .bind(format!("guardianship-guardian-{suffix}@nubia.test"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name, birth_date) \
         VALUES ($1, $2, 'Léa', 'Mineure', '2018-01-01')",
    )
    .bind(dependent_account_id)
    .bind(dependent_app_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Paul', 'Tuteur')",
    )
    .bind(guardian_account_id)
    .bind(guardian_app_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO account_guardianship \
         (guardian_account_id, dependent_account_id, relationship, active) \
         VALUES ($1, $2, 'parent', true)",
    )
    .bind(guardian_account_id)
    .bind(dependent_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet PatientGuardianship {suffix}"))
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
        admin_user_id,
        dependent_app_user_id,
        guardian_app_user_id,
        dependent_account_id,
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
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.cabinet_patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();

    sqlx::query("DELETE FROM account_guardianship WHERE dependent_account_id = $1")
        .bind(f.dependent_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.dependent_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.guardian_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.admin_user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.dependent_app_user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.guardian_app_user_id)
        .execute(db)
        .await
        .ok();
}

async fn get_patient(server: axum::Router, patient_id: Uuid, token: &str) -> serde_json::Value {
    let response = server
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", patient_id))
                .header("Authorization", format!("Bearer {}", token))
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

/// Spec exacte de l'issue : patient mineur rattaché à un tuteur → `guardians`
/// contient le tuteur.
#[tokio::test]
async fn guardians_field_present_for_minor_with_guardian() {
    if !db_available() {
        return;
    }
    let seed_db = owner_pool().await;
    let app_db = app_pool().await;
    let f = insert_fixture(&seed_db, &Uuid::new_v4().to_string()).await;

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_admin_token(Uuid::new_v4(), f.cabinet_id);
    let body = get_patient(app(state), f.cabinet_patient_id, &token).await;

    let guardians = body["guardians"].as_array().expect("guardians: {body}");
    assert_eq!(guardians.len(), 1, "body: {body}");
    assert_eq!(guardians[0]["first_name"], "Paul");
    assert_eq!(guardians[0]["last_name"], "Tuteur");
    assert_eq!(guardians[0]["relationship"], "parent");
    assert_eq!(
        guardians[0]["account_id"],
        f.guardian_account_id.to_string()
    );

    let dependents = body["dependents"].as_array().expect("dependents: {body}");
    assert!(
        dependents.is_empty(),
        "le mineur n'est le tuteur de personne : {body}"
    );

    cleanup(&seed_db, &f).await;
}

/// Non-régression : patient sans compte plateforme lié → tableaux vides,
/// pas d'erreur.
#[tokio::test]
async fn guardians_and_dependents_empty_without_linked_account() {
    if !db_available() {
        return;
    }
    let seed_db = owner_pool().await;
    let app_db = app_pool().await;

    let cabinet_id = Uuid::new_v4();
    let admin_user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    {
        let mut tx = seed_db.begin().await.unwrap();
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) \
             VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(admin_user_id)
        .bind(format!("guardianship-nolinked-{admin_user_id}@nubia.test"))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet PatientGuardianship NoLinked {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
             VALUES ($1, $2, 'Sans', 'Compte')",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_db.clone(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_admin_token(Uuid::new_v4(), cabinet_id);
    let body = get_patient(app(state), patient_id, &token).await;

    assert_eq!(body["guardians"], json!([]), "body: {body}");
    assert_eq!(body["dependents"], json!([]), "body: {body}");

    let mut tx = seed_db.begin().await.unwrap();
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(admin_user_id)
        .execute(&seed_db)
        .await
        .ok();
}
