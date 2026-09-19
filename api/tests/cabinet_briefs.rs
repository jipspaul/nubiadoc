//! Tests d'intégration : briefs du cabinet (#7192)
//! - GET /v1/cabinet/briefs/day
//! - GET /v1/cabinet/briefs/week
//! - GET /v1/cabinet/briefs/prostheses
//! - variantes `.pdf`

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

const JWT_SECRET: &str = "test-secret-cabinet-briefs";

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

fn make_pro_token(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
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
            "role": role,
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
    prac_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("briefs+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Briefs Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query("INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES ($1, $2, 'practitioner')")
        .bind(cabinet_id)
        .bind(user_id)
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
        "INSERT INTO provider (id, practitioner_id, cabinet_id, user_id, display_name) \
         VALUES ($1, $2, $3, $4, 'Dr Briefs')",
    )
    .bind(provider_id)
    .bind(prac_id)
    .bind(cabinet_id)
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'Briefs')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
        patient_id,
        prac_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_task WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM lab_work_order WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_membership WHERE cabinet_id = $1")
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

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn call(
    state: AppState,
    method: &str,
    uri: &str,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method(method)
                .uri(uri)
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

async fn call_bytes(
    state: AppState,
    method: &str,
    uri: &str,
    token: &str,
) -> (StatusCode, Vec<u8>, Option<String>) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method(method)
                .uri(uri)
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let content_type = response
        .headers()
        .get(axum::http::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (status, bytes.to_vec(), content_type)
}

async fn insert_appointment(db: &PgPool, f: &Fixture, offset_interval: &str, motif: &str) -> Uuid {
    let appointment_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() + $5::interval, \
                  now() + $5::interval + interval '30 minutes', 'confirmed', $6)",
    )
    .bind(appointment_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .bind(f.prac_id)
    .bind(offset_interval)
    .bind(motif)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    appointment_id
}

// ── Test : RDV du jour groupé par praticien, avec motif ─────────────────────

#[tokio::test]
async fn day_brief_lists_appointment_grouped_by_practitioner_with_motif() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.user_id, f.cabinet_id, "secretary");

    insert_appointment(&db, &f, "1 hour", "Détartrage").await;

    let (status, body) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/briefs/day",
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["view"], "day");
    let groups = body["appointments_by_practitioner"].as_array().unwrap();
    assert_eq!(groups.len(), 1, "groups={groups:?}");
    assert_eq!(groups[0]["practitioner_id"], f.prac_id.to_string());
    assert_eq!(groups[0]["practitioner_display_name"], "Dr Briefs");
    let appts = groups[0]["appointments"].as_array().unwrap();
    assert_eq!(appts.len(), 1);
    assert_eq!(appts[0]["motif"], "Détartrage");
    assert_eq!(appts[0]["patient_display_name"], "Patient Briefs");

    cleanup(&db, &f).await;
}

/// Variante de [`insert_appointment`] ancrée sur le début de la journée
/// locale `Europe/Paris` plutôt que sur `now()` : les tests qui posent
/// plusieurs RDV "aujourd'hui" avec des offsets de quelques heures peuvent
/// franchir la frontière de minuit Paris selon l'heure d'exécution de la CI
/// (`now() + '2 hours'` lancé à 22h16 UTC en heure d'été = 00h16 Paris le
/// lendemain) — d'où des échecs intermittents non liés au code testé.
async fn insert_appointment_paris_today(
    db: &PgPool,
    f: &Fixture,
    offset_from_midnight: &str,
    motif: &str,
) -> Uuid {
    let appointment_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, \
                  (date_trunc('day', now() AT TIME ZONE 'Europe/Paris') AT TIME ZONE 'Europe/Paris') + $5::interval, \
                  (date_trunc('day', now() AT TIME ZONE 'Europe/Paris') AT TIME ZONE 'Europe/Paris') + $5::interval + interval '30 minutes', \
                  'confirmed', $6)",
    )
    .bind(appointment_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .bind(f.prac_id)
    .bind(offset_from_midnight)
    .bind(motif)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();
    appointment_id
}

// ── Test : RDV dans 3 jours absent du brief du jour, présent dans la semaine ─

#[tokio::test]
async fn week_brief_includes_appointment_beyond_today_day_brief_excludes_it() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.user_id, f.cabinet_id, "secretary");

    insert_appointment(&db, &f, "3 days", "Contrôle").await;

    let (status, day_body) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/briefs/day",
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        day_body["appointments_by_practitioner"]
            .as_array()
            .map(|a| a.is_empty())
            .unwrap_or(true),
        "day_body={day_body:?}"
    );

    let (status, week_body) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/briefs/week",
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(week_body["view"], "week");
    let groups = week_body["appointments_by_practitioner"]
        .as_array()
        .unwrap();
    assert_eq!(groups.len(), 1);
    assert_eq!(groups[0]["appointments"].as_array().unwrap().len(), 1);

    cleanup(&db, &f).await;
}

// ── Test : patient nouveau détecté au premier RDV, actes prévus agrégés ─────

#[tokio::test]
async fn day_brief_flags_new_patient_and_aggregates_planned_acts() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.user_id, f.cabinet_id, "practitioner");

    insert_appointment_paris_today(&db, &f, "10 hours", "Détartrage").await;
    insert_appointment_paris_today(&db, &f, "11 hours", "Détartrage").await;

    let (status, body) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/briefs/day",
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let new_patients = body["new_patients"].as_array().unwrap();
    assert_eq!(new_patients.len(), 1, "new_patients={new_patients:?}");
    assert_eq!(new_patients[0]["patient_id"], f.patient_id.to_string());

    let planned_acts = body["planned_acts"].as_array().unwrap();
    assert_eq!(planned_acts.len(), 1, "planned_acts={planned_acts:?}");
    assert_eq!(planned_acts[0]["motif"], "Détartrage");
    assert_eq!(planned_acts[0]["count"], 2);

    cleanup(&db, &f).await;
}

// ── Test : RDV annulé exclu du brief (RDV, nouveaux patients, actes) ────────

#[tokio::test]
async fn day_brief_excludes_cancelled_appointment() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.user_id, f.cabinet_id, "secretary");

    let appt_id = insert_appointment(&db, &f, "1 hour", "Détartrage").await;
    sqlx::query("UPDATE appointment SET status = 'cancelled' WHERE id = $1")
        .bind(appt_id)
        .execute(&db)
        .await
        .unwrap();

    let (status, body) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/briefs/day",
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(body["appointments_by_practitioner"]
        .as_array()
        .unwrap()
        .is_empty());
    assert!(body["new_patients"].as_array().unwrap().is_empty());
    assert!(body["planned_acts"].as_array().unwrap().is_empty());

    cleanup(&db, &f).await;
}

// ── Test : prothèses à poser — vue dédiée + fenêtre 7 jours ─────────────────

#[tokio::test]
async fn prostheses_brief_lists_lab_work_order_with_appointment_in_window() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.user_id, f.cabinet_id, "secretary");

    let tomorrow_appt = insert_appointment(&db, &f, "1 day", "Pose prothèse").await;
    let far_appt = insert_appointment(&db, &f, "10 days", "Pose prothèse").await;

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO lab_work_order \
             (id, cabinet_id, patient_id, appointment_id, lab_name, purchase_price_cents, status) \
             VALUES ($1, $2, $3, $4, 'Labo Briefs', 12000, 'sent')",
        )
        .bind(Uuid::new_v4())
        .bind(f.cabinet_id)
        .bind(f.patient_id)
        .bind(tomorrow_appt)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO lab_work_order \
             (id, cabinet_id, patient_id, appointment_id, lab_name, purchase_price_cents, status) \
             VALUES ($1, $2, $3, $4, 'Labo Trop Loin', 9000, 'sent')",
        )
        .bind(Uuid::new_v4())
        .bind(f.cabinet_id)
        .bind(f.patient_id)
        .bind(far_appt)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let (status, body) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/briefs/prostheses",
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["view"], "prostheses");
    let prostheses = body["prostheses_to_fit"].as_array().unwrap();
    assert_eq!(prostheses.len(), 1, "prostheses={prostheses:?}");
    assert_eq!(prostheses[0]["lab_name"], "Labo Briefs");
    // Vue focalisée : les autres sections restent vides.
    assert!(body["appointments_by_practitioner"]
        .as_array()
        .map(|a| a.is_empty())
        .unwrap_or(true));

    // Le PDF remis au labo (#7410) ne doit imprimer que la section
    // "prothèses à poser" — pas les 4 autres sections vidées à dessein,
    // dont l'impression affirmerait faussement "Aucun RDV", "Aucune tâche
    // ouverte", etc. sur la même fenêtre.
    let (pdf_status, pdf_bytes, pdf_content_type) = call_bytes(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/briefs/prostheses.pdf",
        &token,
    )
    .await;
    assert_eq!(pdf_status, StatusCode::OK);
    assert_eq!(pdf_content_type.as_deref(), Some("application/pdf"));
    // Note : les lettres accentuées sont écrites en WinAnsi (1 octet, ex.
    // 0xe2 pour "â") donc invisibles telles quelles après un décodage UTF-8
    // lossy — les substrings ci-dessous sont volontairement coupés avant le
    // premier caractère accentué de chaque phrase pour rester fiables.
    let pdf_text = String::from_utf8_lossy(&pdf_bytes);
    assert!(pdf_text.contains("PROTH"));
    assert!(pdf_text.contains("Labo Briefs"));
    assert!(!pdf_text.contains("Aucun RDV"));
    assert!(!pdf_text.contains("Aucun nouveau patient"));
    assert!(!pdf_text.contains("Aucun acte renseign"));
    assert!(!pdf_text.contains("ouverte."));
    assert!(!pdf_text.contains("RENDEZ-VOUS PAR PRATICIEN"));
    assert!(!pdf_text.contains("PATIENTS NOUVEAUX"));
    assert!(!pdf_text.contains("ACTES PR"));
    assert!(!pdf_text.contains("CHES OUVERTES"));

    cleanup(&db, &f).await;
}

// ── Test : tâche ouverte listée avec assigné, tâche clôturée absente ────────

#[tokio::test]
async fn day_brief_lists_open_task_with_assignee_excludes_done_task() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.user_id, f.cabinet_id, "secretary");

    let open_task_id = Uuid::new_v4();
    let done_task_id = Uuid::new_v4();
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO cabinet_task (id, cabinet_id, title, assignee_user_id, status, created_by) \
             VALUES ($1, $2, 'Rappeler labo', $3, 'open', $3)",
        )
        .bind(open_task_id)
        .bind(f.cabinet_id)
        .bind(f.user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO cabinet_task (id, cabinet_id, title, status, created_by, done_at) \
             VALUES ($1, $2, 'Déjà fait', 'done', $3, now())",
        )
        .bind(done_task_id)
        .bind(f.cabinet_id)
        .bind(f.user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let (status, body) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/briefs/day",
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let tasks = body["open_tasks"].as_array().unwrap();
    assert_eq!(tasks.len(), 1, "tasks={tasks:?}");
    assert_eq!(tasks[0]["id"], open_task_id.to_string());
    assert_eq!(tasks[0]["title"], "Rappeler labo");

    cleanup(&db, &f).await;
}

// ── Test : `?date=` invalide → 422 ───────────────────────────────────────────

#[tokio::test]
async fn invalid_date_param_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.user_id, f.cabinet_id, "secretary");

    let (status, _) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/briefs/day?date=not-a-date",
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test : export PDF renvoie un document PDF valide ────────────────────────

#[tokio::test]
async fn day_brief_pdf_returns_application_pdf() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.user_id, f.cabinet_id, "secretary");

    insert_appointment(&db, &f, "1 hour", "Détartrage").await;

    let (status, bytes, content_type) = call_bytes(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/briefs/day.pdf",
        &token,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(content_type.as_deref(), Some("application/pdf"));
    assert!(bytes.starts_with(b"%PDF-1.4"));
    assert!(bytes.ends_with(b"%%EOF"));

    cleanup(&db, &f).await;
}

// ── Test : rôle patient/absent de token → 403/401 ───────────────────────────

#[tokio::test]
async fn day_brief_requires_pro_token() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;

    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    let patient_token = encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "patient", "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let (status, _) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/briefs/day",
        &patient_token,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    cleanup(&db, &f).await;
}
