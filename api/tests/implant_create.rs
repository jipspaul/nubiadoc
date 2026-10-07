//! Tests d'intégration : POST /v1/cabinet/patients/:id/implants (#4140)

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

const JWT_SECRET: &str = "test-secret-implant-create";

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

fn make_state(db: PgPool) -> AppState {
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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub, "kind": "pro", "cabinet_id": cabinet_id,
            "role": "practitioner", "exp": exp()
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
    patient_id: Uuid,
}

async fn insert_fixtures(db: &PgPool, with_appointment: bool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("implant-prac+{user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Implant Test', 'dentaire')",
    )
    .bind(cabinet_id)
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
         VALUES ($1, $2, 'Robert', 'Molaire')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    if with_appointment {
        sqlx::query(
            "INSERT INTO appointment \
             (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
             VALUES ($1, $2, $3, $4, now() - interval '1 hour', now(), 'done', 'pose implant')",
        )
        .bind(Uuid::new_v4())
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    }

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        user_id,
        patient_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM implant_passport WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

#[tokio::test]
async fn create_implant_succeeds_and_visible_via_get() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/implants", f.patient_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::from(
                    json!({
                        "brand": "Nobel Biocare",
                        "implant_ref": "NB-4213",
                        "lot_number": "L2026-07",
                        "placement_date": "2026-07-29",
                        "tooth_position": "26",
                        "notes": "pose sans complication"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let implant_id = body["implant_id"].as_str().unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT brand, implant_ref FROM implant_passport WHERE id = $1")
        .bind(Uuid::parse_str(implant_id).unwrap())
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let brand: String = row.try_get("brand").unwrap();
    assert_eq!(brand, "Nobel Biocare");

    cleanup_fixtures(&db, &f).await;
}

/// #8125 : les 8 champs d'identification dispositif + suivi (#7665) doivent
/// être acceptés et persistés, pas rejetés en 422 / silencieusement perdus.
#[tokio::test]
async fn create_implant_with_device_details_persists_all_fields() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/implants", f.patient_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::from(
                    json!({
                        "brand": "Straumann",
                        "implant_ref": "QA-R133-IRM",
                        "lot_number": "ST-9021-07C",
                        "placement_date": "2026-07-29",
                        "tooth_position": "26",
                        "notes": "QA R133",
                        "manufacturer": "Straumann",
                        "model": "BLT Roxolid",
                        "reference": "36214",
                        "dimensions": "Ø 4,3 mm · L 11,5 mm",
                        "material": "Titane grade 4",
                        "mri_compatibility": "Compatible IRM sous conditions",
                        "last_control_date": "2026-07-29",
                        "next_control": "Juillet 2027 · annuel"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let implant_id = body["implant_id"].as_str().unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query(
        "SELECT manufacturer, model, reference, dimensions, material, mri_compatibility, \
         last_control_date, next_control \
         FROM implant_passport WHERE id = $1",
    )
    .bind(Uuid::parse_str(implant_id).unwrap())
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let manufacturer: String = row.try_get("manufacturer").unwrap();
    let model: String = row.try_get("model").unwrap();
    let reference: String = row.try_get("reference").unwrap();
    let dimensions: String = row.try_get("dimensions").unwrap();
    let material: String = row.try_get("material").unwrap();
    let mri_compatibility: String = row.try_get("mri_compatibility").unwrap();
    let last_control_date: chrono::NaiveDate = row.try_get("last_control_date").unwrap();
    let next_control: String = row.try_get("next_control").unwrap();

    assert_eq!(manufacturer, "Straumann");
    assert_eq!(model, "BLT Roxolid");
    assert_eq!(reference, "36214");
    assert_eq!(dimensions, "Ø 4,3 mm · L 11,5 mm");
    assert_eq!(material, "Titane grade 4");
    assert_eq!(mri_compatibility, "Compatible IRM sous conditions");
    assert_eq!(last_control_date.to_string(), "2026-07-29");
    assert_eq!(next_control, "Juillet 2027 · annuel");

    cleanup_fixtures(&db, &f).await;
}

#[tokio::test]
async fn create_implant_empty_brand_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/implants", f.patient_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::from(
                    json!({"brand": "  ", "implant_ref": "NB-4213"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, &f).await;
}

#[tokio::test]
async fn create_implant_unknown_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/implants", Uuid::new_v4()))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::from(
                    json!({"brand": "Nobel Biocare", "implant_ref": "NB-4213"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::NOT_FOUND);

    cleanup_fixtures(&db, &f).await;
}

/// #4140 : garde §14 (relation de soin) — même discipline que
/// prescriptions.rs/dental_chart.rs (#4400).
#[tokio::test]
async fn create_implant_no_care_relationship_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, false).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/patients/{}/implants", f.patient_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::from(
                    json!({"brand": "Nobel Biocare", "implant_ref": "NB-4213"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, &f).await;
}
