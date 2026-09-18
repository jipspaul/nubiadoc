//! Tests d'intégration : étiquettes de stérilisation + usage par scan
//! (DP-F13.a, #7181)
//! - GET  /v1/sterilization/cycles/{id}/labels.pdf
//! - POST /v1/sterilization/pouches/{code}/use

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

const JWT_SECRET: &str = "test-secret-sterilization-labels";

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

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
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
            "role": "secretary",
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
    other_patient_id: Uuid,
    session_id: Uuid,
    cycle_id: Uuid,
    pouch_codes: Vec<String>,
}

/// Cabinet + secrétaire + praticien + 2 patients + 1 RDV/séance sur le
/// premier patient + 1 cycle conforme avec `pouches` sachets. Ids/codes
/// uniques par run (base partagée entre agents).
async fn seed(db: &PgPool, pouches: usize) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let other_patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();
    let cycle_id = Uuid::new_v4();
    let run = Uuid::new_v4().simple().to_string();
    let pouch_codes: Vec<String> = (0..pouches)
        .map(|i| format!("DM-{}-{i:03}", &run[..8]))
        .collect();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("steril-labels+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Sterilization Labels Test', 'dentaire')",
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
    for (id, last_name) in [(patient_id, "Sachet"), (other_patient_id, "Autre")] {
        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
             VALUES ($1, $2, 'Patient', $3)",
        )
        .bind(id)
        .bind(cabinet_id)
        .bind(last_name)
        .execute(&mut *tx)
        .await
        .unwrap();
    }
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
    sqlx::query(
        "INSERT INTO sterilization_cycle \
         (id, cabinet_id, autoclave_ref, cycle_number, test_kind, test_result, status) \
         VALUES ($1, $2, 'Autoclave-Labels', $3, 'bowie_dick', 'virage complet', 'conforme')",
    )
    .bind(cycle_id)
    .bind(cabinet_id)
    .bind(i32::try_from(1 + (Uuid::new_v4().as_u128() % 1_000_000)).unwrap())
    .execute(&mut *tx)
    .await
    .unwrap();
    for code in &pouch_codes {
        sqlx::query(
            "INSERT INTO sterilized_pouch (cabinet_id, cycle_id, code) VALUES ($1, $2, $3)",
        )
        .bind(cabinet_id)
        .bind(cycle_id)
        .bind(code)
        .execute(&mut *tx)
        .await
        .unwrap();
    }
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
        patient_id,
        other_patient_id,
        session_id,
        cycle_id,
        pouch_codes,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    for sql in [
        "DELETE FROM sterilized_pouch WHERE cabinet_id = $1",
        "DELETE FROM sterilization_cycle WHERE cabinet_id = $1",
        "DELETE FROM consultation_session WHERE cabinet_id = $1",
        "DELETE FROM appointment WHERE cabinet_id = $1",
        "DELETE FROM patient WHERE cabinet_id = $1",
        "DELETE FROM practitioner WHERE cabinet_id = $1",
        "DELETE FROM cabinet WHERE id = $1",
    ] {
        sqlx::query(sql)
            .bind(f.cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
    }
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

async fn call_raw(
    state: AppState,
    method: &str,
    uri: &str,
    token: &str,
    body: Option<serde_json::Value>,
) -> (StatusCode, axum::http::HeaderMap, Vec<u8>) {
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
    let headers = response.headers().clone();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (status, headers, bytes.to_vec())
}

async fn call(
    state: AppState,
    method: &str,
    uri: &str,
    token: &str,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let (status, _, bytes) = call_raw(state, method, uri, token, body).await;
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

fn count(haystack: &[u8], needle: &[u8]) -> usize {
    haystack
        .windows(needle.len())
        .filter(|w| w == &needle)
        .count()
}

async fn use_pouch(
    token: &str,
    code: &str,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/sterilization/pouches/{code}/use"),
        token,
        Some(body),
    )
    .await
}

// ── PDF : non vide, une page par LABELS_PER_PAGE (14) étiquettes ───────────────

#[tokio::test]
async fn labels_pdf_has_one_page_per_fourteen_labels() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    // 15 sachets → 2 pages (14 par planche, 2 colonnes × 7 lignes).
    let f = seed(&db, 15).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);

    let (status, headers, pdf) = call_raw(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/sterilization/cycles/{}/labels.pdf", f.cycle_id),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers["content-type"], "application/pdf");
    assert!(headers["content-disposition"]
        .to_str()
        .unwrap()
        .contains("etiquettes-sterilisation-Autoclave-Labels-"));
    assert!(pdf.starts_with(b"%PDF-1.4"));
    assert!(pdf.ends_with(b"%%EOF"));
    assert!(pdf.len() > 2_000, "pdf trop petit : {} octets", pdf.len());
    assert_eq!(count(&pdf, b"/Type /Page "), 2);
    assert_eq!(count(&pdf, b"/Count 2 "), 1);
    // Chaque code de sachet est imprimé en clair (en plus du QR).
    for code in &f.pouch_codes {
        assert_eq!(count(&pdf, code.as_bytes()), 1, "code {code} absent du PDF");
    }
    // Un seul sachet → une seule page.
    let f1 = seed(&db, 1).await;
    let token1 = make_secretary_token(f1.user_id, f1.cabinet_id);
    let (status, _, pdf1) = call_raw(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/sterilization/cycles/{}/labels.pdf", f1.cycle_id),
        &token1,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(count(&pdf1, b"/Type /Page "), 1);

    // shelf_life_days hors bornes → 422.
    let (status, body) = call(
        state_with(app_pool().await),
        "GET",
        &format!(
            "/v1/sterilization/cycles/{}/labels.pdf?shelf_life_days=0",
            f.cycle_id
        ),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["code"], "validation_error");

    cleanup(&db, &f1).await;
    cleanup(&db, &f).await;
}

#[tokio::test]
async fn labels_pdf_is_tenant_isolated() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f_a = seed(&db, 2).await;
    let f_b = seed(&db, 0).await;
    let token_b = make_secretary_token(f_b.user_id, f_b.cabinet_id);

    let (status, body) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/sterilization/cycles/{}/labels.pdf", f_a.cycle_id),
        &token_b,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["code"], "not_found");

    cleanup(&db, &f_b).await;
    cleanup(&db, &f_a).await;
}

// ── Usage par scan : happy path + idempotence + conflit + audit ───────────────

#[tokio::test]
async fn use_pouch_happy_path_is_idempotent_and_audited() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, 2).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);
    let code = f.pouch_codes[0].clone();

    // Premier scan : patient + séance.
    let (status, body) = use_pouch(
        &token,
        &code,
        json!({"patient_id": f.patient_id, "consultation_id": f.session_id}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["code"], code);
    assert_eq!(body["cycle_id"], f.cycle_id.to_string());
    assert_eq!(body["patient_id"], f.patient_id.to_string());
    assert_eq!(body["consultation_id"], f.session_id.to_string());
    assert_eq!(body["already_used"], false);
    let used_at = body["used_at"].as_str().unwrap().to_string();
    let pouch_id = Uuid::parse_str(body["pouch_id"].as_str().unwrap()).unwrap();

    // Rejeu identique : 200, même used_at, already_used=true, pas de doublon.
    let (status, replay) = use_pouch(
        &token,
        &code,
        json!({"patient_id": f.patient_id, "consultation_id": f.session_id}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{replay}");
    assert_eq!(replay["already_used"], true);
    assert_eq!(replay["used_at"], used_at);
    assert_eq!(replay["pouch_id"], pouch_id.to_string());

    // État DB : une seule ligne, patient/séance/used_by posés.
    let row = sqlx::query(
        "SELECT patient_id, consultation_id, used_by FROM sterilized_pouch \
         WHERE cabinet_id = $1 AND code = $2",
    )
    .bind(f.cabinet_id)
    .bind(&code)
    .fetch_one(&db)
    .await
    .unwrap();
    use sqlx::Row;
    assert_eq!(row.get::<Uuid, _>("patient_id"), f.patient_id);
    assert_eq!(row.get::<Uuid, _>("consultation_id"), f.session_id);
    assert_eq!(row.get::<Uuid, _>("used_by"), f.user_id);
    let pouch_count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM sterilized_pouch WHERE cabinet_id = $1 AND code = $2",
    )
    .bind(f.cabinet_id)
    .bind(&code)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(pouch_count, 1);

    // Audit : une seule entrée (le rejeu n'écrit rien).
    let audit_count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit_log \
         WHERE cabinet_id = $1 AND action = 'use_sterilized_pouch' \
           AND entity = 'sterilized_pouch' AND entity_id = $2",
    )
    .bind(f.cabinet_id)
    .bind(pouch_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audit_count, 1);

    // Second sachet : scan sans séance, puis complétion avec la séance.
    let code2 = f.pouch_codes[1].clone();
    let (status, body) = use_pouch(&token, &code2, json!({"patient_id": f.patient_id})).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(body.get("consultation_id").is_none());
    let (status, body) = use_pouch(
        &token,
        &code2,
        json!({"patient_id": f.patient_id, "consultation_id": f.session_id}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["already_used"], true);
    assert_eq!(body["consultation_id"], f.session_id.to_string());

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn use_pouch_conflicts_and_not_found() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, 1).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);
    let code = f.pouch_codes[0].clone();

    // Code inconnu → 404.
    let (status, body) = use_pouch(
        &token,
        "DM-INCONNU-000",
        json!({"patient_id": f.patient_id}),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["code"], "not_found");

    // Patient inconnu → 404.
    let (status, _) = use_pouch(&token, &code, json!({"patient_id": Uuid::new_v4()})).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Séance d'un autre patient → 422.
    let (status, body) = use_pouch(
        &token,
        &code,
        json!({"patient_id": f.other_patient_id, "consultation_id": f.session_id}),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["code"], "validation_error");

    // Premier usage OK.
    let (status, _) = use_pouch(&token, &code, json!({"patient_id": f.patient_id})).await;
    assert_eq!(status, StatusCode::OK);

    // Même sachet sur un AUTRE patient → 409 pouch_already_used.
    let (status, body) = use_pouch(&token, &code, json!({"patient_id": f.other_patient_id})).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "pouch_already_used");

    // Le rattachement initial est intact.
    let patient: Uuid = sqlx::query_scalar(
        "SELECT patient_id FROM sterilized_pouch WHERE cabinet_id = $1 AND code = $2",
    )
    .bind(f.cabinet_id)
    .bind(&code)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(patient, f.patient_id);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn use_pouch_is_tenant_isolated() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f_a = seed(&db, 1).await;
    let f_b = seed(&db, 0).await;
    let token_b = make_secretary_token(f_b.user_id, f_b.cabinet_id);
    let code = f_a.pouch_codes[0].clone();

    // Cabinet B ne voit pas le sachet de A (RLS) → 404, rien n'est écrit.
    let (status, body) = use_pouch(&token_b, &code, json!({"patient_id": f_b.patient_id})).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["code"], "not_found");

    // Cabinet A ne peut pas rattacher son sachet à un patient de B → 404.
    let token_a = make_secretary_token(f_a.user_id, f_a.cabinet_id);
    let (status, _) = use_pouch(&token_a, &code, json!({"patient_id": f_b.patient_id})).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let patient: Option<Uuid> = sqlx::query_scalar(
        "SELECT patient_id FROM sterilized_pouch WHERE cabinet_id = $1 AND code = $2",
    )
    .bind(f_a.cabinet_id)
    .bind(&code)
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(patient.is_none());

    cleanup(&db, &f_b).await;
    cleanup(&db, &f_a).await;
}

// ── #7243 : un sachet d'un cycle `non_conforme` ne doit jamais être posable ───
// sur un patient — même signal que celui imprimé sur l'étiquette.

#[tokio::test]
async fn use_pouch_rejects_non_conforme_cycle() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, 1).await;
    sqlx::query("UPDATE sterilization_cycle SET status = 'non_conforme' WHERE id = $1")
        .bind(f.cycle_id)
        .execute(&db)
        .await
        .unwrap();
    let token = make_secretary_token(f.user_id, f.cabinet_id);
    let code = f.pouch_codes[0].clone();

    let (status, body) = use_pouch(&token, &code, json!({"patient_id": f.patient_id})).await;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    assert_eq!(body["code"], "pouch_cycle_non_conforme");

    // Rien n'est écrit : le sachet reste vierge.
    let patient: Option<Uuid> = sqlx::query_scalar(
        "SELECT patient_id FROM sterilized_pouch WHERE cabinet_id = $1 AND code = $2",
    )
    .bind(f.cabinet_id)
    .bind(&code)
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(patient.is_none());

    cleanup(&db, &f).await;
}

// ── #7244 : la traçabilité patient/séance posée par `use` doit être relue ─────
// par `GET /v1/cabinet/sterilization-cycles/{id}/pouches` (migration 0269),
// sinon un sachet utilisé ressort comme neuf.

#[tokio::test]
async fn used_pouch_is_visible_in_cycle_pouches_list() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, 2).await;
    let token = make_secretary_token(f.user_id, f.cabinet_id);
    let used_code = f.pouch_codes[0].clone();
    let unused_code = f.pouch_codes[1].clone();

    let (status, use_body) = use_pouch(
        &token,
        &used_code,
        json!({"patient_id": f.patient_id, "consultation_id": f.session_id}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{use_body}");

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/sterilization-cycles/{}/pouches", f.cycle_id),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{list}");
    let pouches = list.as_array().unwrap();

    let used = pouches
        .iter()
        .find(|p| p["code"] == used_code)
        .expect("sachet utilisé absent de la liste");
    assert_eq!(
        used["patient_id"],
        f.patient_id.to_string(),
        "patient_id doit être relu (#7244), pas seulement écrit"
    );
    assert_eq!(used["consultation_id"], f.session_id.to_string());
    assert_eq!(used["used_at"], use_body["used_at"]);
    assert_eq!(used["used_by"], f.user_id.to_string());

    let unused = pouches
        .iter()
        .find(|p| p["code"] == unused_code)
        .expect("sachet non utilisé absent de la liste");
    assert!(unused["patient_id"].is_null());
    assert!(unused["used_at"].is_null());
    assert!(unused["used_by"].is_null());

    cleanup(&db, &f).await;
}
