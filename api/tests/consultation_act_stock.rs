//! Tests d'intégration : décrémentation automatique du stock à la
//! facturation d'un acte (#4145), POST /v1/cabinet/consultations/:id/acts

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

const JWT_SECRET: &str = "test-secret-act-stock";

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

struct Fixture {
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    patient_id: Uuid,
    appt_id: Uuid,
    session_id: Uuid,
    ccam_code: String,
    stock_item_id: Uuid,
}

/// `mapped` : si `true`, crée aussi un `stock_item` + un mapping
/// `ccam_act_stock_consumption` (quantité 2) pour `ccam_code`.
async fn insert_fixture(db: &PgPool, tag: &str, mapped: bool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();
    let stock_item_id = Uuid::new_v4();
    let ccam_code = format!("TSTSTK{}", tag.to_uppercase());

    sqlx::query(
        "INSERT INTO ccam_act (code, label, tarif_cents, active) \
         VALUES ($1, 'Acte test stock', 10000, true)",
    )
    .bind(&ccam_code)
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
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!(
        "act-stock-{}-prac+{}@nubia.test",
        tag, prac_user_id
    ))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Act Stock Test', 'dentaire')",
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
         VALUES ($1, $2, 'Patient', 'ActStock')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now(), now() + interval '1 hour', 'in_progress', 'détartrage')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO consultation_session \
         (id, cabinet_id, appointment_id, practitioner_id, status) \
         VALUES ($1, $2, $3, $4, 'in_progress')",
    )
    .bind(session_id)
    .bind(cabinet_id)
    .bind(appt_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO stock_item (id, cabinet_id, reference, label, unit) \
         VALUES ($1, $2, 'GANTS-STK', 'Gants latex', 'boite')",
    )
    .bind(stock_item_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    if mapped {
        sqlx::query(
            "INSERT INTO ccam_act_stock_consumption (cabinet_id, ccam_code, stock_item_id, quantity) \
             VALUES ($1, $2, $3, 2)",
        )
        .bind(cabinet_id)
        .bind(&ccam_code)
        .bind(stock_item_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    }

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
        ccam_code,
        stock_item_id,
    }
}

async fn cleanup_fixture(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM stock_movement WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM ccam_act_stock_consumption WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM stock_item WHERE id = $1")
        .bind(f.stock_item_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_session WHERE id = $1")
        .bind(f.session_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_act WHERE appointment_id = $1")
        .bind(f.appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(f.appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(f.prac_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM ccam_act WHERE code = $1")
        .bind(&f.ccam_code)
        .execute(db)
        .await
        .ok();
}

async fn post_act(state: AppState, session_id: Uuid, token: &str, ccam_code: &str) -> StatusCode {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{session_id}/acts"))
                .header("Authorization", format!("Bearer {token}"))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({
                        "ccam_code": ccam_code,
                        "label": "Acte test stock",
                        "amount_cents": 9000
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    response.status()
}

// ── Acte mappé → décrémente le stock_item du bon delta ──────────────────────

#[tokio::test]
async fn mapped_act_decrements_linked_stock_item() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "map", true).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let status = post_act(
        AppState {
            db: app_pool().await,
            jwt_secret: JWT_SECRET.to_string(),
            mailer: Arc::new(StubMailer),
        },
        f.session_id,
        &token,
        &f.ccam_code,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let item_row = sqlx::query("SELECT quantity_on_hand FROM stock_item WHERE id = $1")
        .bind(f.stock_item_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let quantity_on_hand: i32 = item_row.try_get("quantity_on_hand").unwrap();
    assert_eq!(
        quantity_on_hand, -2,
        "le mapping (quantity=2) doit décrémenter le stock_item du bon delta"
    );

    let movement_row = sqlx::query(
        "SELECT delta, reason FROM stock_movement WHERE cabinet_id = $1 AND stock_item_id = $2",
    )
    .bind(f.cabinet_id)
    .bind(f.stock_item_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let delta: i32 = movement_row.try_get("delta").unwrap();
    let reason: String = movement_row.try_get("reason").unwrap();
    assert_eq!(delta, -2);
    assert_eq!(reason, "consumption");

    cleanup_fixture(&db, &f).await;
}

// ── Acte sans mapping → aucun mouvement créé ─────────────────────────────────

#[tokio::test]
async fn unmapped_act_creates_no_stock_movement() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "nomap", false).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let status = post_act(
        AppState {
            db: app_pool().await,
            jwt_secret: JWT_SECRET.to_string(),
            mailer: Arc::new(StubMailer),
        },
        f.session_id,
        &token,
        &f.ccam_code,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let count_row =
        sqlx::query("SELECT count(*)::int AS n FROM stock_movement WHERE cabinet_id = $1")
            .bind(f.cabinet_id)
            .fetch_one(&db)
            .await
            .unwrap();
    let n: i32 = count_row.try_get("n").unwrap();
    assert_eq!(n, 0, "aucun mapping → aucun mouvement de stock créé");

    let item_row = sqlx::query("SELECT quantity_on_hand FROM stock_item WHERE id = $1")
        .bind(f.stock_item_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let quantity_on_hand: i32 = item_row.try_get("quantity_on_hand").unwrap();
    assert_eq!(quantity_on_hand, 0);

    cleanup_fixture(&db, &f).await;
}
