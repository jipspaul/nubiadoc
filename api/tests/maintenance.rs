//! Tests d'intégration : `/v1/cabinet/equipment` et
//! `/v1/cabinet/maintenance/*` (#7167) — CRUD équipements/tickets, photos,
//! compteurs dashboard, et e-mail au technicien à la création d'un ticket
//! (mailer mocké — `RecordingMailer`, pas d'appel réseau réel).

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, Mailer, StubMailer};

const JWT_SECRET: &str = "test-secret-maintenance";

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

/// Un appel capté par `RecordingMailer::send_maintenance_ticket_created`.
#[derive(Clone, Debug)]
struct RecordedTicketEmail {
    to: String,
    title: String,
    description: Option<String>,
    photo_filenames: Vec<String>,
}

/// `Mailer` mocké — enregistre les appels au lieu d'un vrai envoi (Brevo/réseau).
#[derive(Default)]
struct RecordingMailer {
    sent: Mutex<Vec<RecordedTicketEmail>>,
}

impl Mailer for RecordingMailer {
    fn send_password_reset(&self, _to: &str, _token: &str) {}
    fn send_invite(&self, _to: &str, _token: &str) {}
    fn send_access_request(&self, _to: &str, _requester_name: &str) {}
    fn send_invoice_reminder(&self, _to: &str, _balance_due_cents: i64) {}
    fn send_maintenance_ticket_created(
        &self,
        to: &str,
        title: &str,
        description: Option<&str>,
        photo_filenames: &[String],
    ) {
        self.sent.lock().unwrap().push(RecordedTicketEmail {
            to: to.to_string(),
            title: title.to_string(),
            description: description.map(|s| s.to_string()),
            photo_filenames: photo_filenames.to_vec(),
        });
    }
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

fn state_with_recording_mailer(db: PgPool, mailer: Arc<RecordingMailer>) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer,
    }
}

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900
}

fn make_pro_token(sub: Uuid, cabinet_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": "secretary",
            "exp": exp(),
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    staff_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let staff_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(staff_id)
    .bind(format!("maintenance-staff+{staff_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet Maintenance Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES ($1, $2, 'secretary')",
    )
    .bind(cabinet_id)
    .bind(staff_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        staff_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM maintenance_ticket_photo WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM maintenance_ticket WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM document WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_equipment WHERE cabinet_id = $1")
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
        .bind(f.staff_id)
        .execute(db)
        .await
        .ok();
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

/// Corps multipart/form-data minimal : un champ `file`.
fn make_photo_multipart(boundary: &str, file_bytes: &[u8], filename: &str, mime: &str) -> Vec<u8> {
    let mut body: Vec<u8> = Vec::new();
    body.extend_from_slice(format!("--{boundary}\r\n").as_bytes());
    body.extend_from_slice(
        format!("Content-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\n")
            .as_bytes(),
    );
    body.extend_from_slice(format!("Content-Type: {mime}\r\n\r\n").as_bytes());
    body.extend_from_slice(file_bytes);
    body.extend_from_slice(b"\r\n");
    body.extend_from_slice(format!("--{boundary}--\r\n").as_bytes());
    body
}

/// PNG 1×1 (en-tête réel, contenu tronqué : seul le nombre magique est vérifié).
fn sample_png(tag: &str) -> Vec<u8> {
    let mut bytes = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR".to_vec();
    bytes.extend_from_slice(tag.as_bytes());
    bytes
}

async fn upload_photo(state: AppState, token: &str, tag: &str) -> (Uuid, String) {
    let boundary = format!("boundary-maintenance-{tag}");
    let filename = format!("{tag}.png");
    let body = make_photo_multipart(&boundary, &sample_png(tag), &filename, "image/png");
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/maintenance/photos")
                .header("Authorization", format!("Bearer {token}"))
                .header(
                    "Content-Type",
                    format!("multipart/form-data; boundary={boundary}"),
                )
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let document_id = Uuid::parse_str(json["document_id"].as_str().unwrap()).unwrap();
    (document_id, filename)
}

// ── Équipements : CRUD ────────────────────────────────────────────────────

#[tokio::test]
async fn create_equipment_appears_in_list_then_can_be_patched_and_deleted() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.staff_id, f.cabinet_id);

    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/equipment",
        &token,
        Some(json!({
            "label": "Autoclave B1",
            "category": "sterilisation",
            "technician_email": "technicien@prestataire.test",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let equipment_id = created["id"].as_str().unwrap().to_string();

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/equipment",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let items = list.as_array().unwrap();
    assert!(items.iter().any(|e| e["id"] == equipment_id));

    let (status, patched) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/equipment/{equipment_id}"),
        &token,
        Some(json!({"room": "Salle 2"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(patched["room"], "Salle 2");
    assert_eq!(
        patched["label"], "Autoclave B1",
        "champ non fourni inchangé"
    );

    let (status, _) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/equipment/{equipment_id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/equipment",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(!list
        .as_array()
        .unwrap()
        .iter()
        .any(|e| e["id"] == equipment_id));

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn create_equipment_rejects_invalid_technician_email() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.staff_id, f.cabinet_id);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/equipment",
        &token,
        Some(json!({
            "label": "Compresseur",
            "category": "air",
            "technician_email": "pas-un-email",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn delete_equipment_referenced_by_ticket_returns_conflict() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.staff_id, f.cabinet_id);

    let (_, equipment) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/equipment",
        &token,
        Some(json!({"label": "Fauteuil 1", "category": "fauteuil"})),
    )
    .await;
    let equipment_id = equipment["id"].as_str().unwrap().to_string();

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/maintenance/tickets",
        &token,
        Some(json!({"equipment_id": equipment_id, "title": "Grince"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, body) = call(
        state_with(app_pool().await),
        "DELETE",
        &format!("/v1/cabinet/equipment/{equipment_id}"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], json!("equipment_in_use"));

    cleanup(&db, &f).await;
}

// ── Tickets : création + e-mail au technicien (mailer mocké) ─────────────

#[tokio::test]
async fn create_ticket_with_assigned_email_dispatches_email_with_description() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.staff_id, f.cabinet_id);
    let mailer = Arc::new(RecordingMailer::default());

    let (status, created) = call(
        state_with_recording_mailer(app_pool().await, mailer.clone()),
        "POST",
        "/v1/cabinet/maintenance/tickets",
        &token,
        Some(json!({
            "title": "Autoclave en panne",
            "description": "Écran d'erreur E4, ne chauffe plus",
            "assigned_to_email": "technicien@prestataire.test",
            "priority": "urgent",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(created["status"], "open");
    assert_eq!(created["priority"], "urgent");

    {
        let sent = mailer.sent.lock().unwrap();
        assert_eq!(sent.len(), 1, "un e-mail doit être envoyé au technicien");
        let email = &sent[0];
        assert_eq!(email.to, "technicien@prestataire.test");
        assert_eq!(email.title, "Autoclave en panne");
        assert_eq!(
            email.description.as_deref(),
            Some("Écran d'erreur E4, ne chauffe plus")
        );
        assert!(email.photo_filenames.is_empty());
    }

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn create_ticket_falls_back_to_equipment_technician_email() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.staff_id, f.cabinet_id);

    let (_, equipment) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/equipment",
        &token,
        Some(json!({
            "label": "Compresseur",
            "category": "air",
            "technician_email": "sav@fournisseur.test",
        })),
    )
    .await;
    let equipment_id = equipment["id"].as_str().unwrap().to_string();

    let mailer = Arc::new(RecordingMailer::default());
    let (status, _) = call(
        state_with_recording_mailer(app_pool().await, mailer.clone()),
        "POST",
        "/v1/cabinet/maintenance/tickets",
        &token,
        Some(json!({"equipment_id": equipment_id, "title": "Fuite d'air"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    {
        let sent = mailer.sent.lock().unwrap();
        assert_eq!(sent.len(), 1);
        assert_eq!(sent[0].to, "sav@fournisseur.test");
    }

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn create_ticket_without_resolvable_email_sends_no_email() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.staff_id, f.cabinet_id);
    let mailer = Arc::new(RecordingMailer::default());

    let (status, _) = call(
        state_with_recording_mailer(app_pool().await, mailer.clone()),
        "POST",
        "/v1/cabinet/maintenance/tickets",
        &token,
        Some(json!({"title": "Ampoule scialytique grillée"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    assert!(
        mailer.sent.lock().unwrap().is_empty(),
        "aucune cible résolue -> pas d'e-mail (no-op loggé)"
    );

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn create_ticket_with_photos_attaches_and_emails_filenames() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.staff_id, f.cabinet_id);

    let (document_id, filename) =
        upload_photo(state_with(app_pool().await), &token, "ticket-photo").await;

    let mailer = Arc::new(RecordingMailer::default());
    let (status, created) = call(
        state_with_recording_mailer(app_pool().await, mailer.clone()),
        "POST",
        "/v1/cabinet/maintenance/tickets",
        &token,
        Some(json!({
            "title": "Fissure sur le fauteuil",
            "assigned_to_email": "technicien@prestataire.test",
            "photo_document_ids": [document_id],
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let ticket_id = created["id"].as_str().unwrap().to_string();

    {
        let sent = mailer.sent.lock().unwrap();
        assert_eq!(sent.len(), 1);
        assert_eq!(sent[0].photo_filenames, vec![filename.clone()]);
    }

    let (status, photos) = call(
        state_with(app_pool().await),
        "GET",
        &format!("/v1/cabinet/maintenance/tickets/{ticket_id}/photos"),
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let photos = photos.as_array().unwrap();
    assert_eq!(photos.len(), 1);
    assert_eq!(photos[0]["filename"], filename);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn create_ticket_with_unknown_photo_document_id_returns_validation_error() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.staff_id, f.cabinet_id);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/maintenance/tickets",
        &token,
        Some(json!({
            "title": "Photo introuvable",
            "photo_document_ids": [Uuid::new_v4()],
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Tickets : statut, filtres ──────────────────────────────────────────────

#[tokio::test]
async fn patch_ticket_resolves_then_blocks_further_status_change() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.staff_id, f.cabinet_id);

    let (_, created) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/maintenance/tickets",
        &token,
        Some(json!({"title": "Détartreur en panne"})),
    )
    .await;
    let ticket_id = created["id"].as_str().unwrap().to_string();

    let (status, patched) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/maintenance/tickets/{ticket_id}"),
        &token,
        Some(json!({"status": "resolved"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(patched["status"], "resolved");
    assert!(patched["resolved_at"].is_string());

    let (status, body) = call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/maintenance/tickets/{ticket_id}"),
        &token,
        Some(json!({"status": "open"})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], json!("invalid_status"));

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn list_tickets_filters_by_status() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.staff_id, f.cabinet_id);

    let (_, open_ticket) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/maintenance/tickets",
        &token,
        Some(json!({"title": "Ticket ouvert"})),
    )
    .await;
    let (_, resolved_ticket) = call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/maintenance/tickets",
        &token,
        Some(json!({"title": "Ticket à résoudre"})),
    )
    .await;
    let resolved_id = resolved_ticket["id"].as_str().unwrap().to_string();
    call(
        state_with(app_pool().await),
        "PATCH",
        &format!("/v1/cabinet/maintenance/tickets/{resolved_id}"),
        &token,
        Some(json!({"status": "resolved"})),
    )
    .await;

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/maintenance/tickets?status=open",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let ids: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["id"].as_str().unwrap())
        .collect();
    assert!(ids.contains(&open_ticket["id"].as_str().unwrap()));
    assert!(!ids.contains(&resolved_id.as_str()));

    cleanup(&db, &f).await;
}

// ── Dashboard : compteurs ──────────────────────────────────────────────────

#[tokio::test]
async fn maintenance_stats_counts_open_tickets_and_equipment_checks() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_pro_token(f.staff_id, f.cabinet_id);

    call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/maintenance/tickets",
        &token,
        Some(json!({"title": "Ticket ouvert pour stats"})),
    )
    .await;
    call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/equipment",
        &token,
        Some(json!({
            "label": "Radio panoramique",
            "category": "imagerie",
            "next_check_at": "2999-01-01",
        })),
    )
    .await;
    call(
        state_with(app_pool().await),
        "POST",
        "/v1/cabinet/equipment",
        &token,
        Some(json!({
            "label": "Compresseur vieux",
            "category": "air",
            "next_check_at": "2000-01-01",
        })),
    )
    .await;

    let (status, stats) = call(
        state_with(app_pool().await),
        "GET",
        "/v1/cabinet/maintenance/stats",
        &token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(stats["open_tickets"], json!(1));
    assert_eq!(stats["planned_checks"], json!(1));
    assert_eq!(stats["overdue_checks"], json!(1));

    cleanup(&db, &f).await;
}
