//! Tests d'intégration : `questionnaire_template` (#7159, DP-F21.b)
//! - `GET`/`POST /v1/cabinet/questionnaire-templates`
//! - `PATCH`/`DELETE /v1/cabinet/questionnaire-templates/:id`
//! - `GET /v1/account/medical-questionnaire/active-template`
//! - validation des soumissions (`POST`/`PATCH /v1/account/medical-questionnaire`)
//!   contre le schéma d'un modèle custom.

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

const JWT_SECRET: &str = "test-jwt-secret-questionnaire-templates";

/// Modèle standard seedé par la migration 0294.
const SEED_STANDARD_TEMPLATE_ID: &str = "02940000-0000-0000-0000-000000000001";

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

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900
}

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": user_id, "kind": "pro", "cabinet_id": cabinet_id,
            "role": "practitioner", "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    patient_user_id: Uuid,
    account_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("qt-prac+{prac_user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("qt-patient+{patient_user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alex', 'QuestionnaireTemplate')",
    )
    .bind(account_id)
    .bind(patient_user_id)
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
        .bind(format!("Cabinet QuestionnaireTemplate {cabinet_id}"))
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

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        prac_user_id,
        patient_user_id,
        account_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(f.account_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM medical_questionnaire_submission WHERE patient_account_id = $1")
        .bind(f.account_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM questionnaire_template WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(f.prac_user_id)
        .bind(f.patient_user_id)
        .execute(db)
        .await
        .ok();
}

async fn call(
    state: AppState,
    method: &str,
    uri: &str,
    token: &str,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("Authorization", format!("Bearer {token}"));
    let body = match body {
        Some(v) => {
            builder = builder.header("Content-Type", "application/json");
            Body::from(v.to_string())
        }
        None => Body::empty(),
    };
    let response = app(state)
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

fn custom_schema() -> serde_json::Value {
    json!([
        {
            "key": "urgence_contact",
            "type": "text",
            "label": "Contact d'urgence",
            "options": null,
            "condition": null,
            "safety_flag": false,
            "required": true
        },
        {
            "key": "groupe_sanguin",
            "type": "select",
            "label": "Groupe sanguin",
            "options": ["A", "B", "AB", "O"],
            "condition": null,
            "safety_flag": false,
            "required": true
        }
    ])
}

// ── Test 1 : liste = standard global + modèle créé par le cabinet ──────────

#[tokio::test]
async fn list_includes_global_standard_and_cabinet_template() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.prac_user_id, f.cabinet_id);

    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/questionnaire-templates",
        &token,
        Some(json!({"title": "Modèle cabinet", "schema": custom_schema()})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(created["version"], 1);

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/questionnaire-templates",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let templates = list.as_array().unwrap();
    assert!(templates
        .iter()
        .any(|t| t["id"] == SEED_STANDARD_TEMPLATE_ID && t["is_global"] == true));
    assert!(templates
        .iter()
        .any(|t| t["title"] == "Modèle cabinet" && t["is_global"] == false));

    cleanup(&db, &f).await;
}

// ── Test 2 : un second POST alors qu'un modèle est déjà actif → 409 ────────

#[tokio::test]
async fn create_second_active_template_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.prac_user_id, f.cabinet_id);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/questionnaire-templates",
        &token,
        Some(json!({"title": "Premier", "schema": custom_schema()})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/questionnaire-templates",
        &token,
        Some(json!({"title": "Second", "schema": custom_schema()})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(resp["code"], "questionnaire_template_already_exists");

    cleanup(&db, &f).await;
}

// ── Test 3 : schéma structurellement invalide → 422 ─────────────────────────

#[tokio::test]
async fn create_with_invalid_schema_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.prac_user_id, f.cabinet_id);

    // Clé dupliquée.
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/questionnaire-templates",
        &token,
        Some(json!({
            "title": "Invalide",
            "schema": [
                {
                    "key": "a", "type": "text", "label": "A",
                    "options": null, "condition": null, "safety_flag": false
                },
                {
                    "key": "a", "type": "text", "label": "A bis",
                    "options": null, "condition": null, "safety_flag": false
                }
            ]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Type inconnu.
    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/questionnaire-templates",
        &token,
        Some(json!({
            "title": "Invalide 2",
            "schema": [
                {
                    "key": "a", "type": "date", "label": "A",
                    "options": null, "condition": null, "safety_flag": false
                }
            ]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test 4 : PATCH évolue le modèle (nouvelle version) ──────────────────────

#[tokio::test]
async fn patch_creates_new_version_and_deactivates_old() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.prac_user_id, f.cabinet_id);

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/questionnaire-templates",
        &token,
        Some(json!({"title": "V1", "schema": custom_schema()})),
    )
    .await;
    let old_id = created["id"].as_str().unwrap().to_string();

    let (status, patched) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/questionnaire-templates/{old_id}"),
        &token,
        Some(json!({"title": "V2"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let new_id = patched["id"].as_str().unwrap().to_string();
    assert_ne!(new_id, old_id);
    assert_eq!(patched["version"], 2);

    let (_, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/questionnaire-templates",
        &token,
        None,
    )
    .await;
    let templates = list.as_array().unwrap();
    assert!(!templates.iter().any(|t| t["id"] == old_id));
    assert!(templates
        .iter()
        .any(|t| t["id"] == new_id && t["title"] == "V2"));

    cleanup(&db, &f).await;
}

// ── Test 5 : DELETE désactive, le cabinet retombe sur le standard ──────────

#[tokio::test]
async fn delete_deactivates_and_falls_back_to_global_standard() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_jwt(f.prac_user_id, f.cabinet_id);
    let patient_token = make_patient_jwt(f.patient_user_id, f.account_id);

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/questionnaire-templates",
        &token,
        Some(json!({"title": "Temporaire", "schema": custom_schema()})),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();

    let (status, active) = call(
        state_with(app_pool().await),
        "GET",
        &format!(
            "/v1/account/medical-questionnaire/active-template?cabinet_id={}",
            f.cabinet_id
        ),
        &patient_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(active["template_id"], id);

    let (status, _) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/questionnaire-templates/{id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, active_after) = call(
        state_with(app_pool().await),
        "GET",
        &format!(
            "/v1/account/medical-questionnaire/active-template?cabinet_id={}",
            f.cabinet_id
        ),
        &patient_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(active_after["template_id"], SEED_STANDARD_TEMPLATE_ID);

    cleanup(&db, &f).await;
}

// ── Test 6 : soumission validée contre un modèle custom ─────────────────────

#[tokio::test]
async fn submission_is_validated_against_custom_template_schema() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let prac_token = make_pro_jwt(f.prac_user_id, f.cabinet_id);
    let patient_token = make_patient_jwt(f.patient_user_id, f.account_id);

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/questionnaire-templates",
        &prac_token,
        Some(json!({"title": "Custom", "schema": custom_schema()})),
    )
    .await;
    let template_id = created["id"].as_str().unwrap().to_string();

    // Brouillon partiel (aucun champ requis fourni) : accepté, c'est un draft.
    let (status, draft) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/account/medical-questionnaire",
        &patient_token,
        Some(json!({"cabinet_id": f.cabinet_id, "payload": {}})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(draft["template_id"], template_id);
    assert_eq!(draft["template_version"], 1);

    // Soumission finale sans les champs requis → 422.
    let (status, resp) = call(
        state_with(app_pool().await),
        "PATCH",
        "/v1/account/medical-questionnaire",
        &patient_token,
        Some(json!({"cabinet_id": f.cabinet_id, "submit": true})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(resp["code"], "questionnaire_schema_violation");

    // Valeur hors options pour le select → 422, pas d'écriture.
    let (status, resp) = call(
        state_with(app_pool().await),
        "PATCH",
        "/v1/account/medical-questionnaire",
        &patient_token,
        Some(json!({
            "cabinet_id": f.cabinet_id,
            "payload": {"urgence_contact": "06 00 00 00 00", "groupe_sanguin": "Z"},
            "submit": true
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(resp["code"], "questionnaire_schema_violation");

    // Soumission complète et valide → 200.
    let (status, submitted) = call(
        state_with(app_pool().await),
        "PATCH",
        "/v1/account/medical-questionnaire",
        &patient_token,
        Some(json!({
            "cabinet_id": f.cabinet_id,
            "payload": {"urgence_contact": "06 00 00 00 00", "groupe_sanguin": "O"},
            "submit": true
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(submitted["status"], "submitted");
    assert_eq!(submitted["template_id"], template_id);

    cleanup(&db, &f).await;
}
