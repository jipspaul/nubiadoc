//! Tests d'intégration : `/v1/interop/fhir/Subscription` (lot A7, sync
//! sortante FHIR) + déclenchement de la livraison depuis
//! `POST /v1/interop/fhir/Appointment` (lot A6).
//!
//! Même pattern que `interop_fhir_appointment.rs` (skip silencieux si
//! `APP_DATABASE_URL`/`DATABASE_URL` ne sont pas configurées, token interop
//! fabriqué directement — pas de lookup `interop_client`).
//!
//! `INTEROP_SIGNING_KEY` est positionnée via `std::env::set_var` dans les
//! tests qui déclenchent une livraison — sûr sous `cargo nextest` (un
//! process par test), pas nécessairement sous `cargo test` (threads
//! partagés). Cf. `db/AGENTS.md`/`api/AGENTS.md` : `cargo nextest run` est
//! l'outil attendu pour ce dépôt.

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

const JWT_SECRET: &str = "test-secret-interop-fhir-subscription";

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
            "client_id": "client-fhir-subscription-test",
            "cabinet_id": cabinet_id,
            "scope": scope,
            "exp": exp,
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

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
        .bind(format!("interop-fhir-sub+{prac_user_id}@nubia.test"))
        .execute(db)
        .await
        .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, $2)")
        .bind(cabinet_id)
        .bind(format!("Cabinet interop FHIR sub test {cabinet_id}"))
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

/// Insère un abonnement directement (owner pool, bypass RLS) — évite de
/// dépendre de `POST /Subscription` pour préparer les fixtures des tests qui
/// portent sur la livraison.
async fn insert_subscription(
    db: &PgPool,
    cabinet_id: Uuid,
    criteria: &str,
    endpoint_url: &str,
) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO interop_subscription (id, cabinet_id, criteria, endpoint_url, secret_hash) \
         VALUES ($1, $2, $3, $4, 'fake-hash-not-used-for-signing')",
    )
    .bind(id)
    .bind(cabinet_id)
    .bind(criteria)
    .bind(endpoint_url)
    .execute(db)
    .await
    .unwrap();
    id
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query(
        "DELETE FROM interop_delivery WHERE subscription_id IN \
         (SELECT id FROM interop_subscription WHERE cabinet_id = $1)",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .ok();
    sqlx::query("DELETE FROM interop_subscription WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
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

// ── POST /v1/interop/fhir/Subscription ──────────────────────────────────────

#[tokio::test]
async fn post_subscription_returns_secret_once_and_never_again() {
    if !db_available() {
        return;
    }
    std::env::set_var("INTEROP_SIGNING_KEY", "test-signing-key-post-subscription");
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;

    let token = make_interop_jwt(fx.cabinet_id, "subscriptions:write");
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Subscription")
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .body(Body::from(
                json!({
                    "resourceType": "Subscription",
                    "criteria": "Appointment",
                    "channel": {"type": "rest-hook", "endpoint": "https://partner.example/hook"}
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(body["resourceType"], "Subscription");
    assert_eq!(body["criteria"], "Appointment");
    assert_eq!(body["status"], "active");
    let secret = body["secret"]
        .as_str()
        .expect("secret doit être présent sur la réponse de création")
        .to_string();
    assert!(!secret.is_empty());
    let sub_id: Uuid = body["id"].as_str().unwrap().parse().unwrap();

    // GET ne renvoie jamais le secret.
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("GET")
            .uri(format!("/v1/interop/fhir/Subscription/{sub_id}"))
            .header("Authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["resourceType"], "Subscription");
    assert!(
        body.get("secret").is_none(),
        "GET ne doit jamais ré-exposer le secret"
    );

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn post_subscription_without_scope_returns_403() {
    if !db_available() {
        return;
    }
    std::env::set_var("INTEROP_SIGNING_KEY", "test-signing-key-scope");
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;

    let token = make_interop_jwt(fx.cabinet_id, "appointments:read"); // pas subscriptions:write
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Subscription")
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .body(Body::from(
                json!({
                    "resourceType": "Subscription",
                    "criteria": "Appointment",
                    "channel": {"type": "rest-hook", "endpoint": "https://partner.example/hook"}
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(body["resourceType"], "OperationOutcome");

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn post_subscription_rejects_non_https_endpoint() {
    if !db_available() {
        return;
    }
    std::env::set_var("INTEROP_SIGNING_KEY", "test-signing-key-https");
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;

    let token = make_interop_jwt(fx.cabinet_id, "subscriptions:write");
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Subscription")
            .header("Authorization", format!("Bearer {token}"))
            .header("Content-Type", "application/json")
            .body(Body::from(
                json!({
                    "resourceType": "Subscription",
                    "criteria": "Appointment",
                    "channel": {"type": "rest-hook", "endpoint": "http://insecure.example/hook"}
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["resourceType"], "OperationOutcome");

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn get_subscription_from_another_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fx_a = setup_fixture(&owner).await;
    let fx_b = setup_fixture(&owner).await;
    let sub_id = insert_subscription(
        &owner,
        fx_a.cabinet_id,
        "Appointment",
        "https://partner.example/hook",
    )
    .await;

    let token = make_interop_jwt(fx_b.cabinet_id, "subscriptions:write");
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("GET")
            .uri(format!("/v1/interop/fhir/Subscription/{sub_id}"))
            .header("Authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["resourceType"], "OperationOutcome");

    cleanup(&owner, fx_a.cabinet_id).await;
    cleanup(&owner, fx_b.cabinet_id).await;
}

// ── Livraison déclenchée depuis POST /v1/interop/fhir/Appointment ──────────

#[tokio::test]
async fn post_appointment_triggers_interop_delivery_to_matching_subscription() {
    if !db_available() {
        return;
    }
    std::env::set_var("INTEROP_SIGNING_KEY", "test-signing-key-for-delivery");
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;

    // Endpoint volontairement injoignable (port 1 en local) : la tentative
    // échouera vite et sera enregistrée en `failed` — suffisant pour prouver
    // le câblage bout-en-bout (lookup + tentative + écriture interop_delivery)
    // sans dépendre d'un vrai récepteur HTTPS dans le test.
    let sub_id = insert_subscription(
        &owner,
        fx.cabinet_id,
        "Appointment",
        "https://127.0.0.1:1/interop-test-unreachable",
    )
    .await;

    let token = make_interop_jwt(fx.cabinet_id, "appointments:write");
    let (status, body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Appointment")
            .header("Authorization", format!("Bearer {token}"))
            .header("Idempotency-Key", format!("key-{}", Uuid::new_v4()))
            .header("Content-Type", "application/json")
            .body(Body::from(
                json!({
                    "start": "2031-02-01T10:00:00Z",
                    "end": "2031-02-01T10:30:00Z",
                    "participant": [
                        {"actor": {"reference": format!("Patient/{}", fx.patient_id)}},
                        {"actor": {"reference": format!("Practitioner/{}", fx.practitioner_id)}},
                    ]
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    let appt_id: Uuid = body["id"].as_str().unwrap().parse().unwrap();

    // La livraison est awaitée dans le handler avant la réponse HTTP : pas de
    // sleep nécessaire pour observer la ligne interop_delivery.
    let row = sqlx::query_as::<_, (String,)>(
        "SELECT status FROM interop_delivery WHERE subscription_id = $1 AND resource_id = $2",
    )
    .bind(sub_id)
    .bind(appt_id)
    .fetch_optional(&owner)
    .await
    .unwrap();

    assert!(
        row.is_some(),
        "interop_delivery devrait contenir une tentative pour cet abonnement"
    );
    assert_eq!(row.unwrap().0, "failed", "endpoint injoignable => failed");

    cleanup(&owner, fx.cabinet_id).await;
}

#[tokio::test]
async fn post_appointment_does_not_notify_subscription_with_different_criteria() {
    if !db_available() {
        return;
    }
    std::env::set_var("INTEROP_SIGNING_KEY", "test-signing-key-no-match");
    let owner = owner_pool().await;
    let fx = setup_fixture(&owner).await;

    // Abonné à un autre type de ressource : ne doit jamais être notifié.
    let sub_id = insert_subscription(
        &owner,
        fx.cabinet_id,
        "Patient",
        "https://127.0.0.1:1/interop-test-unreachable",
    )
    .await;

    let token = make_interop_jwt(fx.cabinet_id, "appointments:write");
    let (status, _body) = send(
        state_sync(app_pool().await),
        Request::builder()
            .method("POST")
            .uri("/v1/interop/fhir/Appointment")
            .header("Authorization", format!("Bearer {token}"))
            .header("Idempotency-Key", format!("key-{}", Uuid::new_v4()))
            .header("Content-Type", "application/json")
            .body(Body::from(
                json!({
                    "start": "2031-02-02T10:00:00Z",
                    "end": "2031-02-02T10:30:00Z",
                    "participant": [
                        {"actor": {"reference": format!("Patient/{}", fx.patient_id)}},
                        {"actor": {"reference": format!("Practitioner/{}", fx.practitioner_id)}},
                    ]
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);

    let count: (i64,) =
        sqlx::query_as("SELECT count(*) FROM interop_delivery WHERE subscription_id = $1")
            .bind(sub_id)
            .fetch_one(&owner)
            .await
            .unwrap();
    assert_eq!(
        count.0, 0,
        "un abonnement 'Patient' ne doit jamais être notifié pour un Appointment"
    );

    cleanup(&owner, fx.cabinet_id).await;
}
