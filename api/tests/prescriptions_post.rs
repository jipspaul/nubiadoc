//! Tests d'intégration : POST /v1/cabinet/prescriptions (création d'ordonnance)

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

const JWT_SECRET: &str = "test-secret-prescriptions-post";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "practitioner".into(),
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "secretary".into(),
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Fixture minimale : cabinet + praticien + patient.
/// Retourne `(cabinet_id, prac_user_id, prac_id, patient_id)`.
async fn insert_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
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
    .bind(prac_user_id)
    .bind(format!("presc-create+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Presc Create Test', 'dentaire')",
    )
    .bind(cabinet_id)
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'Test')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Appointment passé : le praticien a bien soigné ce patient (requis par
    // la garde relation-de-soin E.2.16.c, cf. #3769).
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', now(), 'done', 'contrôle')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (cabinet_id, prac_user_id, prac_id, patient_id)
}

/// Variante sans relation de soin : le praticien n'a JAMAIS eu de rendez-vous
/// avec ce patient (cf. #3769 — garde `has_appointment` manquante).
async fn insert_fixture_no_appointment(db: &PgPool) -> (Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
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
    .bind(prac_user_id)
    .bind(format!("presc-create-noappt+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Presc Create NoAppt Test', 'dentaire')",
    )
    .bind(cabinet_id)
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Camille', 'Rousseau')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (cabinet_id, prac_user_id, prac_id, patient_id)
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();

    sqlx::query("DELETE FROM prescription_item WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM prescription WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();

    tx.commit().await.ok();
}

// ── Test 1 : praticien valide → 201 avec prescription_id ─────────────────────

#[tokio::test]
async fn create_prescription_practitioner_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_user_id, prac_id, patient_id) = insert_fixture(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = json!({
        "patient_id": patient_id,
        "items": [
            {
                "label": "Paracétamol 1 g",
                "form": "comprimé",
                "posology": "1 cp × 3 / jour si douleur",
                "duration": "5 jours",
                "quantity": "QSP 15 cp"
            }
        ]
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/prescriptions")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

    let prescription_id = v["prescription_id"]
        .as_str()
        .and_then(|s| s.parse::<Uuid>().ok());
    assert!(
        prescription_id.is_some(),
        "prescription_id doit être un UUID valide"
    );

    // Vérifie que la prescription et les items existent en base.
    let pid = prescription_id.unwrap();
    let row = sqlx::query("SELECT status FROM prescription WHERE id = $1")
        .bind(pid)
        .fetch_one(&db)
        .await
        .unwrap();
    let status: String = sqlx::Row::try_get(&row, "status").unwrap();
    assert_eq!(status, "draft");

    let item_count: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM prescription_item WHERE prescription_id = $1")
            .bind(pid)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(item_count, 1);

    cleanup_fixture(&db, cabinet_id, prac_user_id, prac_id, patient_id).await;
}

// ── Test 2 : body invalide (items vides) → 422 ───────────────────────────────

#[tokio::test]
async fn create_prescription_empty_items_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_user_id, prac_id, patient_id) = insert_fixture(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = json!({
        "patient_id": patient_id,
        "items": []
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/prescriptions")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixture(&db, cabinet_id, prac_user_id, prac_id, patient_id).await;
}

// ── Test 2bis (#4410) : octet NUL dans un item → 422 (pas 500) ──────────────

#[tokio::test]
async fn create_prescription_nul_byte_in_item_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_user_id, prac_id, patient_id) = insert_fixture(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = json!({
        "patient_id": patient_id,
        "items": [{"label": "a\u{0}b", "posology": "y", "duration": "z"}]
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/prescriptions")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixture(&db, cabinet_id, prac_user_id, prac_id, patient_id).await;
}

// ── Test 3 : token secrétaire → 403 ──────────────────────────────────────────

#[tokio::test]
async fn create_prescription_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_user_id, prac_id, patient_id) = insert_fixture(&db).await;

    let secretary_id = Uuid::new_v4();
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = json!({
        "patient_id": patient_id,
        "items": [
            {
                "label": "Amoxicilline 500 mg",
                "posology": "1 gélule × 3 / jour",
                "duration": "7 jours"
            }
        ]
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/prescriptions")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_secretary_token(secretary_id, cabinet_id)),
                )
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup_fixture(&db, cabinet_id, prac_user_id, prac_id, patient_id).await;
}

// ── Test 4 : praticien sans relation de soin avec le patient → 403 (#3769) ───

#[tokio::test]
async fn create_prescription_no_appointment_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_user_id, prac_id, patient_id) = insert_fixture_no_appointment(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = json!({
        "patient_id": patient_id,
        "items": [
            {
                "label": "Amoxicilline 1g",
                "posology": "1 matin et soir",
                "duration": "7 jours"
            }
        ]
    });

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/prescriptions")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    // Aucune prescription ne doit avoir été créée.
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM prescription WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(count, 0);

    cleanup_fixture(&db, cabinet_id, prac_user_id, prac_id, patient_id).await;
}

// ── Test 6 (#6101) : champs design-v2 persistés puis restitués au GET ───────

#[tokio::test]
async fn create_prescription_persists_design_v2_fields() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_user_id, prac_id, patient_id) = insert_fixture(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let body = json!({
        "patient_id": patient_id,
        "items": [
            {
                "label": "Amoxicilline",
                "form": "comprimé",
                "posology": "1 comprimé 3 fois par jour",
                "duration": "7 jours",
                "quantity": "21",
                "structured_posology": {"dose": 1, "frequency_per_day": 3, "duration_in_days": 7},
                "non_substitution_reason": "MTE marge thérapeutique étroite",
                "non_renouvelable": true,
                "product_reference": {
                    "id": "11111111-2222-3333-4444-555555555555",
                    "dci": "Amoxicilline",
                    "galenic_form": "comprimé",
                    "therapeutic_class": "antibiotique"
                }
            }
        ]
    });

    let token = make_practitioner_token(prac_user_id, cabinet_id);

    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/prescriptions")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let created: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let prescription_id = created["prescription_id"].as_str().unwrap().to_string();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/prescriptions/{}", prescription_id))
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
    let fetched: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let item = &fetched["items"][0];

    assert_eq!(
        item["structured_posology"],
        json!({"dose": 1, "frequency_per_day": 3, "duration_in_days": 7})
    );
    assert_eq!(
        item["non_substitution_reason"],
        "MTE marge thérapeutique étroite"
    );
    assert_eq!(item["non_renouvelable"], true);
    assert_eq!(
        item["product_reference"],
        json!({
            "id": "11111111-2222-3333-4444-555555555555",
            "dci": "Amoxicilline",
            "galenic_form": "comprimé",
            "therapeutic_class": "antibiotique"
        })
    );

    cleanup_fixture(&db, cabinet_id, prac_user_id, prac_id, patient_id).await;
}
