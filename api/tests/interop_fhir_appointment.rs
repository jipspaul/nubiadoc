//! Tests d'intégration : `/v1/interop/fhir/Appointment` (lot A6, lecture/écriture FHIR).
//!
//! Suit le même pattern que `interop_oauth_token.rs` (skip silencieux si
//! `APP_DATABASE_URL`/`DATABASE_URL` ne sont pas configurées) et que
//! `appointments_post.rs` (fixtures via owner pool, RLS bypass). Le token
//! interop est fabriqué directement (pas via `POST /v1/interop/oauth/token`) :
//! l'extracteur `InteropClaims` ne fait qu'une vérification de signature +
//! `aud`, pas de lookup `interop_client` — pas besoin de cette table ici.
//!
//! Couvre particulièrement, comme demandé pour ce lot booking-adjacent :
//! le conflit de double-booking (23P01 → 409), le rejeu d'idempotence (clé
//! identique/empreinte différente → 409, clé+empreinte identiques → même
//! RDV sans doublon), et le rejet d'une transition de statut illégale.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-interop-fhir-appointment";

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

fn state_sync(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

/// Fabrique un JWT `aud:"interop"` valide directement (pas de lookup DB dans
/// l'extracteur `InteropClaims` — seule la signature + `aud` sont vérifiées).
fn make_interop_jwt(cabinet_id: Uuid, scope: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &json!({
            "sub": Uuid::new_v4(),
            "aud": "interop",
            "client_id": "client-fhir-appointment-test",
            "cabinet_id": cabinet_id,
            "scope": scope,
            "exp": exp,
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Cabinet + praticien + patient minimal (owner pool, bypass RLS — même
/// pattern que `appointments_post.rs`).
struct Fixture {
    cabinet_id: Uuid,
    patient_id: Uuid,
    practitioner_id: Uuid,
}

async fn setup_fixture(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query("INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')")
        .bind(prac_user_id)
        .bind(format!("interop-fhir-appt+{prac_user_id}@nubia.test"))
        .execute(db)
        .await
        .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, $2)")
        .bind(cabinet_id)
        .bind(format!("Cabinet interop FHIR test {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES ($1, $2, 'Jean', 'Dupont')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        patient_id,
        practitioner_id,
    }
}

async fn insert_appointment(
    db: &PgPool,
    cabinet_id: Uuid,
    patient_id: Uuid,
    practitioner_id: Uuid,
    status: &str,
    starts_at: &str,
    ends_at: &str,
) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO appointment (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(starts_at.parse::<chrono::DateTime<chrono::Utc>>().unwrap())
    .bind(ends_at.parse::<chrono::DateTime<chrono::Utc>>().unwrap())
    .bind(status)
    .execute(db)
    .await
    .unwrap();
    id
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query(
        "DELETE FROM app_user WHERE id IN (SELECT user_id FROM practitioner WHERE cabinet_id = $1)",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

async fn send(state: AppState, req: Request<Body>) -> (StatusCode, Value) {
    let resp = app(state).oneshot(req).await.unwrap();
    let status = resp.status();
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&bytes).unwrap();
    (status, json)
}

// ── GET /v1/interop/fhir/Appointment/:id ────────────────────────────────────

#[tokio::test]
async fn get_appointment_returns_mapped_fhir_resource() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let appt_id = insert_appointment(
        &owner,
        fx.cabinet_id,
        fx.patient_id,
        fx.practitioner_id,
        "confirmed",
        "2031-01-15T09:00:00Z",
        "2031-01-15T09:30:00Z",
    )
    .await;

    let token = make_interop_jwt(fx.cabinet_id, "appointments:read");
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("GET")
            .uri(format!("/v1/interop/fhir/Appointment/{appt_id}"))
            .header("Authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["resourceType"], "Appointment");
    assert_eq!(body["id"], appt_id.to_string());
    assert_eq!(body["status"], "booked"); // confirmed -> booked
    assert_eq!(body["start"], "2031-01-15T09:00:00+00:00");
    let participants = body["participant"].as_array().unwrap();
    assert_eq!(participants.len(), 2);

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn get_appointment_from_another_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx_a = setup_fixture(&owner).await;
    let fx_b = setup_fixture(&owner).await;
    let appt_id = insert_appointment(
        &owner,
        fx_a.cabinet_id,
        fx_a.patient_id,
        fx_a.practitioner_id,
        "confirmed",
        "2031-02-01T09:00:00Z",
        "2031-02-01T09:30:00Z",
    )
    .await;

    // Token du cabinet B tente de lire un RDV du cabinet A.
    let token = make_interop_jwt(fx_b.cabinet_id, "appointments:read");
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("GET")
            .uri(format!("/v1/interop/fhir/Appointment/{appt_id}"))
            .header("Authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["resourceType"], "OperationOutcome");
    assert_eq!(body["issue"][0]["code"], "not-found");

    cleanup(&owner, fx_a.cabinet_id).await;
    cleanup(&owner, fx_b.cabinet_id).await;
}

#[tokio::test]
async fn get_appointment_without_scope_returns_403_operation_outcome() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let appt_id = insert_appointment(
        &owner,
        fx.cabinet_id,
        fx.patient_id,
        fx.practitioner_id,
        "confirmed",
        "2031-02-05T09:00:00Z",
        "2031-02-05T09:30:00Z",
    )
    .await;

    let token = make_interop_jwt(fx.cabinet_id, "directory:read"); // pas appointments:read
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("GET")
            .uri(format!("/v1/interop/fhir/Appointment/{appt_id}"))
            .header("Authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(body["resourceType"], "OperationOutcome");
    assert_eq!(body["issue"][0]["code"], "forbidden");

    cleanup(&owner, fx.cabinet_id).await;
}

// ── GET /v1/interop/fhir/Appointment (search) ───────────────────────────────

#[tokio::test]
async fn search_appointments_filters_by_patient_and_date_range() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let other_patient_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES ($1, $2, 'Autre', 'Patient')",
    )
    .bind(other_patient_id)
    .bind(fx.cabinet_id)
    .execute(&owner)
    .await
    .unwrap();

    insert_appointment(
        &owner,
        fx.cabinet_id,
        fx.patient_id,
        fx.practitioner_id,
        "confirmed",
        "2031-03-01T09:00:00Z",
        "2031-03-01T09:30:00Z",
    )
    .await;
    insert_appointment(
        &owner,
        fx.cabinet_id,
        other_patient_id,
        fx.practitioner_id,
        "confirmed",
        "2031-03-10T09:00:00Z",
        "2031-03-10T09:30:00Z",
    )
    .await;

    let token = make_interop_jwt(fx.cabinet_id, "appointments:read");

    // Filtre par patient : un seul résultat.
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("GET")
            .uri(format!(
                "/v1/interop/fhir/Appointment?patient={}",
                fx.patient_id
            ))
            .header("Authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["resourceType"], "Bundle");
    assert_eq!(body["total"], 1);

    // Filtre par fenêtre de dates : seul le RDV du 2031-03-10 doit matcher.
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("GET")
            .uri("/v1/interop/fhir/Appointment?date_from=2031-03-05T00:00:00Z&date_to=2031-03-15T00:00:00Z")
            .header("Authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["total"], 1);
    assert_eq!(
        body["entry"][0]["resource"]["participant"][0]["actor"]["reference"],
        format!("Patient/{other_patient_id}")
    );

    cleanup(&owner, fx.cabinet_id).await;
}

// ── POST /v1/interop/fhir/Appointment ───────────────────────────────────────

fn fhir_appointment_body(patient_id: Uuid, practitioner_id: Uuid, start: &str, end: &str) -> Value {
    json!({
        "resourceType": "Appointment",
        "start": start,
        "end": end,
        "participant": [
            {"actor": {"reference": format!("Patient/{patient_id}")}},
            {"actor": {"reference": format!("Practitioner/{practitioner_id}")}}
        ]
    })
}

#[tokio::test]
async fn create_appointment_requires_idempotency_key_header() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let token = make_interop_jwt(fx.cabinet_id, "appointments:write");

    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Appointment")
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .body(Body::from(
                serde_json::to_string(&fhir_appointment_body(
                    fx.patient_id,
                    fx.practitioner_id,
                    "2031-04-01T09:00:00Z",
                    "2031-04-01T09:30:00Z",
                ))
                .unwrap(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["resourceType"], "OperationOutcome");

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn create_appointment_happy_path_sets_status_confirmed() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let token = make_interop_jwt(fx.cabinet_id, "appointments:write");

    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Appointment")
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .header("Idempotency-Key", "idem-happy-1")
            .body(Body::from(
                serde_json::to_string(&fhir_appointment_body(
                    fx.patient_id,
                    fx.practitioner_id,
                    "2031-04-02T09:00:00Z",
                    "2031-04-02T09:30:00Z",
                ))
                .unwrap(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(body["resourceType"], "Appointment");
    // Statut initial = confirmed ("booked" en FHIR), pas "requested"/"pending" :
    // un partenaire qui pousse un RDV affirme une réservation déjà actée.
    assert_eq!(body["status"], "booked");

    let appt_id: Uuid = body["id"].as_str().unwrap().parse().unwrap();
    let row = sqlx::query("SELECT status FROM appointment WHERE id = $1")
        .bind(appt_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    let db_status: String = row.try_get("status").unwrap();
    assert_eq!(db_status, "confirmed");

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn create_appointment_idempotent_replay_returns_same_appointment_without_duplicate() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let token = make_interop_jwt(fx.cabinet_id, "appointments:write");
    let payload = fhir_appointment_body(
        fx.patient_id,
        fx.practitioner_id,
        "2031-04-03T09:00:00Z",
        "2031-04-03T09:30:00Z",
    );

    let build_req = || {
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Appointment")
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .header("Idempotency-Key", "idem-replay-1")
            .body(Body::from(serde_json::to_string(&payload).unwrap()))
            .unwrap()
    };

    let (status1, body1) = send(state_sync(app_pool().await), build_req()).await;
    let (status2, body2) = send(state_sync(app_pool().await), build_req()).await;

    assert_eq!(status1, StatusCode::CREATED);
    assert_eq!(status2, StatusCode::CREATED);
    assert_eq!(body1["id"], body2["id"], "même RDV rejoué, pas de doublon");

    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM appointment WHERE cabinet_id = $1 AND idempotency_key = $2",
    )
    .bind(fx.cabinet_id)
    .bind("idem-replay-1")
    .fetch_one(&owner)
    .await
    .unwrap();
    assert_eq!(count, 1, "une seule ligne insérée malgré les deux appels");

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn create_appointment_idempotency_key_replayed_with_different_payload_returns_409() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let token = make_interop_jwt(fx.cabinet_id, "appointments:write");

    let (status1, _) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Appointment")
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .header("Idempotency-Key", "idem-conflict-1")
            .body(Body::from(
                serde_json::to_string(&fhir_appointment_body(
                    fx.patient_id,
                    fx.practitioner_id,
                    "2031-04-04T09:00:00Z",
                    "2031-04-04T09:30:00Z",
                ))
                .unwrap(),
            ))
            .unwrap(),
    )
    .await;
    assert_eq!(status1, StatusCode::CREATED);

    // Même clé, horaire différent -> empreinte différente -> 409.
    let (status2, body2) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Appointment")
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .header("Idempotency-Key", "idem-conflict-1")
            .body(Body::from(
                serde_json::to_string(&fhir_appointment_body(
                    fx.patient_id,
                    fx.practitioner_id,
                    "2031-04-05T09:00:00Z",
                    "2031-04-05T09:30:00Z",
                ))
                .unwrap(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status2, StatusCode::CONFLICT);
    assert_eq!(body2["resourceType"], "OperationOutcome");
    assert_eq!(body2["issue"][0]["code"], "conflict");

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn create_appointment_double_booking_returns_409_conflict() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let token = make_interop_jwt(fx.cabinet_id, "appointments:write");

    let (status1, _) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Appointment")
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .header("Idempotency-Key", "idem-double-book-1")
            .body(Body::from(
                serde_json::to_string(&fhir_appointment_body(
                    fx.patient_id,
                    fx.practitioner_id,
                    "2031-04-06T09:00:00Z",
                    "2031-04-06T09:30:00Z",
                ))
                .unwrap(),
            ))
            .unwrap(),
    )
    .await;
    assert_eq!(status1, StatusCode::CREATED);

    // Créneau chevauchant, même praticien, clé d'idempotence DIFFÉRENTE :
    // ce n'est pas un rejeu, c'est une vraie 2e réservation en conflit.
    let (status2, body2) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Appointment")
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .header("Idempotency-Key", "idem-double-book-2")
            .body(Body::from(
                serde_json::to_string(&fhir_appointment_body(
                    fx.patient_id,
                    fx.practitioner_id,
                    "2031-04-06T09:15:00Z",
                    "2031-04-06T09:45:00Z",
                ))
                .unwrap(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status2, StatusCode::CONFLICT);
    assert_eq!(body2["resourceType"], "OperationOutcome");
    assert_eq!(body2["issue"][0]["code"], "conflict");

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn create_appointment_unknown_patient_returns_422() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let token = make_interop_jwt(fx.cabinet_id, "appointments:write");

    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Appointment")
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .header("Idempotency-Key", "idem-unknown-patient-1")
            .body(Body::from(
                serde_json::to_string(&fhir_appointment_body(
                    Uuid::new_v4(), // patient inexistant
                    fx.practitioner_id,
                    "2031-04-07T09:00:00Z",
                    "2031-04-07T09:30:00Z",
                ))
                .unwrap(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["resourceType"], "OperationOutcome");
    assert_eq!(body["issue"][0]["code"], "business-rule");

    cleanup(&owner, fx.cabinet_id).await;
}

// ── PATCH /v1/interop/fhir/Appointment/:id ──────────────────────────────────

#[tokio::test]
async fn patch_appointment_legal_transition_confirmed_to_cancelled_succeeds() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let appt_id = insert_appointment(
        &owner,
        fx.cabinet_id,
        fx.patient_id,
        fx.practitioner_id,
        "confirmed",
        "2031-05-01T09:00:00Z",
        "2031-05-01T09:30:00Z",
    )
    .await;

    let token = make_interop_jwt(fx.cabinet_id, "appointments:write");
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("PATCH")
            .uri(format!("/v1/interop/fhir/Appointment/{appt_id}"))
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .body(Body::from(
                serde_json::to_string(&json!({"status": "cancelled"})).unwrap(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "cancelled");

    let row = sqlx::query("SELECT status FROM appointment WHERE id = $1")
        .bind(appt_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    let db_status: String = row.try_get("status").unwrap();
    assert_eq!(db_status, "cancelled");

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn patch_appointment_illegal_transition_done_to_requested_is_rejected() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let appt_id = insert_appointment(
        &owner,
        fx.cabinet_id,
        fx.patient_id,
        fx.practitioner_id,
        "done",
        "2031-05-02T09:00:00Z",
        "2031-05-02T09:30:00Z",
    )
    .await;

    let token = make_interop_jwt(fx.cabinet_id, "appointments:write");
    // "pending" = mapping FHIR de "requested" (cf. internal_status_to_fhir).
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("PATCH")
            .uri(format!("/v1/interop/fhir/Appointment/{appt_id}"))
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .body(Body::from(
                serde_json::to_string(&json!({"status": "pending"})).unwrap(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["resourceType"], "OperationOutcome");
    assert_eq!(body["issue"][0]["code"], "business-rule");

    // Statut DB inchangé.
    let row = sqlx::query("SELECT status FROM appointment WHERE id = $1")
        .bind(appt_id)
        .fetch_one(&owner)
        .await
        .unwrap();
    let db_status: String = row.try_get("status").unwrap();
    assert_eq!(db_status, "done");

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn patch_appointment_without_scope_returns_403() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;
    let appt_id = insert_appointment(
        &owner,
        fx.cabinet_id,
        fx.patient_id,
        fx.practitioner_id,
        "confirmed",
        "2031-05-03T09:00:00Z",
        "2031-05-03T09:30:00Z",
    )
    .await;

    let token = make_interop_jwt(fx.cabinet_id, "appointments:read"); // read seul, pas write
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("PATCH")
            .uri(format!("/v1/interop/fhir/Appointment/{appt_id}"))
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .body(Body::from(
                serde_json::to_string(&json!({"status": "cancelled"})).unwrap(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(body["resourceType"], "OperationOutcome");

    cleanup(&owner, fx.cabinet_id).await;
}
