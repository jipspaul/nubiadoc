//! Tests d'intégration : GET /v1/cabinet/consultations/:id

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-consultations";

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

/// Insère le jeu de fixtures minimal pour une séance de consultation.
/// Retourne `(cabinet_id, prac_id, prac_user_id, appt_id, session_id)`.
async fn insert_consultation_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();

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
    .bind(format!("consult-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet Consultation Test', 'dentaire')",
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
        "INSERT INTO provider \
         (cabinet_id, practitioner_id, user_id, display_name, specialite, is_listed, rpps_verified) \
         VALUES ($1, $2, $3, 'Dr. Test Consultation', 'dentaire', false, false)",
    )
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'Consultation')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now(), now() + interval '1 hour', 'confirmed', 'détartrage')",
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

    (cabinet_id, prac_id, prac_user_id, appt_id, session_id)
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    appt_id: Uuid,
    session_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM consultation_session WHERE id = $1")
        .bind(session_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query(
        "DELETE FROM consultation_act WHERE appointment_id IN \
                 (SELECT id FROM appointment WHERE cabinet_id = $1)",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE practitioner_id = $1")
        .bind(prac_id)
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

// ── Test 1 : praticien → 200 avec contexte complet ─────────────────────────────

#[tokio::test]
async fn consultation_get_practitioner_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, session_id) =
        insert_consultation_fixture(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/consultations/{}", session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    assert_eq!(v["id"], session_id.to_string());
    assert_eq!(v["appointment_id"], appt_id.to_string());
    assert_eq!(v["status"], "in_progress");
    assert!(
        v["started_at"].is_string(),
        "started_at doit être une chaîne"
    );
    assert_eq!(v["practitioner"]["id"], prac_id.to_string());
    assert_eq!(v["practitioner"]["display_name"], "Dr. Test Consultation");
    assert!(v["acts"].is_array(), "acts doit être un tableau");

    // Enrichissements vue fauteuil (lot 1) — fixture minimale :
    // patient + RDV présents, le reste absent/vide.
    assert_eq!(v["patient"]["display_name"], "Patient Consultation");
    assert!(
        v["patient"].get("age_years").is_none(),
        "age_years absent sans birth_date"
    );
    assert!(v["appointment"]["starts_at"].is_string());
    assert_eq!(v["appointment"]["motif"], "détartrage");
    assert_eq!(
        v["medical_alerts"],
        serde_json::json!([]),
        "medical_alerts doit être une liste vide sans dossier médical"
    );
    assert!(v.get("medical_history").is_none());
    assert!(v.get("current_phase").is_none());
    assert!(v.get("last_note").is_none());
    assert!(
        !String::from_utf8_lossy(&body).contains("birth_date"),
        "birth_date ne doit JAMAIS sortir (minimisation)"
    );

    cleanup_fixture(&db, cabinet_id, prac_id, prac_user_id, appt_id, session_id).await;
}

// ── Test 1bis : contexte enrichi complet (dossier, plan, dernière note) ───────

/// Chiffre une note de séance comme `consultations.rs::set_consultation_note` :
/// préfixe `STUB_ENC:` puis XOR 0xFF (≠ stub `medical_record`, JSON en clair).
fn stub_encrypt_session_note(plain: &str) -> Vec<u8> {
    let mut out = b"STUB_ENC:".to_vec();
    out.extend(plain.bytes().map(|b| b ^ 0xFF));
    out
}

#[tokio::test]
async fn consultation_get_returns_enriched_context() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, session_id) =
        insert_consultation_fixture(&db).await;

    // ── Enrichit la fixture : âge, dossier médical, plan 3 phases, note passée.
    let plan_id = Uuid::new_v4();
    let past_appt_id = Uuid::new_v4();
    let past_session_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    let patient_id: Uuid = sqlx::query_scalar("SELECT patient_id FROM appointment WHERE id = $1")
        .bind(appt_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();

    // Âge déterministe quel que soit le jour d'exécution : 48 ans révolus.
    sqlx::query(
        "UPDATE patient SET birth_date = (current_date - interval '48 years' - interval '40 days')::date \
         WHERE id = $1",
    )
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    let record_json = serde_json::json!({
        "allergies": ["latex"],
        "treatments": [],
        "history": "Bruxisme nocturne (gouttière)",
        "medico_legal": { "anticoagulants": true }
    });
    sqlx::query(
        "INSERT INTO medical_record (cabinet_id, patient_id, data_ciphertext, data_key_ref) \
         VALUES ($1, $2, $3, 'stub')",
    )
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(format!("STUB_ENC:{record_json}").into_bytes())
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO treatment_plan (id, cabinet_id, patient_id, practitioner_id, title, status) \
         VALUES ($1, $2, $3, $4, 'Pose implant 26', 'in_progress')",
    )
    .bind(plan_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO treatment_phase (cabinet_id, plan_id, position, title, status, planned_sessions, completed_sessions) VALUES \
         ($1, $2, 1, 'Extraction + greffe', 'done', 1, 1), \
         ($1, $2, 2, 'Chirurgie implantaire', 'in_progress', 3, 1), \
         ($1, $2, 3, 'Pilier + couronne céramique', 'requested', NULL, 0)",
    )
    .bind(cabinet_id)
    .bind(plan_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Séance passée terminée avec note → alimente `last_note`.
    sqlx::query(
        "INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, now() - interval '30 days', now() - interval '30 days' + interval '1 hour', 'done')",
    )
    .bind(past_appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO consultation_session \
         (id, cabinet_id, appointment_id, practitioner_id, status, started_at, completed_at, note_ciphertext, note_key_ref) \
         VALUES ($1, $2, $3, $4, 'completed', now() - interval '30 days', now() - interval '30 days', $5, 'stub')",
    )
    .bind(past_session_id)
    .bind(cabinet_id)
    .bind(past_appt_id)
    .bind(prac_id)
    .bind(stub_encrypt_session_note(
        "Densité osseuse suffisante en secteur 2.",
    ))
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/consultations/{}", session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();

    // Patient : âge calculé, jamais la date brute.
    assert_eq!(v["patient"]["id"], patient_id.to_string());
    assert_eq!(v["patient"]["age_years"], 48);
    assert!(!String::from_utf8_lossy(&body).contains("birth_date"));

    // Alertes passives : allergie saisie + flag structuré (jamais déduit).
    let alerts = v["medical_alerts"].as_array().unwrap();
    assert!(alerts
        .iter()
        .any(|a| a["kind"] == "allergie" && a["label"] == "latex"));
    assert!(alerts
        .iter()
        .any(|a| a["kind"] == "medico_legal" && a["label"] == "Anticoagulants"));
    assert_eq!(v["medical_history"], "Bruxisme nocturne (gouttière)");

    // Phase courante : la phase in_progress, pas la done ni la requested.
    assert_eq!(v["current_phase"]["plan_id"], plan_id.to_string());
    assert_eq!(v["current_phase"]["plan_title"], "Pose implant 26");
    assert_eq!(v["current_phase"]["phase_title"], "Chirurgie implantaire");
    assert_eq!(v["current_phase"]["position"], 2);
    assert_eq!(v["current_phase"]["phase_count"], 3);
    assert_eq!(v["current_phase"]["planned_sessions"], 3);
    assert_eq!(v["current_phase"]["completed_sessions"], 1);
    assert_eq!(
        v["current_phase"]["next_phase_title"],
        "Pilier + couronne céramique"
    );

    // Dernière note : déchiffrée + datée.
    assert_eq!(
        v["last_note"]["excerpt"],
        "Densité osseuse suffisante en secteur 2."
    );
    assert!(v["last_note"]["date"].is_string());

    // ── Cleanup (ordre FK) ─────────────────────────────────────────────────
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    for q in [
        "DELETE FROM consultation_session WHERE cabinet_id = $1",
        "DELETE FROM treatment_phase WHERE cabinet_id = $1",
        "DELETE FROM treatment_plan WHERE cabinet_id = $1",
        "DELETE FROM medical_record WHERE cabinet_id = $1",
    ] {
        sqlx::query(q).bind(cabinet_id).execute(&mut *tx).await.ok();
    }
    // Le RDV passé doit partir AVANT cleanup_fixture, sinon la FK
    // appointment→patient bloque la suppression du patient.
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(past_appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    cleanup_fixture(&db, cabinet_id, prac_id, prac_user_id, appt_id, session_id).await;
}

// ── Test 2 : secrétaire → 403 ──────────────────────────────────────────────────

#[tokio::test]
async fn consultation_get_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, session_id) =
        insert_consultation_fixture(&db).await;

    let secretary_id = Uuid::new_v4();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/consultations/{}", session_id))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_secretary_token(secretary_id, cabinet_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup_fixture(&db, cabinet_id, prac_id, prac_user_id, appt_id, session_id).await;
}

// ── Test 3 : praticien d'un autre cabinet → 404 (isolation tenant) ────────────

#[tokio::test]
async fn consultation_get_other_cabinet_provider_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, session_id) =
        insert_consultation_fixture(&db).await;

    // Praticien valide mais appartenant à un cabinet différent.
    let other_provider_user_id = Uuid::new_v4();
    let other_cabinet_id = Uuid::new_v4();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/consultations/{}", session_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(other_provider_user_id, other_cabinet_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // Le cabinet_id du token ne correspond pas → la requête SQL ne trouve rien → 404.
    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    cleanup_fixture(&db, cabinet_id, prac_id, prac_user_id, appt_id, session_id).await;
}

// ── Test 4 : token patient → 403 (extractor ProPractitionerClaims) ────────────

#[tokio::test]
async fn consultation_get_patient_token_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, prac_id, prac_user_id, appt_id, session_id) =
        insert_consultation_fixture(&db).await;

    let patient_user_id = Uuid::new_v4();

    // Token de type "patient" — rejeté par ProPractitionerClaims (kind != "pro").
    #[derive(serde::Serialize)]
    struct PatientClaims {
        sub: Uuid,
        kind: String,
        account_id: Uuid,
        exp: u64,
    }
    let exp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    let patient_token = jsonwebtoken::encode(
        &jsonwebtoken::Header::default(),
        &PatientClaims {
            sub: patient_user_id,
            kind: "patient".into(),
            account_id: patient_user_id,
            exp,
        },
        &jsonwebtoken::EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/consultations/{}", session_id))
                .header("Authorization", format!("Bearer {}", patient_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    cleanup_fixture(&db, cabinet_id, prac_id, prac_user_id, appt_id, session_id).await;
}

// ── Test 5 : sans token → 401 ──────────────────────────────────────────────────

#[tokio::test]
async fn consultation_get_no_token_returns_401() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // UUID fictif — 401 retourné avant toute requête DB.
    let session_id = Uuid::new_v4();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/consultations/{}", session_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 6 : séance inexistante → 404 ─────────────────────────────────────────

#[tokio::test]
async fn consultation_get_unknown_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let prac_user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("consult-404+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet 404 Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/consultations/{}", Uuid::new_v4()))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_practitioner_token(prac_user_id, cabinet_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    // Cleanup
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&db)
        .await
        .ok();
}
