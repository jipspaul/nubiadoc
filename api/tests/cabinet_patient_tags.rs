//! Tests d'intégration : CRUD `/v1/cabinet/patients/:id/tags` (#4040).
//!
//! Couvre les critères d'acceptation de l'issue : 201 (POST), 200 (GET),
//! 204 (DELETE), et l'autorisation RBAC — un token secretary peut gérer
//! les étiquettes (administratif, pas clinique), un token patient est rejeté.

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

const JWT_SECRET: &str = "test-secret-patient-tags";

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

async fn seed_pool() -> PgPool {
    let url = std::env::var("SEED_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_seed@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

fn make_token(
    sub: Uuid,
    cabinet_id: Uuid,
    kind: &str,
    role: &str,
    secretariat_id: Option<Uuid>,
) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": kind,
            "cabinet_id": cabinet_id,
            "role": role,
            "secretariat_id": secretariat_id,
            "exp": exp,
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère cabinet + secrétaire + patient. Retourne `(cabinet_id, secretary_user_id, patient_id)`.
async fn insert_fixture(db: &PgPool, suffix: &str) -> (Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let secretary_user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(secretary_user_id)
    .bind(format!("patient-tags-secretary-{suffix}@nubia.test"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet PatientTags {suffix}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Marc', 'Tags')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (cabinet_id, secretary_user_id, patient_id)
}

/// Rattache le patient au périmètre d'un secrétariat (R10, #3821) en créant la
/// chaîne practitioner, provider, secretariat, provider_secretariat(active) et un
/// appointment non annulé liant le patient au praticien. Sans ce rattachement,
/// `ensure_secretary_scope` masque le patient en 404. Retourne le `secretariat_id`
/// à porter dans le JWT du secrétaire.
async fn scope_patient_to_secretariat(db: &PgPool, cabinet_id: Uuid, patient_id: Uuid) -> Uuid {
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let secretariat_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("patient-tags-prac+{prac_user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
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
        "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, is_listed, rpps_verified) \
         VALUES ($1, $2, $3, $4, 'Dr. Tags Test', true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec Tags Test')")
        .bind(secretariat_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO provider_secretariat (provider_id, secretariat_id, active) \
         VALUES ($1, $2, true)",
    )
    .bind(provider_id)
    .bind(secretariat_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, now() + interval '1 day', now() + interval '1 day 1 hour', 'confirmed')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    secretariat_id
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, secretary_user_id: Uuid, patient_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_tag WHERE patient_id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    // Scope secrétariat posé par `scope_patient_to_secretariat` (no-op pour les
    // tests qui ne l'appellent pas). Ordre FK : appointment → provider_secretariat
    // → secretariat → provider → practitioner, avant patient/cabinet.
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query(
        "DELETE FROM provider_secretariat WHERE provider_id IN \
         (SELECT id FROM provider WHERE cabinet_id = $1)",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .ok();
    sqlx::query("DELETE FROM secretariat WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    let prac_user_id: Option<Uuid> =
        sqlx::query_scalar("SELECT user_id FROM practitioner WHERE cabinet_id = $1 LIMIT 1")
            .bind(cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .ok()
            .flatten();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
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

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(secretary_user_id)
        .execute(db)
        .await
        .ok();
    if let Some(prac_user_id) = prac_user_id {
        sqlx::query("DELETE FROM app_user WHERE id = $1")
            .bind(prac_user_id)
            .execute(db)
            .await
            .ok();
    }
}

fn test_state(app_db: PgPool) -> AppState {
    AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

/// Cycle complet : POST 201 → GET 200 (contient l'étiquette) → DELETE 204 →
/// GET 200 (liste à nouveau vide). RBAC : token secretary autorisé de bout en bout.
#[tokio::test]
async fn secretary_can_create_list_and_delete_tag() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, secretary_user_id, patient_id) =
        insert_fixture(&seed_db, &Uuid::new_v4().to_string()).await;
    let secretariat_id = scope_patient_to_secretariat(&seed_db, cabinet_id, patient_id).await;
    // `sub` = l'app_user secrétaire réellement inséré par le fixture : `created_by`
    // sur patient_tag/audit_log référence app_user(id) (un Uuid aléatoire → 500 FK).
    let token = make_token(
        secretary_user_id,
        cabinet_id,
        "pro",
        "secretary",
        Some(secretariat_id),
    );

    // POST → 201.
    let response = app(test_state(app_db.clone()))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/tags", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({"label": "Paie en retard", "color": "#F59E0B"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let created: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(created["label"], "Paie en retard");
    let tag_id = created["id"].as_str().unwrap().to_string();

    // GET → 200, contient l'étiquette créée.
    let response = app(test_state(app_db.clone()))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/tags", patient_id))
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
    let listed: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(listed["data"].as_array().unwrap().len(), 1);

    // DELETE → 204.
    let response = app(test_state(app_db.clone()))
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!(
                    "/v1/cabinet/patients/{}/tags/{}",
                    patient_id, tag_id
                ))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    // GET → 200, liste à nouveau vide.
    let response = app(test_state(app_db.clone()))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/tags", patient_id))
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
    let listed: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(listed["data"].as_array().unwrap().len(), 0);

    cleanup(&seed_db, cabinet_id, secretary_user_id, patient_id).await;
}

/// RBAC : un token `kind:"patient"` est rejeté (403), même sur une route
/// `/cabinet/...` — `ProSecretaryPlusClaims` exige `kind:"pro"`.
#[tokio::test]
async fn patient_token_is_forbidden() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, secretary_user_id, patient_id) =
        insert_fixture(&seed_db, &Uuid::new_v4().to_string()).await;
    let token = make_token(Uuid::new_v4(), cabinet_id, "patient", "patient", None);

    let response = app(test_state(app_db))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/tags", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup(&seed_db, cabinet_id, secretary_user_id, patient_id).await;
}

/// `label` vide (après trim) → 422.
#[tokio::test]
async fn blank_label_is_rejected() {
    if !db_available() {
        return;
    }
    let seed_db = seed_pool().await;
    let app_db = app_pool().await;
    let (cabinet_id, secretary_user_id, patient_id) =
        insert_fixture(&seed_db, &Uuid::new_v4().to_string()).await;
    let token = make_token(Uuid::new_v4(), cabinet_id, "pro", "secretary", None);

    let response = app(test_state(app_db))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/tags", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("content-type", "application/json")
                .body(Body::from(json!({"label": "   "}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&seed_db, cabinet_id, secretary_user_id, patient_id).await;
}
