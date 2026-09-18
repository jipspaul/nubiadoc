//! Tests d'intégration : libération des holds de créneau expirés (#6992, #6840).
//!
//! Un patient qui pose un hold (`POST /v1/slots/:id/hold`) puis abandonne le
//! tunnel ne doit pas stériliser le créneau : passé `expires_at`, le créneau
//! doit réapparaître dans `/v1/search/slots` et `/v1/providers/:id/availability`
//! et redevenir « holdable » par un autre patient. Un hold ACTIF, lui, reste
//! bloquant. Le reaper périodique (`dispatch_slot_hold_expiry`) purge les
//! holds expirés et repasse les créneaux en `open`.

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

use nubia_api::{app, dispatch_slot_hold_expiry, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-slot-hold-expiry";

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

fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn test_state() -> AppState {
    AppState {
        db: PgPool::connect_lazy(
            &std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
        )
        .unwrap(),
        jwt_secret: JWT_SECRET.into(),
        mailer: Arc::new(StubMailer),
    }
}

/// Insère un utilisateur patient + patient_account. Retourne (user_id, account_id).
async fn insert_patient(db: &PgPool, suffix: &str) -> (Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("hold-expiry-patient-{}@nubia.test", suffix))
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'HoldExpiry')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
    (user_id, account_id)
}

/// Insère un provider listé + un slot open exposé en ligne. Retourne
/// (provider_id, slot_id).
async fn insert_provider_and_slot(db: &PgPool, suffix: &str) -> (Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let slot_id = Uuid::new_v4();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Hold Expiry {}", suffix))
        .execute(db)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("hold-expiry-pro-{}@nubia.test", suffix))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO provider (id, cabinet_id, user_id, display_name, rpps_verified, is_listed) \
         VALUES ($1, $2, $3, $4, true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(user_id)
    .bind(format!("Dr HoldExpiry {}", suffix))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, cabinet_id, starts_at, ends_at, status, online_booking) \
         VALUES ($1, $2, $3, now() + interval '1 day', now() + interval '1 day 30 minutes', \
                 'open', true)",
    )
    .bind(slot_id)
    .bind(provider_id)
    .bind(cabinet_id)
    .execute(db)
    .await
    .unwrap();

    (provider_id, slot_id)
}

async fn cleanup(db: &PgPool, slot_id: Uuid) {
    sqlx::query("DELETE FROM slot_holds WHERE slot_id = $1")
        .bind(slot_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM availability_slot WHERE id = $1")
        .bind(slot_id)
        .execute(db)
        .await
        .ok();
}

/// `POST /v1/slots/:id/hold` avec le JWT patient fourni → statut HTTP.
async fn post_hold(state: AppState, slot_id: Uuid, token: &str) -> StatusCode {
    app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/slots/{}/hold", slot_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap()
        .status()
}

/// `GET /v1/search/slots?provider_id=…` → les slot_id renvoyés pour ce
/// praticien (vide si le praticien n'apparaît pas).
async fn search_slot_ids(state: AppState, provider_id: Uuid) -> Vec<String> {
    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/search/slots?provider_id={provider_id}"))
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
    v["data"]
        .as_array()
        .expect("data doit être un tableau")
        .iter()
        .filter(|e| e["provider_id"].as_str() == Some(&provider_id.to_string()))
        .flat_map(|e| {
            e["slots"]
                .as_array()
                .cloned()
                .unwrap_or_default()
                .into_iter()
                .filter_map(|s| s["slot_id"].as_str().map(str::to_string))
        })
        .collect()
}

/// `GET /v1/providers/:id/availability` → les slot_id renvoyés.
async fn availability_slot_ids(state: AppState, provider_id: Uuid) -> Vec<String> {
    let response = app(state)
        .oneshot(
            Request::builder()
                .uri(format!("/v1/providers/{provider_id}/availability"))
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
    v["data"]
        .as_array()
        .expect("data doit être un tableau")
        .iter()
        .filter_map(|s| s["slot_id"].as_str().map(str::to_string))
        .collect()
}

/// Recule `expires_at` du hold en SQL : simule les 10 min écoulées sans
/// attendre.
async fn expire_hold(db: &PgPool, slot_id: Uuid) {
    let updated = sqlx::query(
        "UPDATE slot_holds SET expires_at = now() - interval '2 minutes' WHERE slot_id = $1",
    )
    .bind(slot_id)
    .execute(db)
    .await
    .unwrap()
    .rows_affected();
    assert_eq!(updated, 1, "le hold à expirer doit exister");
}

async fn slot_status(db: &PgPool, slot_id: Uuid) -> String {
    sqlx::query("SELECT status FROM availability_slot WHERE id = $1")
        .bind(slot_id)
        .fetch_one(db)
        .await
        .unwrap()
        .try_get("status")
        .unwrap()
}

// ── Test 1 : hold expiré → le créneau réapparaît dans les listings et un
// autre patient peut le tenir (#6992, #6840 — repro QA) ─────────────────────

#[tokio::test]
async fn expired_hold_slot_reappears_in_listings_and_can_be_reheld() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let (provider_id, slot_id) = insert_provider_and_slot(&db, &suffix).await;
    let (user_a, account_a) = insert_patient(&db, &format!("a-{suffix}")).await;
    let (user_b, account_b) = insert_patient(&db, &format!("b-{suffix}")).await;
    let token_a = make_patient_jwt(user_a, account_a);
    let token_b = make_patient_jwt(user_b, account_b);
    let slot = slot_id.to_string();

    // Avant le hold : visible.
    assert!(search_slot_ids(test_state(), provider_id)
        .await
        .contains(&slot));

    // Patient A pose un hold puis abandonne (aucun appel ensuite).
    assert_eq!(
        post_hold(test_state(), slot_id, &token_a).await,
        StatusCode::OK
    );
    assert!(
        !search_slot_ids(test_state(), provider_id)
            .await
            .contains(&slot),
        "pendant le hold, le créneau doit être absent de /search/slots"
    );

    // Les 10 minutes passent (expires_at reculé en SQL) — aucun reaper appelé
    // volontairement : le chemin de lecture doit suffire.
    expire_hold(&db, slot_id).await;

    assert!(
        search_slot_ids(test_state(), provider_id)
            .await
            .contains(&slot),
        "hold expiré : le créneau doit réapparaître dans /search/slots"
    );
    assert!(
        availability_slot_ids(test_state(), provider_id)
            .await
            .contains(&slot),
        "hold expiré : le créneau doit réapparaître dans /providers/:id/availability"
    );

    // Un AUTRE patient peut désormais tenir le créneau.
    assert_eq!(
        post_hold(test_state(), slot_id, &token_b).await,
        StatusCode::OK,
        "hold expiré : un nouveau hold par un autre patient doit être accepté"
    );
    let holder: Uuid = sqlx::query("SELECT user_id FROM slot_holds WHERE slot_id = $1")
        .bind(slot_id)
        .fetch_one(&db)
        .await
        .unwrap()
        .try_get("user_id")
        .unwrap();
    assert_eq!(holder, user_b, "le hold doit appartenir au second patient");
    assert_eq!(slot_status(&db, slot_id).await, "held");

    cleanup(&db, slot_id).await;
}

// ── Test 2 : hold ACTIF → le créneau reste absent des listings et 409 pour
// un autre patient (non-régression du verrou 10 min) ────────────────────────

#[tokio::test]
async fn active_hold_still_hides_slot_and_blocks_other_patient() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let (provider_id, slot_id) = insert_provider_and_slot(&db, &suffix).await;
    let (user_a, account_a) = insert_patient(&db, &format!("a-{suffix}")).await;
    let (user_b, account_b) = insert_patient(&db, &format!("b-{suffix}")).await;
    let token_a = make_patient_jwt(user_a, account_a);
    let token_b = make_patient_jwt(user_b, account_b);
    let slot = slot_id.to_string();

    assert_eq!(
        post_hold(test_state(), slot_id, &token_a).await,
        StatusCode::OK
    );

    assert!(
        !search_slot_ids(test_state(), provider_id)
            .await
            .contains(&slot),
        "hold actif : le créneau doit rester absent de /search/slots"
    );
    assert!(
        !availability_slot_ids(test_state(), provider_id)
            .await
            .contains(&slot),
        "hold actif : le créneau doit rester absent de /providers/:id/availability"
    );
    assert_eq!(
        post_hold(test_state(), slot_id, &token_b).await,
        StatusCode::CONFLICT,
        "hold actif : un autre patient doit recevoir 409"
    );

    // Le reaper ne touche pas à un hold actif.
    dispatch_slot_hold_expiry(&app_pool().await).await.unwrap();
    assert_eq!(slot_status(&db, slot_id).await, "held");
    let holds: i64 = sqlx::query("SELECT count(*) AS n FROM slot_holds WHERE slot_id = $1")
        .bind(slot_id)
        .fetch_one(&db)
        .await
        .unwrap()
        .try_get("n")
        .unwrap();
    assert_eq!(
        holds, 1,
        "un hold actif ne doit pas être purgé par le reaper"
    );

    cleanup(&db, slot_id).await;
}

// ── Test 3 : le reaper purge le hold expiré et repasse le créneau en open ───

#[tokio::test]
async fn reaper_releases_expired_hold_and_reopens_slot() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let suffix = Uuid::new_v4().to_string();
    let (_, slot_id) = insert_provider_and_slot(&db, &suffix).await;
    let (user_a, account_a) = insert_patient(&db, &suffix).await;
    let token_a = make_patient_jwt(user_a, account_a);

    assert_eq!(
        post_hold(test_state(), slot_id, &token_a).await,
        StatusCode::OK
    );
    assert_eq!(slot_status(&db, slot_id).await, "held");
    expire_hold(&db, slot_id).await;

    // Le reaper tourne sous nubia_app, hors de tout contexte de requête (pas
    // de GUC cabinet) — comme la boucle `tokio::spawn` de main.rs.
    let summary = dispatch_slot_hold_expiry(&app_pool().await).await.unwrap();
    assert!(
        summary.released >= 1,
        "le reaper doit compter au moins le hold expiré de ce test"
    );

    assert_eq!(
        slot_status(&db, slot_id).await,
        "open",
        "hold expiré purgé : le créneau doit repasser en open"
    );
    let holds: i64 = sqlx::query("SELECT count(*) AS n FROM slot_holds WHERE slot_id = $1")
        .bind(slot_id)
        .fetch_one(&db)
        .await
        .unwrap()
        .try_get("n")
        .unwrap();
    assert_eq!(holds, 0, "le hold expiré doit avoir été supprimé");

    cleanup(&db, slot_id).await;
}
