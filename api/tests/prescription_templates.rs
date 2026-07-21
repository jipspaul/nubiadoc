//! Tests d'intégration : routes `prescription_template` (#4074)
//! - `GET`/`POST /v1/cabinet/prescription-templates`
//! - `POST /v1/cabinet/prescriptions/:id/apply-template`

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-prescription-templates";

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

struct Fixture {
    cabinet_id: Uuid,
    user_id: Uuid,
    patient_id: Uuid,
    prescription_id: Uuid,
    private_template_id: Uuid,
}

/// Seed : cabinet + practitioner + patient + prescription `draft` + un
/// modèle privé au cabinet (2 lignes).
async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prescription_id = Uuid::new_v4();
    let private_template_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("presc-tmpl+{user_id}@nubia.test"))
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
        .bind(format!("Cabinet PrescTmpl {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'PrescTemplate')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status) \
         VALUES ($1, $2, $3, $4, 'draft')",
    )
    .bind(prescription_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO prescription_template (id, cabinet_id, label, items) \
         VALUES ($1, $2, 'Modèle privé test', $3::jsonb)",
    )
    .bind(private_template_id)
    .bind(cabinet_id)
    .bind(json!([
        {"label": "Paracétamol 1 g", "form": "comprimé", "posology": "1 cp x 3/jour", "duration": "5 jours", "quantity": "QSP 15 cp"},
        {"label": "Ibuprofène 400 mg", "form": "comprimé", "posology": "1 cp x 3/jour", "duration": "3 jours", "quantity": null}
    ]).to_string())
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
        patient_id,
        prescription_id,
        private_template_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM prescription_template WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM prescription_item WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM prescription WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn apply_template(
    state: AppState,
    prescription_id: Uuid,
    token: String,
    template_id: Uuid,
) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/prescriptions/{prescription_id}/apply-template"
                ))
                .header("Authorization", format!("Bearer {token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({ "template_id": template_id }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

// ── Test 1 : applique un modèle sur un brouillon -> crée les prescription_item ──

#[tokio::test]
async fn apply_template_on_draft_creates_expected_items() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;

    let (status, resp) = apply_template(
        state_with(app_pool().await),
        f.prescription_id,
        make_pro_jwt(f.user_id, f.cabinet_id, "practitioner"),
        f.private_template_id,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(resp["items_created"], 2);

    let rows = sqlx::query(
        "SELECT label, posology, duration FROM prescription_item \
         WHERE prescription_id = $1 ORDER BY label",
    )
    .bind(f.prescription_id)
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(rows.len(), 2);
    let labels: Vec<String> = rows
        .iter()
        .map(|r| r.try_get::<String, _>("label").unwrap())
        .collect();
    assert_eq!(
        labels,
        vec![
            "Ibuprofène 400 mg".to_string(),
            "Paracétamol 1 g".to_string()
        ]
    );

    cleanup(&db, &f).await;
}

// ── Test 2 : un praticien d'un autre cabinet reçoit 404 sur un modèle qui n'est pas le sien ──

#[tokio::test]
async fn apply_template_of_other_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;

    // Second cabinet + son propre brouillon.
    let other_cabinet_id = Uuid::new_v4();
    let other_user_id = Uuid::new_v4();
    let other_prac_id = Uuid::new_v4();
    let other_patient_id = Uuid::new_v4();
    let other_prescription_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(other_user_id)
    .bind(format!("presc-tmpl-other+{other_user_id}@nubia.test"))
    .execute(&db)
    .await
    .unwrap();

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(other_cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(other_cabinet_id)
        .bind(format!("Cabinet PrescTmpl Other {other_cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
            .bind(other_prac_id)
            .bind(other_cabinet_id)
            .bind(other_user_id)
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
             VALUES ($1, $2, 'Autre', 'Cabinet')",
        )
        .bind(other_patient_id)
        .bind(other_cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status) \
             VALUES ($1, $2, $3, $4, 'draft')",
        )
        .bind(other_prescription_id)
        .bind(other_cabinet_id)
        .bind(other_patient_id)
        .bind(other_prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    // Le praticien du cabinet B tente d'appliquer le modèle PRIVÉ du cabinet A
    // sur SON PROPRE brouillon (cabinet B) -> le modèle est invisible (RLS) -> 404.
    let (status, _) = apply_template(
        state_with(app_pool().await),
        other_prescription_id,
        make_pro_jwt(other_user_id, other_cabinet_id, "practitioner"),
        f.private_template_id,
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);

    // Cleanup du second cabinet.
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(other_cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM prescription WHERE cabinet_id = $1")
            .bind(other_cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
            .bind(other_cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
            .bind(other_cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM cabinet WHERE id = $1")
            .bind(other_cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_user_id)
        .execute(&db)
        .await
        .ok();

    cleanup(&db, &f).await;
}

// ── Test 3 : prescription non-draft -> 409 ───────────────────────────────────

#[tokio::test]
async fn apply_template_on_signed_prescription_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;

    sqlx::query("UPDATE prescription SET status = 'signed' WHERE id = $1")
        .bind(f.prescription_id)
        .execute(&db)
        .await
        .unwrap();

    let (status, _) = apply_template(
        state_with(app_pool().await),
        f.prescription_id,
        make_pro_jwt(f.user_id, f.cabinet_id, "practitioner"),
        f.private_template_id,
    )
    .await;

    assert_eq!(status, StatusCode::CONFLICT);

    cleanup(&db, &f).await;
}

// ── Test 4 : GET liste les modèles globaux (seed #4073) + privés du cabinet ──

#[tokio::test]
async fn list_templates_includes_global_and_own_cabinet_templates() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;

    let response = app(state_with(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/prescription-templates")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(f.user_id, f.cabinet_id, "practitioner")
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
    let templates: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let templates = templates.as_array().unwrap();

    // Au moins les 5 modèles globaux (#4073) + le modèle privé du cabinet.
    assert!(
        templates.len() >= 6,
        "attendu >= 6 (5 globaux + 1 privé), reçu {}",
        templates.len()
    );
    assert!(templates
        .iter()
        .any(|t| t["label"] == "Modèle privé test" && t["is_global"] == false));
    assert!(templates.iter().any(|t| t["is_global"] == true));

    cleanup(&db, &f).await;
}
