//! Tests d'intégration : PATCH /v1/cabinet/quotes/:id/items/:item_id/parts (#4069)
//!
//! Réaffectation manuelle AMO/AMC après retour de remboursement — doit
//! fonctionner même sur un devis `signed` (voir doc de module
//! `cabinet_quote_item_parts.rs`) et tracer l'ancien/nouveau montant dans
//! `audit_log`.

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

const JWT_SECRET: &str = "test-jwt-secret-quote-item-parts";

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

fn make_pro_jwt(user_id: Uuid, cabinet_id: Uuid, role: &str) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": user_id,
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
    patient_id: Uuid,
    quote_id: Uuid,
    item_id: Uuid,
}

/// Seed : cabinet + patient + devis au statut `status` + une ligne avec
/// amo_part=70.00/amc_part=20.00.
async fn seed(db: &PgPool, status: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();
    let item_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet QIP {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Reallocation')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency, signed_at) \
         VALUES ($1, $2, $3, $4, 100.00, 'EUR', CASE WHEN $4 = 'signed' THEN now() ELSE NULL END)",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote_item (id, cabinet_id, quote_id, label, unit_amount, amo_part, amc_part) \
         VALUES ($1, $2, $3, 'Couronne', 100.00, 70.00, 20.00)",
    )
    .bind(item_id)
    .bind(cabinet_id)
    .bind(quote_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        patient_id,
        quote_id,
        item_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_item WHERE quote_id = $1")
        .bind(f.quote_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE id = $1")
        .bind(f.quote_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn patch_parts(
    state: AppState,
    quote_id: Uuid,
    item_id: Uuid,
    token: String,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!(
                    "/v1/cabinet/quotes/{quote_id}/items/{item_id}/parts"
                ))
                .header("Authorization", format!("Bearer {token}"))
                .header("Content-Type", "application/json")
                .body(Body::from(body.to_string()))
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

// ── Test 1 : devis SIGNED — corrige amo_part, écrit un audit_log ────────────

#[tokio::test]
async fn patch_parts_on_signed_quote_updates_item_and_writes_audit_log() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let user_id = Uuid::new_v4();

    let (status, resp) = patch_parts(
        state_with(app_pool().await),
        f.quote_id,
        f.item_id,
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        json!({ "amo_part_cents": 5000 }),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(resp["amo_part_cents"], 5000);
    // amc_part_cents non fourni : doit rester inchangé (2000 = 20.00 EUR seed).
    assert_eq!(resp["amc_part_cents"], 2000);

    let item_row = sqlx::query(
        "SELECT (amo_part * 100)::bigint AS amo_cents, (amc_part * 100)::bigint AS amc_cents \
         FROM quote_item WHERE id = $1",
    )
    .bind(f.item_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let amo_cents: i64 = item_row.try_get("amo_cents").unwrap();
    let amc_cents: i64 = item_row.try_get("amc_cents").unwrap();
    assert_eq!(amo_cents, 5000);
    assert_eq!(amc_cents, 2000);

    // audit_log : append-only, pas de SELECT pour nubia_app -> vérifié via owner_pool.
    let audit_row = sqlx::query(
        "SELECT metadata FROM audit_log \
         WHERE entity = 'quote_item' AND entity_id = $1 \
           AND action = 'reallocate_quote_item_parts' \
         ORDER BY occurred_at DESC LIMIT 1",
    )
    .bind(f.item_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let metadata: serde_json::Value = audit_row.try_get("metadata").unwrap();
    assert_eq!(metadata["old_amo_part_cents"], 7000);
    assert_eq!(metadata["new_amo_part_cents"], 5000);
    assert_eq!(metadata["quote_id"], f.quote_id.to_string());

    cleanup(&db, &f).await;
}

// ── Test 2 : aucun champ fourni -> 422 ───────────────────────────────────────

#[tokio::test]
async fn patch_parts_with_no_fields_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "draft").await;
    let user_id = Uuid::new_v4();

    let (status, _) = patch_parts(
        state_with(app_pool().await),
        f.quote_id,
        f.item_id,
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        json!({}),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test 3 : montant négatif -> 422 ──────────────────────────────────────────

#[tokio::test]
async fn patch_parts_with_negative_amount_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "draft").await;
    let user_id = Uuid::new_v4();

    let (status, _) = patch_parts(
        state_with(app_pool().await),
        f.quote_id,
        f.item_id,
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        json!({ "amo_part_cents": -100 }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test 4 : ligne hors cabinet -> 404 (isolation RLS) ───────────────────────

#[tokio::test]
async fn patch_parts_of_other_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "draft").await;
    let other_cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();

    let (status, _) = patch_parts(
        state_with(app_pool().await),
        f.quote_id,
        f.item_id,
        make_pro_jwt(user_id, other_cabinet_id, "secretary"),
        json!({ "amo_part_cents": 1000 }),
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}

// ── Test 5 : somme amo+amc dépasse le montant de la ligne -> 422 (#4309) ────
//
// Seed : amount=10000, amo=7000, amc=2000 (somme 9000 <= 10000). Patch
// amo_part_cents=9000 sans toucher amc (reste 2000, valeur INCHANGÉE) :
// somme effective 9000+2000=11000 > 10000 → doit être rejeté, PAS accepté
// avec un reste à charge négatif (-1000).

#[tokio::test]
async fn patch_parts_exceeding_item_amount_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "draft").await;
    let user_id = Uuid::new_v4();

    let (status, _) = patch_parts(
        state_with(app_pool().await),
        f.quote_id,
        f.item_id,
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        json!({ "amo_part_cents": 9000 }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Doit rester inchangé (pas d'écriture partielle).
    let item_row =
        sqlx::query("SELECT (amo_part * 100)::bigint AS amo_cents FROM quote_item WHERE id = $1")
            .bind(f.item_id)
            .fetch_one(&db)
            .await
            .unwrap();
    let amo_cents: i64 = item_row.try_get("amo_cents").unwrap();
    assert_eq!(amo_cents, 7000, "aucune écriture ne doit avoir eu lieu");

    cleanup(&db, &f).await;
}
