//! Tests d'intégration : sélection du tarif applicable sur GET /v1/ccam/acts
//! selon le secteur conventionnel du praticien (#4056).
//!
//! Le catalogue seedé (migration 0119/0161) n'a que `secteur1_cents` rempli
//! (`optam_cents`/`panier_sante` restent NULL, cf. #4054/#4055) — ces tests
//! insèrent une ligne `ccam_act` dédiée avec les trois colonnes renseignées
//! pour exercer réellement la différence secteur1/OPTAM, plutôt que de
//! dépendre du seed (où les deux se replieraient silencieusement sur la
//! même valeur et masqueraient un bug de sélection).

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

const JWT_SECRET: &str = "test-secret-ccam-tariff-selection";
const TEST_CODE: &str = "TEST4056";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "practitioner".into(),
            exp: exp(),
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
}

/// Insère cabinet + app_user + practitioner (`conventions` fourni tel quel)
/// + une ligne `ccam_act` de test avec les 3 colonnes tarifaires renseignées.
async fn insert_fixtures(db: &PgPool, conventions: serde_json::Value) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("ccam-tariff+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Tariff Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO practitioner (id, cabinet_id, user_id, conventions) VALUES ($1, $2, $3, $4)",
    )
    .bind(prac_id)
    .bind(cabinet_id)
    .bind(user_id)
    .bind(conventions)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO ccam_act \
         (code, label, tarif_cents, secteur1_cents, optam_cents, panier_sante, active) \
         VALUES ($1, 'Acte de test #4056', 1000, 1000, 1200, 'libre', true) \
         ON CONFLICT (code) DO UPDATE SET \
           tarif_cents = EXCLUDED.tarif_cents, \
           secteur1_cents = EXCLUDED.secteur1_cents, \
           optam_cents = EXCLUDED.optam_cents, \
           panier_sante = EXCLUDED.panier_sante, \
           active = true",
    )
    .bind(TEST_CODE)
    .execute(db)
    .await
    .unwrap();

    Fixtures {
        cabinet_id,
        user_id,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    sqlx::query("DELETE FROM ccam_act WHERE code = $1")
        .bind(TEST_CODE)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : praticien OPTAM → applicable_tariff_cents = optam_cents ─────────

#[tokio::test]
async fn optam_practitioner_gets_optam_tariff() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, json!({ "optam": true })).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/ccam/acts?q={}", TEST_CODE))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let item = v["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["code"] == TEST_CODE)
        .expect("ligne de test présente");
    assert_eq!(item["applicable_tariff_cents"], 1200);
    assert_eq!(item["panier_sante"], "libre");

    cleanup_fixtures(&db, &f).await;
}

// ── Test 2 : praticien non-OPTAM → applicable_tariff_cents = secteur1_cents ──

#[tokio::test]
async fn non_optam_practitioner_gets_secteur1_tariff() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixtures(&db, json!({})).await;

    let token = make_practitioner_token(f.user_id, f.cabinet_id);
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/ccam/acts?q={}", TEST_CODE))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let item = v["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["code"] == TEST_CODE)
        .expect("ligne de test présente");
    assert_eq!(item["applicable_tariff_cents"], 1000);

    cleanup_fixtures(&db, &f).await;
}

// ── Test 3 : praticien sans ligne `practitioner` → repli non-OPTAM, pas de 500 ─

#[tokio::test]
async fn practitioner_without_row_falls_back_gracefully() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    // Fixture minimale : ligne `ccam_act` de test insérée, mais AUCUNE ligne
    // `practitioner` pour ce token (cas edge : compte pro sans fiche
    // practitioner, ex. juste après provisioning).
    sqlx::query(
        "INSERT INTO ccam_act \
         (code, label, tarif_cents, secteur1_cents, optam_cents, panier_sante, active) \
         VALUES ($1, 'Acte de test #4056', 1000, 1000, 1200, 'libre', true) \
         ON CONFLICT (code) DO UPDATE SET \
           tarif_cents = EXCLUDED.tarif_cents, \
           secteur1_cents = EXCLUDED.secteur1_cents, \
           optam_cents = EXCLUDED.optam_cents, \
           panier_sante = EXCLUDED.panier_sante, \
           active = true",
    )
    .bind(TEST_CODE)
    .execute(&db)
    .await
    .unwrap();

    let token = make_practitioner_token(Uuid::new_v4(), Uuid::new_v4());
    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/ccam/acts?q={}", TEST_CODE))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let item = v["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["code"] == TEST_CODE)
        .expect("ligne de test présente");
    assert_eq!(item["applicable_tariff_cents"], 1000);

    sqlx::query("DELETE FROM ccam_act WHERE code = $1")
        .bind(TEST_CODE)
        .execute(&db)
        .await
        .ok();
}
