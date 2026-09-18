//! Tests d'intégration : `/v1/cabinet/tasks` — CRUD des tâches internes du
//! cabinet + notification à l'assigné (#7211), et son raccourci
//! `POST /v1/appointments/:id/tasks`.

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

const JWT_SECRET: &str = "test-secret-cabinet-tasks";

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

fn state_with(db: PgPool) -> AppState {
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

fn make_pro_token(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": role,
            "exp": exp(),
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_patient_token(sub: Uuid, account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "patient",
            "account_id": account_id,
            "exp": exp(),
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    /// Secrétaire — crée les tâches.
    secretary_id: Uuid,
    /// Praticien — assigné des tâches.
    assignee_id: Uuid,
    patient_id: Uuid,
    appointment_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let secretary_id = Uuid::new_v4();
    let assignee_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appointment_id = Uuid::new_v4();

    for (user_id, tag) in [(secretary_id, "sec"), (assignee_id, "prac")] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind, first_name, last_name) \
             VALUES ($1, $2, 'hash', 'pro', $3, $4)",
        )
        .bind(user_id)
        .bind(format!("task-{tag}+{user_id}@nubia.test"))
        .bind("Jean")
        .bind("Dupont")
        .execute(db)
        .await
        .unwrap();
    }

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Tasks Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES ($1, $2, 'secretary')",
    )
    .bind(cabinet_id)
    .bind(secretary_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES ($1, $2, 'practitioner')",
    )
    .bind(cabinet_id)
    .bind(assignee_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(assignee_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'Task')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() + interval '1 day', \
                  now() + interval '1 day 30 minutes', 'confirmed', 'contrôle')",
    )
    .bind(appointment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        secretary_id,
        assignee_id,
        patient_id,
        appointment_id,
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
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
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

    for user_id in [f.secretary_id, f.assignee_id] {
        sqlx::query("DELETE FROM notification WHERE app_user_id = $1")
            .bind(user_id)
            .execute(db)
            .await
            .ok();
        sqlx::query("DELETE FROM app_user WHERE id = $1")
            .bind(user_id)
            .execute(db)
            .await
            .ok();
    }
}

async fn call(
    state: AppState,
    method: &str,
    uri: &str,
    token: &str,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
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
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

// ── Création + notification à l'assigné ──────────────────────────────────

#[tokio::test]
async fn create_task_with_assignee_notifies_and_appears_in_list() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.secretary_id, f.cabinet_id, "secretary");

    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/tasks",
        &token,
        Some(json!({
            "title": "Préparer le dossier",
            "assignee_user_id": f.assignee_id,
            "patient_id": f.patient_id,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let task_id = created["id"].as_str().unwrap().to_string();

    // L'assigné a bien reçu une notification in-app `task_assigned`.
    let notif_count: i64 = sqlx::query(
        "SELECT count(*) AS n FROM notification WHERE app_user_id = $1 AND kind = 'task_assigned'",
    )
    .bind(f.assignee_id)
    .fetch_one(&db)
    .await
    .unwrap()
    .try_get("n")
    .unwrap();
    assert_eq!(notif_count, 1, "l'assigné doit recevoir une notification");

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/tasks",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = list.as_array().unwrap();
    let item = items
        .iter()
        .find(|t| t["id"] == task_id)
        .expect("tâche présente dans la liste");
    assert_eq!(item["title"], "Préparer le dossier");
    assert_eq!(item["status"], "open");
    assert_eq!(item["assignee_user_id"], f.assignee_id.to_string());

    cleanup(&db, &f).await;
}

// ── Filtre par assignee_id / statut ───────────────────────────────────────

#[tokio::test]
async fn list_filters_by_assignee_and_status() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.secretary_id, f.cabinet_id, "secretary");

    let (_, unassigned) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/tasks",
        &token,
        Some(json!({ "title": "Tâche sans assigné" })),
    )
    .await;
    let unassigned_id = unassigned["id"].as_str().unwrap().to_string();

    let (_, assigned) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/tasks",
        &token,
        Some(json!({
            "title": "Tâche assignée",
            "assignee_user_id": f.assignee_id,
        })),
    )
    .await;
    let assigned_id = assigned["id"].as_str().unwrap().to_string();

    let (status, filtered) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/tasks?assignee_id={}", f.assignee_id),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let ids: Vec<String> = filtered
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["id"].as_str().unwrap().to_string())
        .collect();
    assert!(ids.contains(&assigned_id));
    assert!(!ids.contains(&unassigned_id));

    let (status, _) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/tasks?status=bogus",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── PATCH puis clôture ────────────────────────────────────────────────────

#[tokio::test]
async fn patch_then_complete_transitions_status() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.secretary_id, f.cabinet_id, "secretary");

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/tasks",
        &token,
        Some(json!({ "title": "Rappeler le labo" })),
    )
    .await;
    let task_id = created["id"].as_str().unwrap().to_string();

    let (status, patched) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/tasks/{task_id}"),
        &token,
        Some(json!({ "assignee_user_id": f.assignee_id, "due_date": "2026-10-01" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(patched["status"], "open");

    let (status, completed) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/tasks/{task_id}/complete"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(completed["status"], "done");

    // Une tâche déjà close ne peut pas être re-close → 409.
    let (status, resp) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/cabinet/tasks/{task_id}/complete"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(resp["code"], "invalid_status");

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/tasks?status=done",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let item = list
        .as_array()
        .unwrap()
        .iter()
        .find(|t| t["id"] == task_id)
        .expect("tâche close présente dans le filtre status=done");
    assert_eq!(item["due_date"], "2026-10-01");
    assert!(item["done_at"].is_string());

    cleanup(&db, &f).await;
}

// ── Raccourci POST /v1/appointments/:id/tasks ─────────────────────────────

#[tokio::test]
async fn create_from_appointment_prefills_patient_and_appointment() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.secretary_id, f.cabinet_id, "secretary");

    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        &format!("/v1/appointments/{}/tasks", f.appointment_id),
        &token,
        Some(json!({
            "title": "Prépare le guide chirurgical",
            "assignee_user_id": f.assignee_id,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let task_id = created["id"].as_str().unwrap().to_string();

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/tasks",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let item = list
        .as_array()
        .unwrap()
        .iter()
        .find(|t| t["id"] == task_id)
        .expect("tâche créée depuis le RDV");
    assert_eq!(item["patient_id"], f.patient_id.to_string());
    assert_eq!(item["appointment_id"], f.appointment_id.to_string());

    cleanup(&db, &f).await;
}

// ── RBAC : un patient n'accède pas aux tâches du cabinet ──────────────────

#[tokio::test]
async fn patient_token_forbidden() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_patient_token(Uuid::new_v4(), Uuid::new_v4());

    let (status, _) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/tasks",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/tasks",
        &token,
        Some(json!({ "title": "Interdit" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    cleanup(&db, &f).await;
}

// ── Validation : titre vide → 422, assigné hors cabinet → 404 ────────────

#[tokio::test]
async fn blank_title_returns_422_and_foreign_assignee_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.secretary_id, f.cabinet_id, "secretary");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/tasks",
        &token,
        Some(json!({ "title": "   " })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/tasks",
        &token,
        Some(json!({
            "title": "Assigné inconnu",
            "assignee_user_id": Uuid::new_v4(),
        })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}
