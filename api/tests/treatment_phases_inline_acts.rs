//! Test d'intégration : POST /v1/cabinet/treatment-plans/:id/phases avec
//! `inline_acts` (#4263) — crée les `quote_item` correspondants (nouveau
//! devis `draft`) et les rattache à la phase en une seule transaction.

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

const JWT_SECRET: &str = "test-secret-treatment-phases-inline-acts";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
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
            "role": "practitioner",
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
    patient_id: Uuid,
    plan_id: Uuid,
}

async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let plan_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("tph-inline+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Phase Inline Test', 'dentaire')",
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
         VALUES ($1, $2, 'Marie', 'Durand')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO treatment_plan (id, cabinet_id, patient_id, title, status) \
         VALUES ($1, $2, $3, 'Plan test', 'draft')",
    )
    .bind(plan_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Appointment passé : le praticien a consulté ce patient (garde §14, #4400).
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

    Fixtures {
        cabinet_id,
        user_id,
        patient_id,
        plan_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_item WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_phase WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM treatment_plan WHERE cabinet_id = $1")
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

#[tokio::test]
async fn inline_acts_create_quote_items_attached_to_phase() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/treatment-plans/{}/phases", f.plan_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({
                        "title": "Phase 1 · Chirurgie",
                        "position": 1,
                        "inline_acts": [
                            {"label": "Couronne", "ccam_code": "HBQK002", "tooth": "11", "amount_cents": 45000},
                            {"label": "Implant", "amount_cents": 120000},
                        ],
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
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let phase_id: Uuid = v["phase_id"].as_str().unwrap().parse().unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    let rows = sqlx::query(
        "SELECT label, ccam_code, tooth, (unit_amount * 100)::bigint AS unit_amount_cents, quote_id \
         FROM quote_item WHERE phase_id = $1 ORDER BY unit_amount ASC",
    )
    .bind(phase_id)
    .fetch_all(&mut *tx)
    .await
    .unwrap();
    assert_eq!(rows.len(), 2);

    let first_label: String = rows[0].try_get("label").unwrap();
    let first_amount_cents: i64 = rows[0].try_get("unit_amount_cents").unwrap();
    assert_eq!(first_label, "Couronne");
    assert_eq!(first_amount_cents, 45000);

    let second_label: String = rows[1].try_get("label").unwrap();
    let second_ccam: Option<String> = rows[1].try_get("ccam_code").unwrap();
    assert_eq!(second_label, "Implant");
    assert_eq!(second_ccam, None);

    let quote_id: Uuid = rows[0].try_get("quote_id").unwrap();
    let quote_row = sqlx::query(
        "SELECT patient_id, status, (total_amount * 100)::bigint AS total_amount_cents \
         FROM quote WHERE id = $1",
    )
    .bind(quote_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    let quote_patient_id: Uuid = quote_row.try_get("patient_id").unwrap();
    let quote_status: String = quote_row.try_get("status").unwrap();
    let quote_total_cents: i64 = quote_row.try_get("total_amount_cents").unwrap();
    assert_eq!(quote_patient_id, f.patient_id);
    assert_eq!(quote_status, "draft");
    assert_eq!(quote_total_cents, 165000);

    tx.commit().await.unwrap();

    cleanup_fixtures(&db, &f).await;
}

#[tokio::test]
async fn inline_act_empty_label_returns_422_and_creates_nothing() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/treatment-plans/{}/phases", f.plan_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(
                    json!({
                        "title": "Phase 1",
                        "position": 1,
                        "inline_acts": [{"label": "   ", "amount_cents": 1000}],
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let phase_count: i64 =
        sqlx::query("SELECT count(*) AS n FROM treatment_phase WHERE cabinet_id = $1")
            .bind(f.cabinet_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap()
            .try_get("n")
            .unwrap();
    let quote_count: i64 = sqlx::query("SELECT count(*) AS n FROM quote WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap()
        .try_get("n")
        .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(phase_count, 0, "aucune phase ne doit être créée");
    assert_eq!(quote_count, 0, "aucun devis ne doit être créé");

    cleanup_fixtures(&db, &f).await;
}
