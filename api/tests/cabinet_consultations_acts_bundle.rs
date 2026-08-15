//! Tests d'intégration : POST /v1/cabinet/consultations/:id/acts avec
//! bundle_code (#4115, table ccam_act_bundle/ccam_act_bundle_item, migration 0182)

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

const JWT_SECRET: &str = "test-secret-acts-bundle";

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
    prac_id: Uuid,
    prac_user_id: Uuid,
    patient_id: Uuid,
    appt_id: Uuid,
    session_id: Uuid,
    bundle_code: String,
    empty_bundle_code: String,
    risky_bundle_code: String,
}

/// Bundle "couronne_test" = HBQK002 (tarif 2300, qty 1) + HBGD036 (tarif
/// 2864, qty 2) — un code répété volontairement absent (UNIQUE bundle_code+
/// ccam_code), qty > 1 vérifie la multiplication du tarif.
async fn insert_fixtures(db: &PgPool, risky_treatments: bool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();
    let bundle_code = format!("BUNDLE-TEST-{}", Uuid::new_v4().simple());
    let empty_bundle_code = format!("BUNDLE-EMPTY-{}", Uuid::new_v4().simple());
    let risky_bundle_code = format!("BUNDLE-RISKY-{}", Uuid::new_v4().simple());

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
    .bind(format!("bundle-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Bundle Test', 'dentaire')",
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
         VALUES ($1, $2, 'Patient', 'Bundle')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now(), now() + interval '1 hour', 'in_progress', 'bilan')",
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

    if risky_treatments {
        let ciphertext = format!(
            "STUB_ENC:{}",
            json!({"allergies": [], "treatments": ["Warfarine 5mg"], "history": null})
        );
        sqlx::query(
            "INSERT INTO medical_record (cabinet_id, patient_id, data_ciphertext, data_key_ref) \
             VALUES ($1, $2, $3, 'stub-key-ref')",
        )
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(ciphertext.as_bytes())
        .execute(&mut *tx)
        .await
        .unwrap();
    }

    tx.commit().await.unwrap();

    // ccam_act_bundle/ccam_act_bundle_item : catalogue public, écrit hors RLS
    // tenant (nubia_owner, comme le reste des fixtures superuser).
    sqlx::query("INSERT INTO ccam_act_bundle (code, label) VALUES ($1, 'Bundle de test')")
        .bind(&bundle_code)
        .execute(db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO ccam_act_bundle (code, label) VALUES ($1, 'Bundle vide')")
        .bind(&empty_bundle_code)
        .execute(db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO ccam_act_bundle (code, label) VALUES ($1, 'Bundle risqué')")
        .bind(&risky_bundle_code)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO ccam_act_bundle_item (bundle_code, ccam_code, qty) VALUES ($1, 'HBQK002', 1)",
    )
    .bind(&bundle_code)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO ccam_act_bundle_item (bundle_code, ccam_code, qty) VALUES ($1, 'HBGD036', 2)",
    )
    .bind(&bundle_code)
    .execute(db)
    .await
    .unwrap();
    // Bundle avec un item invasif à risque (#4057) — HBLD724 = avulsion.
    sqlx::query(
        "INSERT INTO ccam_act_bundle_item (bundle_code, ccam_code, qty) VALUES ($1, 'HBLD724', 1)",
    )
    .bind(&risky_bundle_code)
    .execute(db)
    .await
    .unwrap();

    Fixtures {
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
        bundle_code,
        empty_bundle_code,
        risky_bundle_code,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    sqlx::query("DELETE FROM ccam_act_bundle_item WHERE bundle_code IN ($1, $2, $3)")
        .bind(&f.bundle_code)
        .bind(&f.empty_bundle_code)
        .bind(&f.risky_bundle_code)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM ccam_act_bundle WHERE code IN ($1, $2, $3)")
        .bind(&f.bundle_code)
        .bind(&f.empty_bundle_code)
        .bind(&f.risky_bundle_code)
        .execute(db)
        .await
        .ok();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
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
    sqlx::query("DELETE FROM medical_record WHERE patient_id = $1")
        .bind(f.patient_id)
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
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : bundle_code valide → 201, un acte par ligne, tarif×qty ─────────

#[tokio::test]
async fn add_act_with_bundle_code_creates_one_act_per_item() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, false).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", f.session_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"bundle_code": f.bundle_code, "tooth": "26"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    if resp.status() != StatusCode::CREATED {
        let status = resp.status();
        let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
            .await
            .unwrap();
        panic!(
            "DEBUG status={status} body={}",
            String::from_utf8_lossy(&bytes)
        );
    }
    assert_eq!(resp.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let acts = body["acts"]
        .as_array()
        .expect("réponse bundle = {acts: []}");
    assert_eq!(acts.len(), 2);

    // Vérifie en DB : 2 lignes, tarifs corrects (HBQK002: 2300×1, HBGD036: 2864×2).
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let rows = sqlx::query(
        "SELECT ccam_code, amount_cents, tooth FROM consultation_act \
         WHERE appointment_id = $1 ORDER BY ccam_code",
    )
    .bind(f.appt_id)
    .fetch_all(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    assert_eq!(rows.len(), 2);
    let by_code: std::collections::HashMap<String, i32> = rows
        .iter()
        .map(|r| {
            (
                r.try_get::<String, _>("ccam_code").unwrap(),
                r.try_get::<i32, _>("amount_cents").unwrap(),
            )
        })
        .collect();
    assert_eq!(by_code.get("HBQK002"), Some(&2300));
    assert_eq!(by_code.get("HBGD036"), Some(&5728)); // 2864 * 2
    let tooth: Option<String> = rows[0].try_get("tooth").unwrap();
    assert_eq!(tooth.as_deref(), Some("26"));

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : bundle_code inconnu → 422 ───────────────────────────────────────

#[tokio::test]
async fn add_act_with_unknown_bundle_code_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, false).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", f.session_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"bundle_code": "CODE_INEXISTANT"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : ccam_code ET bundle_code fournis → 422 (ambigu) ────────────────

#[tokio::test]
async fn add_act_with_both_ccam_code_and_bundle_code_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, false).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", f.session_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "ccam_code": "HBQK002",
                        "label": "Examen",
                        "bundle_code": f.bundle_code
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 4 : ni ccam_code ni bundle_code → 422 ───────────────────────────────

#[tokio::test]
async fn add_act_with_neither_code_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, false).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", f.session_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(json!({"tooth": "26"}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 5 : bundle avec un item invasif + patient sous anticoagulants → 409,
//    rien n'est inséré (atomicité transactionnelle) ──────────────────────────

#[tokio::test]
async fn add_act_with_bundle_containing_risky_item_returns_409_and_inserts_nothing() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, true).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", f.session_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"bundle_code": f.risky_bundle_code}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::CONFLICT);

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let count: i64 =
        sqlx::query("SELECT count(*) AS n FROM consultation_act WHERE appointment_id = $1")
            .bind(f.appt_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap()
            .try_get("n")
            .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(
        count, 0,
        "aucun acte du bundle ne doit être inséré (409 bloquant)"
    );

    cleanup_fixtures(&db, &f).await;
}

// ── Test 6 : bundle_code sans aucune ligne → 422 ─────────────────────────────

#[tokio::test]
async fn add_act_with_empty_bundle_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, false).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", f.session_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"bundle_code": f.empty_bundle_code}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixtures(&db, &f).await;
}
