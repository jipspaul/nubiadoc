//! Tests d'intégration : cumuls interdits à l'ajout d'un acte CCAM (#4117,
//! table ccam_act_incompatibility, migration 0183)

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

const JWT_SECRET: &str = "test-secret-acts-incompatibility";
// HBQK002 < HBGD036 lexicographiquement ('H','B','G' < 'H','B','Q') — la
// paire canonisée (migration 0183, CHECK code_a < code_b) est donc
// (HBGD036, HBQK002).
const CODE_A: &str = "HBGD036";
const CODE_B: &str = "HBQK002";
const REASON: &str = "Cumul interdit : détartrage et bilan le même jour (test)";

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
}

async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();
    let bundle_code = format!("BUNDLE-INCOMPAT-{}", Uuid::new_v4().simple());

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
    .bind(format!("incompat-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Incompat Test', 'dentaire')",
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
         VALUES ($1, $2, 'Patient', 'Incompat')",
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

    tx.commit().await.unwrap();

    // ccam_act_incompatibility : catalogue public (nubia_owner, hors RLS tenant).
    sqlx::query(
        "INSERT INTO ccam_act_incompatibility (code_a, code_b, reason) VALUES ($1, $2, $3) \
         ON CONFLICT (code_a, code_b) DO NOTHING",
    )
    .bind(CODE_A)
    .bind(CODE_B)
    .bind(REASON)
    .execute(db)
    .await
    .unwrap();

    // Bundle contenant les deux codes incompatibles (#4117 x #4115).
    sqlx::query("INSERT INTO ccam_act_bundle (code, label) VALUES ($1, 'Bundle incompatible')")
        .bind(&bundle_code)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO ccam_act_bundle_item (bundle_code, ccam_code, qty) VALUES ($1, $2, 1)",
    )
    .bind(&bundle_code)
    .bind(CODE_A)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO ccam_act_bundle_item (bundle_code, ccam_code, qty) VALUES ($1, $2, 1)",
    )
    .bind(&bundle_code)
    .bind(CODE_B)
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
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    sqlx::query("DELETE FROM ccam_act_bundle_item WHERE bundle_code = $1")
        .bind(&f.bundle_code)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM ccam_act_bundle WHERE code = $1")
        .bind(&f.bundle_code)
        .execute(db)
        .await
        .ok();
    // PAS de DELETE sur ccam_act_incompatibility (CODE_A, CODE_B) ici (#4319) :
    // contrairement à bundle_code (aléatoire par appel), cette paire est un
    // COUPLE FIXE partagé par les 4 tests de ce fichier — `cargo test` les
    // exécute en parallèle par défaut. Un test qui la supprime en cleanup
    // pendant qu'un autre est encore entre son 1er et 2e POST fait
    // disparaître la règle sous ses pieds → `check_incompatibility` ne
    // matche plus rien → 201 au lieu de 422 (repro exacte de l'issue).
    // `insert_fixtures` la (re)crée déjà en idempotent (ON CONFLICT DO
    // NOTHING) ; la laisser vivre est sans risque (référentiel catalogue,
    // pas de donnée tenant).

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

async fn post_act(
    state: AppState,
    session_id: Uuid,
    token: &str,
    ccam_code: &str,
) -> (StatusCode, serde_json::Value) {
    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", session_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    // amount_cents requis en mode ccam_code depuis #4404.
                    json!({"ccam_code": ccam_code, "label": "Acte test", "amount_cents": 1000})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap_or_default();
    (status, body)
}

// ── Test 1 : deuxième acte incompatible avec le premier → 422 + motif ───────

#[tokio::test]
async fn add_act_incompatible_with_existing_returns_422_with_reason() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let (first_status, _) =
        post_act(make_state(app_pool().await), f.session_id, &token, CODE_A).await;
    assert_eq!(first_status, StatusCode::CREATED);

    let (second_status, second_body) =
        post_act(make_state(app_pool().await), f.session_id, &token, CODE_B).await;
    assert_eq!(second_status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(second_body["code"], "incompatible_acts");
    assert_eq!(second_body["reason"], REASON);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : ordre inverse — le premier acte ajouté est CODE_B → détecté aussi ─

#[tokio::test]
async fn add_act_incompatibility_detected_regardless_of_insertion_order() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let (first_status, _) =
        post_act(make_state(app_pool().await), f.session_id, &token, CODE_B).await;
    assert_eq!(first_status, StatusCode::CREATED);

    let (second_status, second_body) =
        post_act(make_state(app_pool().await), f.session_id, &token, CODE_A).await;
    assert_eq!(second_status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(second_body["code"], "incompatible_acts");

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : aucune règle d'incompatibilité → les deux actes coexistent ─────

#[tokio::test]
async fn add_act_without_incompatibility_rule_both_created() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let (first_status, _) = post_act(
        make_state(app_pool().await),
        f.session_id,
        &token,
        "HBQD001",
    )
    .await;
    assert_eq!(first_status, StatusCode::CREATED);

    let (second_status, _) = post_act(
        make_state(app_pool().await),
        f.session_id,
        &token,
        "HBQD003",
    )
    .await;
    assert_eq!(second_status, StatusCode::CREATED);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 4 : bundle avec deux items mutuellement incompatibles → 422, rollback ─

#[tokio::test]
async fn add_act_bundle_with_incompatible_items_returns_422_and_inserts_nothing() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/consultations/{}/acts", f.session_id))
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"bundle_code": f.bundle_code}).to_string(),
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
        "aucun item du bundle ne doit être inséré (422 bloquant)"
    );

    cleanup_fixtures(&db, &f).await;
}
