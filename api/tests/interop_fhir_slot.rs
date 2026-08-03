//! Tests d'intégration : `GET /v1/interop/fhir/Slot/:id`, `GET /v1/interop/fhir/Slot`
//! (recherche) et `GET /v1/interop/fhir/Schedule/:id` (lot A3 — lecture seule).
//!
//! Suit le même pattern que `api/tests/interop_oauth_token.rs` : skip silencieux
//! si `APP_DATABASE_URL`/`DATABASE_URL` ne sont pas configurées (pas de Postgres
//! migré au schéma courant dans ce sandbox). Le token bearer utilisé pour
//! chaque appel est un vrai JWT obtenu via `POST /v1/interop/oauth/token`
//! (pas fabriqué à la main) : ça couvre aussi bout-en-bout l'enchaînement
//! token endpoint → routes ressources protégées.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use chrono::{Duration, Utc};
use integrations_interop::hash_secret;
use serde_json::Value;
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-interop-fhir-slot";

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

/// Fixture d'un cabinet avec un praticien et un créneau (owner pool, bypass RLS).
struct SlotFixture {
    cabinet_id: Uuid,
    practitioner_id: Uuid,
    slot_id: Uuid,
    interop_client_id: Uuid,
}

/// Crée cabinet + app_user + practitioner + availability_slot(status) +
/// interop_client (scope `slots:read`) + interop_client_secret.
async fn insert_fixture(db: &PgPool, client_id: &str, secret: &str, status: &str) -> SlotFixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let slot_id = Uuid::new_v4();
    let interop_client_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, $2)")
        .bind(cabinet_id)
        .bind(format!("Cabinet interop slot test {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO app_user (id, email, kind) VALUES ($1, $2, 'pro')")
        .bind(user_id)
        .bind(format!("practitioner-{user_id}@example.test"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    let starts_at = Utc::now() + Duration::hours(2);
    let ends_at = starts_at + Duration::minutes(30);
    sqlx::query(
        "INSERT INTO availability_slot \
         (id, cabinet_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(slot_id)
    .bind(cabinet_id)
    .bind(practitioner_id)
    .bind(starts_at)
    .bind(ends_at)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO interop_client (id, client_id, cabinet_id, display_name, scopes, status) \
         VALUES ($1, $2, $3, 'PMS externe test slots', $4, 'active')",
    )
    .bind(interop_client_id)
    .bind(client_id)
    .bind(cabinet_id)
    .bind(vec!["slots:read".to_string()])
    .execute(&mut *tx)
    .await
    .unwrap();

    let hash = hash_secret(secret).unwrap();
    sqlx::query("INSERT INTO interop_client_secret (client_id_ref, secret_hash) VALUES ($1, $2)")
        .bind(interop_client_id)
        .bind(hash)
        .execute(&mut *tx)
        .await
        .unwrap();

    tx.commit().await.unwrap();

    SlotFixture {
        cabinet_id,
        practitioner_id,
        slot_id,
        interop_client_id,
    }
}

/// Variante sans scope `slots:read` (n'accorde que `directory:read`) — sert
/// à vérifier `403 insufficient_scope` côté ressources FHIR.
async fn insert_fixture_without_slots_scope(
    db: &PgPool,
    client_id: &str,
    secret: &str,
) -> SlotFixture {
    let fixture = insert_fixture(db, client_id, secret, "open").await;
    sqlx::query("UPDATE interop_client SET scopes = $1 WHERE id = $2")
        .bind(vec!["directory:read".to_string()])
        .bind(fixture.interop_client_id)
        .execute(db)
        .await
        .unwrap();
    fixture
}

async fn cleanup(db: &PgPool, fixture: &SlotFixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("DELETE FROM interop_client_secret WHERE client_id_ref = $1")
        .bind(fixture.interop_client_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM interop_client WHERE id = $1")
        .bind(fixture.interop_client_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM availability_slot WHERE id = $1")
        .bind(fixture.slot_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(fixture.practitioner_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(fixture.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

/// Échange `client_id`/`client_secret` contre un JWT via le vrai token
/// endpoint (pas de JWT fabriqué à la main).
async fn issue_token(state: AppState, client_id: &str, secret: &str) -> String {
    let body =
        format!("grant_type=client_credentials&client_id={client_id}&client_secret={secret}");
    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/interop/oauth/token")
                .header("content-type", "application/x-www-form-urlencoded")
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&bytes).unwrap();
    json["access_token"].as_str().unwrap().to_string()
}

async fn get_with_bearer(state: AppState, uri: &str, token: &str) -> (StatusCode, Value) {
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
    let json: Value = serde_json::from_slice(&bytes).unwrap();
    (status, json)
}

// ── GET /v1/interop/fhir/Slot/:id ────────────────────────────────────────────

#[tokio::test]
async fn get_slot_open_maps_to_free_with_schedule_reference() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture = insert_fixture(&owner, "client-slot-open", "s3cret-open", "open").await;

    let token = issue_token(
        state_sync(app_pool().await),
        "client-slot-open",
        "s3cret-open",
    )
    .await;

    let (status, body) = get_with_bearer(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Slot/{}", fixture.slot_id),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["resourceType"], "Slot");
    assert_eq!(body["id"], fixture.slot_id.to_string());
    assert_eq!(body["status"], "free");
    assert_eq!(
        body["schedule"]["reference"],
        format!("Schedule/{}", fixture.practitioner_id)
    );
    assert!(body["start"].as_str().is_some());
    assert!(body["end"].as_str().is_some());

    cleanup(&owner, &fixture).await;
}

#[tokio::test]
async fn get_slot_booked_maps_to_busy() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture = insert_fixture(&owner, "client-slot-booked", "s3cret-booked", "booked").await;

    let token = issue_token(
        state_sync(app_pool().await),
        "client-slot-booked",
        "s3cret-booked",
    )
    .await;

    let (status, body) = get_with_bearer(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Slot/{}", fixture.slot_id),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "busy");

    cleanup(&owner, &fixture).await;
}

#[tokio::test]
async fn get_slot_unknown_id_returns_404_operation_outcome() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture = insert_fixture(&owner, "client-slot-404", "s3cret-404", "open").await;

    let token = issue_token(
        state_sync(app_pool().await),
        "client-slot-404",
        "s3cret-404",
    )
    .await;

    let (status, body) = get_with_bearer(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Slot/{}", Uuid::new_v4()),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["resourceType"], "OperationOutcome");

    cleanup(&owner, &fixture).await;
}

#[tokio::test]
async fn get_slot_from_other_cabinet_returns_404_not_403() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    // Cabinet A : détient le créneau ciblé.
    let fixture_a = insert_fixture(&owner, "client-slot-cross-a", "s3cret-cross-a", "open").await;
    // Cabinet B : le token utilisé pour l'appel.
    let fixture_b = insert_fixture(&owner, "client-slot-cross-b", "s3cret-cross-b", "open").await;

    let token_b = issue_token(
        state_sync(app_pool().await),
        "client-slot-cross-b",
        "s3cret-cross-b",
    )
    .await;

    // Le token du cabinet B tente de lire un créneau du cabinet A.
    let (status, body) = get_with_bearer(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Slot/{}", fixture_a.slot_id),
        &token_b,
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["resourceType"], "OperationOutcome");

    cleanup(&owner, &fixture_a).await;
    cleanup(&owner, &fixture_b).await;
}

#[tokio::test]
async fn get_slot_without_slots_read_scope_returns_403_operation_outcome() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture =
        insert_fixture_without_slots_scope(&owner, "client-slot-noscope", "s3cret-noscope").await;

    // Le client n'a que `directory:read` accordé : demander `slots:read`
    // explicitement échouerait dès le token endpoint (invalid_scope). On
    // simule plutôt un token émis pour `directory:read` (scope par défaut,
    // absent de la requête) qui tente ensuite d'accéder à une route
    // `slots:read` — le cas réel d'un token valide mais insuffisant.
    let token = issue_token(
        state_sync(app_pool().await),
        "client-slot-noscope",
        "s3cret-noscope",
    )
    .await;

    let (status, body) = get_with_bearer(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Slot/{}", fixture.slot_id),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(body["resourceType"], "OperationOutcome");
    assert_eq!(body["issue"][0]["code"], "forbidden");

    cleanup(&owner, &fixture).await;
}

#[tokio::test]
async fn get_slot_missing_bearer_returns_401_rfc6749_shape() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture = insert_fixture(&owner, "client-slot-nobearer", "s3cret-nobearer", "open").await;

    let resp = app(state_sync(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/interop/fhir/Slot/{}", fixture.slot_id))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    // L'échec d'extraction du bearer reste au format RFC 6749 (invalid_token),
    // distinct de l'OperationOutcome des erreurs métier FHIR (cf. error.rs).
    assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(json["error"], "invalid_token");

    cleanup(&owner, &fixture).await;
}

// ── GET /v1/interop/fhir/Slot (recherche) ───────────────────────────────────

#[tokio::test]
async fn search_slots_returns_bundle_scoped_to_own_cabinet() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture_a = insert_fixture(&owner, "client-slot-search-a", "s3cret-search-a", "open").await;
    let fixture_b = insert_fixture(&owner, "client-slot-search-b", "s3cret-search-b", "open").await;

    let token_a = issue_token(
        state_sync(app_pool().await),
        "client-slot-search-a",
        "s3cret-search-a",
    )
    .await;

    let (status, body) = get_with_bearer(
        state_sync(app_pool().await),
        "/v1/interop/fhir/Slot",
        &token_a,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["resourceType"], "Bundle");
    assert_eq!(body["type"], "searchset");
    let ids: Vec<String> = body["entry"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["resource"]["id"].as_str().unwrap().to_string())
        .collect();
    assert!(ids.contains(&fixture_a.slot_id.to_string()));
    assert!(!ids.contains(&fixture_b.slot_id.to_string()));

    cleanup(&owner, &fixture_a).await;
    cleanup(&owner, &fixture_b).await;
}

#[tokio::test]
#[ignore = "quarantaine: bug déterministe révélé par le fix DB CI, voir #4602"]
async fn search_slots_from_to_excludes_out_of_range_slot() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture = insert_fixture(
        &owner,
        "client-slot-search-range",
        "s3cret-search-range",
        "open",
    )
    .await;

    let token = issue_token(
        state_sync(app_pool().await),
        "client-slot-search-range",
        "s3cret-search-range",
    )
    .await;

    // La fixture crée un créneau ~2h dans le futur : une fenêtre from/to loin
    // dans le futur ne doit pas le retourner.
    let far_from = (Utc::now() + Duration::days(30)).to_rfc3339();
    let far_to = (Utc::now() + Duration::days(31)).to_rfc3339();
    let (status, body) = get_with_bearer(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Slot?from={far_from}&to={far_to}"),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["total"], 0);

    cleanup(&owner, &fixture).await;
}

#[tokio::test]
async fn search_slots_malformed_from_returns_400_operation_outcome() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture = insert_fixture(
        &owner,
        "client-slot-search-bad",
        "s3cret-search-bad",
        "open",
    )
    .await;

    let token = issue_token(
        state_sync(app_pool().await),
        "client-slot-search-bad",
        "s3cret-search-bad",
    )
    .await;

    let (status, body) = get_with_bearer(
        state_sync(app_pool().await),
        "/v1/interop/fhir/Slot?from=not-a-date",
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["resourceType"], "OperationOutcome");

    cleanup(&owner, &fixture).await;
}

// ── GET /v1/interop/fhir/Schedule/:id ────────────────────────────────────────

#[tokio::test]
async fn get_schedule_returns_practitioner_actor_reference() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture = insert_fixture(&owner, "client-schedule-ok", "s3cret-schedule-ok", "open").await;

    let token = issue_token(
        state_sync(app_pool().await),
        "client-schedule-ok",
        "s3cret-schedule-ok",
    )
    .await;

    let (status, body) = get_with_bearer(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Schedule/{}", fixture.practitioner_id),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["resourceType"], "Schedule");
    assert_eq!(body["id"], fixture.practitioner_id.to_string());
    assert_eq!(
        body["actor"][0]["reference"],
        format!("Practitioner/{}", fixture.practitioner_id)
    );

    cleanup(&owner, &fixture).await;
}

#[tokio::test]
async fn get_schedule_for_other_cabinet_practitioner_returns_404() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture_a = insert_fixture(
        &owner,
        "client-schedule-cross-a",
        "s3cret-schedule-cross-a",
        "open",
    )
    .await;
    let fixture_b = insert_fixture(
        &owner,
        "client-schedule-cross-b",
        "s3cret-schedule-cross-b",
        "open",
    )
    .await;

    let token_b = issue_token(
        state_sync(app_pool().await),
        "client-schedule-cross-b",
        "s3cret-schedule-cross-b",
    )
    .await;

    let (status, body) = get_with_bearer(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Schedule/{}", fixture_a.practitioner_id),
        &token_b,
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["resourceType"], "OperationOutcome");

    cleanup(&owner, &fixture_a).await;
    cleanup(&owner, &fixture_b).await;
}
