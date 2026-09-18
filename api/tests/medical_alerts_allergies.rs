//! Tests d'intégration (#6917, QA-20260913-6) : les allergies du dossier
//! médical — quelle que soit la forme de saisie (`{"text"}` issue du
//! questionnaire patient, `{"substance","severity"}` structurée, `{"name"}`/
//! `{"label"}`, chaîne nue) — remontent dans `medical_alerts` sur les DEUX
//! en-têtes cliniques : `GET /v1/cabinet/patients/:id/medical-record` et
//! `GET /v1/cabinet/consultations/:id`.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::{json, Value};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-medical-alerts-allergies";

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

fn make_patient_token(user_id: Uuid, account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
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
    patient_user_id: Uuid,
    account_id: Uuid,
    prac_user_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
    appt_id: Uuid,
    session_id: Uuid,
}

/// Un cabinet complet : praticien, patient (avec compte), RDV confirmé et
/// séance `in_progress` sur ce RDV — de quoi interroger les deux en-têtes.
async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("ma-patient+{}@nubia.test", patient_user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Marc', 'Alertes')",
    )
    .bind(account_id)
    .bind(patient_user_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("ma-prac+{}@nubia.test", prac_user_id))
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
         VALUES ($1, 'Cabinet Alertes Test', 'dentaire')",
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Marc', 'Alertes', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now(), now() + interval '30 minutes', 'confirmed', 'contrôle')",
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

    Fixtures {
        cabinet_id,
        patient_user_id,
        account_id,
        prac_user_id,
        prac_id,
        patient_id,
        appt_id,
        session_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
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
    sqlx::query("DELETE FROM audit_log WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM medical_record WHERE patient_id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_session WHERE id = $1")
        .bind(f.session_id)
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
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(f.patient_user_id)
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

// ── Helpers HTTP ──────────────────────────────────────────────────────────

async fn get_json(state: AppState, uri: String, token: &str) -> (StatusCode, Value) {
    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(uri)
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: Value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap()
    };
    (status, v)
}

async fn get_medical_record(state: AppState, f: &Fixtures, token: &str) -> (StatusCode, Value) {
    get_json(
        state,
        format!("/v1/cabinet/patients/{}/medical-record", f.patient_id),
        token,
    )
    .await
}

async fn get_consultation(state: AppState, f: &Fixtures, token: &str) -> (StatusCode, Value) {
    get_json(
        state,
        format!("/v1/cabinet/consultations/{}", f.session_id),
        token,
    )
    .await
}

/// Soumet un questionnaire patient (`POST` brouillon + `PATCH submit:true`)
/// puis le fait valider/importer par le praticien (`/review`).
async fn submit_and_review_questionnaire(state: &AppState, f: &Fixtures, payload: Value) {
    let patient_token = make_patient_token(f.patient_user_id, f.account_id);
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {patient_token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "payload": payload}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri("/v1/account/medical-questionnaire")
                .header("Authorization", format!("Bearer {patient_token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"cabinet_id": f.cabinet_id, "submit": true}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    let resp = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/patients/{}/medical-questionnaire/review",
                    f.patient_id
                ))
                .header("Authorization", format!("Bearer {prac_token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
}

fn allergy_alerts(v: &Value) -> Vec<&Value> {
    v["medical_alerts"]
        .as_array()
        .map(|a| a.iter().filter(|x| x["kind"] == "allergie").collect())
        .unwrap_or_default()
}

// ── Test 1 : questionnaire patient (texte libre) → alerte sur les 2 en-têtes ──

#[tokio::test]
async fn questionnaire_allergy_free_text_surfaces_in_medical_alerts() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let state = make_state(app_pool().await);
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    submit_and_review_questionnaire(
        &state,
        &f,
        json!({
            "antecedents": "",
            "allergies": "Pénicilline",
            "traitements_en_cours": "",
            "ald": false
        }),
    )
    .await;

    // En-tête du dossier patient.
    let (status, record) = get_medical_record(state.clone(), &f, &prac_token).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(record["allergies"][0]["text"], "Pénicilline");
    let alerts = allergy_alerts(&record);
    assert_eq!(
        alerts.len(),
        1,
        "l'allergie du questionnaire doit produire une alerte: {record}"
    );
    assert_eq!(alerts[0]["label"], "Pénicilline");

    // En-tête de la consultation au fauteuil.
    let (status, consult) = get_consultation(state.clone(), &f, &prac_token).await;
    assert_eq!(status, StatusCode::OK);
    let alerts = allergy_alerts(&consult);
    assert_eq!(alerts.len(), 1, "même alerte au fauteuil: {consult}");
    assert_eq!(alerts[0]["label"], "Pénicilline");

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : questionnaire avec liste + objets structurés (substance/severity) ──

#[tokio::test]
async fn questionnaire_allergy_list_and_structured_entries_surface_with_severity() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let state = make_state(app_pool().await);
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    submit_and_review_questionnaire(
        &state,
        &f,
        json!({
            "allergies": [
                "latex",
                { "substance": "pénicilline", "severity": "high" },
                { "text": "iode" },
                { "name": "" },
                ""
            ]
        }),
    )
    .await;

    let (status, record) = get_medical_record(state.clone(), &f, &prac_token).await;
    assert_eq!(status, StatusCode::OK);
    // Les entrées vides sont ignorées, les autres conservées avec leur source.
    let raw = record["allergies"].as_array().unwrap();
    assert_eq!(raw.len(), 3, "{record}");
    assert!(raw.iter().all(|e| e["source"] == "questionnaire_patient"));

    let alerts = allergy_alerts(&record);
    let labels: Vec<&str> = alerts
        .iter()
        .map(|a| a["label"].as_str().unwrap())
        .collect();
    assert_eq!(labels.len(), 3, "{record}");
    // La sévérité `high` remonte en tête.
    assert_eq!(labels[0], "pénicilline");
    assert_eq!(alerts[0]["severity"], "high");
    assert!(labels.contains(&"latex"));
    assert!(labels.contains(&"iode"));
    assert!(alerts
        .iter()
        .filter(|a| a["label"] != "pénicilline")
        .all(|a| a.get("severity").is_none()));

    let (status, consult) = get_consultation(state.clone(), &f, &prac_token).await;
    assert_eq!(status, StatusCode::OK);
    let alerts = allergy_alerts(&consult);
    assert_eq!(alerts.len(), 3, "{consult}");
    assert_eq!(alerts[0]["label"], "pénicilline");
    assert_eq!(alerts[0]["severity"], "high");

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : dossier écrit en base avec les formes réellement observées (QA) ──

#[tokio::test]
async fn stored_record_substance_and_text_entries_surface_in_medical_alerts() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let state = make_state(app_pool().await);
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    // Exactement le dossier de Marc Dubois dans le rapport QA.
    let ciphertext = format!(
        "STUB_ENC:{}",
        json!({
            "allergies": [
                { "severity": "high", "substance": "pénicilline" },
                { "source": "questionnaire_patient", "text": "latex" },
                { "label": "Aspirine" },
                { "name": "Iode" },
                "Nickel"
            ],
            "treatments": ["QA-med"],
            "history": null,
            "medico_legal": { "ald": true }
        })
    );
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO medical_record (cabinet_id, patient_id, data_ciphertext, data_key_ref) \
             VALUES ($1, $2, $3, 'stub-key-ref')",
        )
        .bind(f.cabinet_id)
        .bind(f.patient_id)
        .bind(ciphertext.as_bytes())
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    for (name, (status, v)) in [
        (
            "medical-record",
            get_medical_record(state.clone(), &f, &prac_token).await,
        ),
        (
            "consultation",
            get_consultation(state.clone(), &f, &prac_token).await,
        ),
    ] {
        assert_eq!(status, StatusCode::OK, "{name}");
        let all = v["medical_alerts"].as_array().unwrap();
        assert_eq!(all.len(), 6, "{name}: 5 allergies + ALD — {v}");
        let alerts = allergy_alerts(&v);
        let labels: Vec<&str> = alerts
            .iter()
            .map(|a| a["label"].as_str().unwrap())
            .collect();
        assert_eq!(
            labels,
            vec!["pénicilline", "latex", "Aspirine", "Iode", "Nickel"],
            "{name}"
        );
        assert_eq!(alerts[0]["severity"], "high", "{name}");
        // Le flag médico-légal reste présent, après les allergies.
        assert_eq!(all[5]["kind"], "medico_legal", "{name}");
        assert_eq!(all[5]["label"], "ALD", "{name}");
    }

    cleanup_fixtures(&db, &f).await;
}

// ── Test 4 : sans allergie → aucune alerte allergie ────────────────────────

#[tokio::test]
async fn questionnaire_without_allergy_produces_no_allergy_alert() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db).await;
    let state = make_state(app_pool().await);
    let prac_token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    submit_and_review_questionnaire(
        &state,
        &f,
        json!({
            "antecedents": "RAS",
            "allergies": "   ",
            "traitements_en_cours": "Doliprane",
            "ald": true
        }),
    )
    .await;

    let (status, record) = get_medical_record(state.clone(), &f, &prac_token).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(record["allergies"], json!([]));
    assert!(allergy_alerts(&record).is_empty(), "{record}");
    // Seul le flag ALD produit une alerte.
    assert_eq!(record["medical_alerts"].as_array().unwrap().len(), 1);
    assert_eq!(record["medical_alerts"][0]["kind"], "medico_legal");

    let (status, consult) = get_consultation(state.clone(), &f, &prac_token).await;
    assert_eq!(status, StatusCode::OK);
    assert!(allergy_alerts(&consult).is_empty(), "{consult}");

    cleanup_fixtures(&db, &f).await;
}

// ── Test 5 : isolation tenant ───────────────────────────────────────────────

#[tokio::test]
async fn medical_alerts_are_isolated_per_tenant() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fa = insert_fixtures(&db).await;
    let fb = insert_fixtures(&db).await;
    let state = make_state(app_pool().await);
    let token_a = make_practitioner_token(fa.prac_user_id, fa.cabinet_id);
    let token_b = make_practitioner_token(fb.prac_user_id, fb.cabinet_id);

    submit_and_review_questionnaire(&state, &fa, json!({"allergies": "Pénicilline"})).await;
    submit_and_review_questionnaire(&state, &fb, json!({"allergies": ""})).await;

    // Le cabinet A voit son allergie.
    let (status, record_a) = get_medical_record(state.clone(), &fa, &token_a).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(allergy_alerts(&record_a).len(), 1);

    // Le cabinet B ne voit rien du patient A (ni fiche, ni séance).
    let (status, _) = get_medical_record(state.clone(), &fa, &token_b).await;
    assert!(
        status == StatusCode::FORBIDDEN || status == StatusCode::NOT_FOUND,
        "cross-tenant medical-record: {status}"
    );
    let (status, _) = get_consultation(state.clone(), &fa, &token_b).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Et son propre patient n'hérite d'aucune alerte du cabinet A.
    let (status, record_b) = get_medical_record(state.clone(), &fb, &token_b).await;
    assert_eq!(status, StatusCode::OK);
    assert!(allergy_alerts(&record_b).is_empty(), "{record_b}");
    let (status, consult_b) = get_consultation(state.clone(), &fb, &token_b).await;
    assert_eq!(status, StatusCode::OK);
    assert!(allergy_alerts(&consult_b).is_empty(), "{consult_b}");

    cleanup_fixtures(&db, &fa).await;
    cleanup_fixtures(&db, &fb).await;
}
