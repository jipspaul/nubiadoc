//! Tests d'intégration : GET /v1/ccam/acts?tooth= — suggestion contextuelle
//! par type de dent (#4118)

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

const JWT_SECRET: &str = "test-secret-ccam-tooth-suggestion";

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
}

/// Historique : HBQK002 utilisé 3x sur des molaires (16, 26, 36), HBLD001 1x
/// sur une molaire (47) ; HBGD036 1x sur une incisive (11, hors-sujet pour
/// le test molaire).
async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();

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
    .bind(format!("tooth-sugg-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet ToothSuggestion Test', 'dentaire')",
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
         VALUES ($1, $2, 'Patient', 'ToothSuggestion')",
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

    for (code, tooth) in [
        ("HBQK002", "16"),
        ("HBQK002", "26"),
        ("HBQK002", "36"),
        ("HBLD001", "47"),
        ("HBGD036", "11"),
    ] {
        sqlx::query(
            "INSERT INTO consultation_act \
             (cabinet_id, appointment_id, patient_id, practitioner_id, ccam_code, label, tooth, amount_cents) \
             VALUES ($1, $2, $3, $4, $5, $5, $6, 0)",
        )
        .bind(cabinet_id)
        .bind(appt_id)
        .bind(patient_id)
        .bind(prac_id)
        .bind(code)
        .bind(tooth)
        .execute(&mut *tx)
        .await
        .unwrap();
    }

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
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
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : tooth molaire → HBQK002 (3x) avant HBLD001 (1x) ─────────────────

#[tokio::test]
async fn tooth_param_surfaces_most_used_code_for_same_tooth_type_first() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    // Tooth 17 = molaire (position 7), même type que 16/26/36/47.
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/ccam/acts?tooth=17")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let data = body["data"].as_array().unwrap();

    let position = |code: &str| data.iter().position(|a| a["code"] == code);
    let pos_hbqk002 = position("HBQK002").expect("HBQK002 doit être suggéré");
    let pos_hbld001 = position("HBLD001").expect("HBLD001 doit être suggéré");
    let pos_hbgd036 = position("HBGD036");

    assert!(
        pos_hbqk002 < pos_hbld001,
        "HBQK002 (3 usages molaire) doit précéder HBLD001 (1 usage molaire)"
    );
    if let Some(pos_incisive) = pos_hbgd036 {
        assert!(
            pos_hbld001 < pos_incisive,
            "les suggestions molaire doivent précéder le reste du catalogue alphabétique"
        );
    }

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : tooth incisive → seul HBGD036 (usage incisive) suggéré, pas HBQK002 ─

#[tokio::test]
async fn tooth_param_does_not_cross_tooth_types() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    // Tooth 21 = incisive (position 1), même type que 11.
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/ccam/acts?tooth=21")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let data = body["data"].as_array().unwrap();

    let pos_hbgd036 = data.iter().position(|a| a["code"] == "HBGD036");
    let pos_hbqk002 = data.iter().position(|a| a["code"] == "HBQK002");
    assert!(
        pos_hbgd036.is_some(),
        "HBGD036 (usage incisive) doit être suggéré"
    );
    assert!(
        pos_hbqk002.is_none() || pos_hbgd036 < pos_hbqk002,
        "HBQK002 (usage molaire uniquement) ne doit pas être suggéré avant le catalogue normal"
    );

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : q renseigné → tooth ignoré (recherche = filtre pur) ────────────

#[tokio::test]
async fn tooth_param_ignored_when_q_is_present() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    // q filtre sur un libellé sans rapport avec HBQK002/HBLD001/HBGD036 —
    // si tooth était appliqué malgré q, ces codes pourraient apparaître
    // hors-filtre. On vérifie juste que le filtre q reste strict.
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/ccam/acts?tooth=17&q=radiographie")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let data = body["data"].as_array().unwrap();

    assert!(
        data.iter().all(|a| a["label"]
            .as_str()
            .unwrap()
            .to_lowercase()
            .contains("radiographie")),
        "q reste un filtre strict même avec tooth fourni — aucune suggestion \
         hors-filtre ne doit apparaître"
    );

    cleanup_fixtures(&db, &f).await;
}
