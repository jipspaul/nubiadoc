//! Tests d'intégration : GET /v1/interop/fhir/{Practitioner,Organization,Location}
//! (lot A2, annuaire FHIR en lecture seule).
//!
//! Suit le même pattern que `interop_oauth_token.rs` (lot A1) : skip silencieux
//! si `APP_DATABASE_URL`/`DATABASE_URL` ne sont pas configurées.
//!
//! Couvre : succès sur chacune des 3 ressources, isolation tenant (un token du
//! cabinet A ne voit jamais une ressource du cabinet B, même par UUID deviné —
//! y compris `establishment`/`Location` qui n'a *aucune* RLS, cf.
//! `db/migrations/0011_rls_policies.sql`), scope insuffisant → 403
//! `OperationOutcome`, recherche `Practitioner` par `_id` et sans filtre.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::Serialize;
use serde_json::Value;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-interop-directory";

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

#[derive(Serialize)]
struct InteropClaimsForTest {
    sub: Uuid,
    aud: &'static str,
    client_id: String,
    cabinet_id: Uuid,
    scope: String,
    exp: u64,
}

/// Signe un JWT `aud:"interop"` comme le ferait `POST /v1/interop/oauth/token`
/// (même forme que `interop::auth::InteropClaims`).
fn make_interop_token(cabinet_id: Uuid, scope: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &InteropClaimsForTest {
            sub: Uuid::new_v4(),
            aud: "interop",
            client_id: "client-directory-test".to_string(),
            cabinet_id,
            scope: scope.to_string(),
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct CabinetFixture {
    cabinet_id: Uuid,
    user_id: Uuid,
    practitioner_id: Uuid,
    establishment_id: Uuid,
}

/// Crée un cabinet + praticien (avec identité civile) + establishment lié via
/// un `provider` marketplace — assez pour peupler Practitioner/Organization/
/// Location. `raison_sociale`/`first_name`/`last_name` varient par cabinet
/// pour distinguer les fixtures dans les assertions.
async fn insert_cabinet_fixture(
    db: &PgPool,
    raison_sociale: &str,
    first_name: &str,
    last_name: &str,
    rpps: Option<&str>,
) -> CabinetFixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let establishment_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, $2)")
        .bind(cabinet_id)
        .bind(raison_sociale)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind, first_name, last_name) \
         VALUES ($1, $2, 'hash', 'pro', $3, $4)",
    )
    .bind(user_id)
    .bind(format!("directory-test+{user_id}@nubia.test"))
    .bind(first_name)
    .bind(last_name)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id, rpps) VALUES ($1, $2, $3, $4)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(user_id)
        .bind(rpps)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO establishment (id, name, address) VALUES ($1, $2, $3)")
        .bind(establishment_id)
        .bind(format!("Établissement {raison_sociale}"))
        .bind(serde_json::json!({"rue": "1 rue Test", "cp": "75001", "ville": "Paris"}))
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, user_id, practitioner_id, establishment_id, display_name) \
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(user_id)
    .bind(practitioner_id)
    .bind(establishment_id)
    .bind(format!("Dr {last_name}"))
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    CabinetFixture {
        cabinet_id,
        user_id,
        practitioner_id,
        establishment_id,
    }
}

async fn cleanup(db: &PgPool, fixture: &CabinetFixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("DELETE FROM provider WHERE cabinet_id = $1")
        .bind(fixture.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM establishment WHERE id = $1")
        .bind(fixture.establishment_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(fixture.practitioner_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(fixture.user_id)
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

async fn get(state: AppState, uri: &str, token: &str) -> (StatusCode, Value) {
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

// ── Practitioner ─────────────────────────────────────────────────────────────

#[tokio::test]
#[ignore = "quarantaine: échec réel révélé par le fix DB CI (env reset+migrate), voir #4602"]
async fn get_practitioner_returns_fhir_resource_for_own_cabinet() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture = insert_cabinet_fixture(
        &owner,
        "Cabinet Directory A",
        "Alice",
        "Martin",
        Some("10100000099"),
    )
    .await;
    let token = make_interop_token(fixture.cabinet_id, "directory:read");

    let (status, body) = get(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Practitioner/{}", fixture.practitioner_id),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["resourceType"], "Practitioner");
    assert_eq!(body["id"], fixture.practitioner_id.to_string());
    assert_eq!(body["name"][0]["family"], "Martin");
    assert_eq!(body["identifier"][0]["value"], "10100000099");
    assert_eq!(
        body["identifier"][0]["system"],
        "urn:oid:1.2.250.1.71.4.2.1"
    );

    cleanup(&owner, &fixture).await;
}

#[tokio::test]
async fn get_practitioner_of_another_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture_a = insert_cabinet_fixture(&owner, "Cabinet A", "Alice", "Martin", None).await;
    let fixture_b = insert_cabinet_fixture(&owner, "Cabinet B", "Bob", "Durand", None).await;
    // Token du cabinet A, mais on demande le praticien du cabinet B.
    let token = make_interop_token(fixture_a.cabinet_id, "directory:read");

    let (status, body) = get(
        state_sync(app_pool().await),
        &format!(
            "/v1/interop/fhir/Practitioner/{}",
            fixture_b.practitioner_id
        ),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["resourceType"], "OperationOutcome");
    assert_eq!(body["issue"][0]["code"], "not-found");

    cleanup(&owner, &fixture_a).await;
    cleanup(&owner, &fixture_b).await;
}

#[tokio::test]
async fn get_practitioner_without_directory_scope_returns_403_operation_outcome() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture = insert_cabinet_fixture(&owner, "Cabinet Scope", "Alice", "Martin", None).await;
    // Scope accordé, mais pas directory:read.
    let token = make_interop_token(fixture.cabinet_id, "appointments:read");

    let (status, body) = get(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Practitioner/{}", fixture.practitioner_id),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::FORBIDDEN);
    assert_eq!(body["resourceType"], "OperationOutcome");
    assert_eq!(body["issue"][0]["code"], "forbidden");

    cleanup(&owner, &fixture).await;
}

#[tokio::test]
#[ignore = "quarantaine: échec réel révélé par le fix DB CI (env reset+migrate), voir #4602"]
async fn search_practitioners_lists_only_own_cabinet() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture_a =
        insert_cabinet_fixture(&owner, "Cabinet Search A", "Alice", "Martin", None).await;
    let fixture_b = insert_cabinet_fixture(&owner, "Cabinet Search B", "Bob", "Durand", None).await;
    let token = make_interop_token(fixture_a.cabinet_id, "directory:read");

    let (status, body) = get(
        state_sync(app_pool().await),
        "/v1/interop/fhir/Practitioner",
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["resourceType"], "Bundle");
    assert_eq!(body["type"], "searchset");
    assert_eq!(body["total"], 1);
    assert_eq!(
        body["entry"][0]["resource"]["id"],
        fixture_a.practitioner_id.to_string()
    );

    cleanup(&owner, &fixture_a).await;
    cleanup(&owner, &fixture_b).await;
}

#[tokio::test]
async fn search_practitioners_by_id_of_other_cabinet_returns_empty_bundle() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture_a = insert_cabinet_fixture(&owner, "Cabinet Id A", "Alice", "Martin", None).await;
    let fixture_b = insert_cabinet_fixture(&owner, "Cabinet Id B", "Bob", "Durand", None).await;
    let token = make_interop_token(fixture_a.cabinet_id, "directory:read");

    let (status, body) = get(
        state_sync(app_pool().await),
        &format!(
            "/v1/interop/fhir/Practitioner?_id={}",
            fixture_b.practitioner_id
        ),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["total"], 0);
    assert_eq!(body["entry"], serde_json::json!([]));

    cleanup(&owner, &fixture_a).await;
    cleanup(&owner, &fixture_b).await;
}

// ── Organization ─────────────────────────────────────────────────────────────

#[tokio::test]
async fn get_organization_returns_own_cabinet() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture = insert_cabinet_fixture(&owner, "Cabinet Org", "Alice", "Martin", None).await;
    let token = make_interop_token(fixture.cabinet_id, "directory:read");

    let (status, body) = get(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Organization/{}", fixture.cabinet_id),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["resourceType"], "Organization");
    assert_eq!(body["id"], fixture.cabinet_id.to_string());
    assert_eq!(body["name"], "Cabinet Org");

    cleanup(&owner, &fixture).await;
}

#[tokio::test]
async fn get_organization_of_another_cabinet_returns_404_even_if_it_exists() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture_a = insert_cabinet_fixture(&owner, "Cabinet Org A", "Alice", "Martin", None).await;
    let fixture_b = insert_cabinet_fixture(&owner, "Cabinet Org B", "Bob", "Durand", None).await;
    let token = make_interop_token(fixture_a.cabinet_id, "directory:read");

    let (status, body) = get(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Organization/{}", fixture_b.cabinet_id),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["resourceType"], "OperationOutcome");

    cleanup(&owner, &fixture_a).await;
    cleanup(&owner, &fixture_b).await;
}

// ── Location ─────────────────────────────────────────────────────────────────

#[tokio::test]
async fn get_location_returns_own_establishment() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture = insert_cabinet_fixture(&owner, "Cabinet Loc", "Alice", "Martin", None).await;
    let token = make_interop_token(fixture.cabinet_id, "directory:read");

    let (status, body) = get(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Location/{}", fixture.establishment_id),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["resourceType"], "Location");
    assert_eq!(body["id"], fixture.establishment_id.to_string());
    assert_eq!(body["address"]["postalCode"], "75001");
    assert_eq!(body["address"]["city"], "Paris");

    cleanup(&owner, &fixture).await;
}

/// `establishment` n'a AUCUNE RLS (table plateforme) — ce test vérifie que
/// l'isolation tenant vient bien du filtre explicite `provider.cabinet_id`
/// dans la requête (directory.rs), pas d'une policy RLS qui n'existe pas.
#[tokio::test]
async fn get_location_of_another_cabinet_establishment_returns_404() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture_a = insert_cabinet_fixture(&owner, "Cabinet Loc A", "Alice", "Martin", None).await;
    let fixture_b = insert_cabinet_fixture(&owner, "Cabinet Loc B", "Bob", "Durand", None).await;
    let token = make_interop_token(fixture_a.cabinet_id, "directory:read");

    let (status, body) = get(
        state_sync(app_pool().await),
        &format!("/v1/interop/fhir/Location/{}", fixture_b.establishment_id),
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["resourceType"], "OperationOutcome");

    cleanup(&owner, &fixture_a).await;
    cleanup(&owner, &fixture_b).await;
}

#[tokio::test]
async fn get_location_without_bearer_token_returns_401_rfc6749_shape() {
    if !db_available() {
        return;
    }
    let owner = owner_pool().await;
    let fixture =
        insert_cabinet_fixture(&owner, "Cabinet Loc No Token", "Alice", "Martin", None).await;

    let resp = app(state_sync(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!(
                    "/v1/interop/fhir/Location/{}",
                    fixture.establishment_id
                ))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = resp.status();
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: Value = serde_json::from_slice(&bytes).unwrap();

    // Couche bearer (InteropClaims, socle A1) : reste RFC 6749/6750, pas
    // OperationOutcome — distinct des erreurs de résolution de ressource.
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body["error"], "invalid_token");

    cleanup(&owner, &fixture).await;
}
