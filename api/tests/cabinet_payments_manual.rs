//! Tests d'intégration : POST /v1/cabinet/payments/manual (#4070, #4311)
//!
//! Encaissement manuel (espèces/chèque/virement) sans PaymentIntent
//! Stripe/GoCardless : crée un `payment` `status='paid'` immédiat.
//! #4311 : parité avec le chemin Stripe — devis `signed` requis, garde
//! anti-sur-encaissement, idempotence via header `Idempotency-Key`.

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-payments-manual";

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
}

/// Seed : cabinet + patient + devis au statut `status` (100.00 EUR).
async fn seed(db: &PgPool, status: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet CPM {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'ManualPayment')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, $4, 100.00, 'EUR')",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Le reste dû est calculé depuis les quote_item (part patient), pas depuis
    // quote.total_amount. Sans ligne, reste dû = 0 → tout paiement rejeté 422.
    // 1 acte à 100.00 (part patient pleine) → reste dû 10000 cents.
    sqlx::query(
        "INSERT INTO quote_item (cabinet_id, quote_id, label, qty, unit_amount) \
         VALUES ($1, $2, 'Acte de test', 1, 100.00)",
    )
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
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM payment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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

    sqlx::query("DELETE FROM idempotency_keys WHERE key LIKE 'test-cpm-%'")
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

/// `idem` est le header `Idempotency-Key` — `None` pour tester son absence.
async fn create_manual(
    state: AppState,
    token: String,
    idem: Option<&str>,
    body: serde_json::Value,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method("POST")
        .uri("/v1/cabinet/payments/manual")
        .header("Authorization", format!("Bearer {token}"))
        .header("Content-Type", "application/json");
    if let Some(key) = idem {
        builder = builder.header("Idempotency-Key", key);
    }
    let response = app(state)
        .oneshot(builder.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

fn idem_key(test_name: &str) -> String {
    format!("test-cpm-{test_name}-{}", Uuid::new_v4())
}

// ── Test 1 : method='cash', devis signed -> paiement paid associé au bon devis/cabinet ──

#[tokio::test]
async fn create_manual_payment_with_cash_creates_paid_payment() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let user_id = Uuid::new_v4();
    let key = idem_key("cash-happy");

    let (status, resp) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        Some(&key),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 10000,
            "method": "cash"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(resp["status"], "paid");
    let payment_id: Uuid = resp["payment_id"].as_str().unwrap().parse().unwrap();

    let row = sqlx::query(
        "SELECT cabinet_id, patient_id, quote_id, status, provider, method, \
                (amount * 100)::bigint AS amount_cents \
         FROM payment WHERE id = $1",
    )
    .bind(payment_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let cabinet_id: Uuid = row.try_get("cabinet_id").unwrap();
    let patient_id: Uuid = row.try_get("patient_id").unwrap();
    let quote_id: Uuid = row.try_get("quote_id").unwrap();
    let status: String = row.try_get("status").unwrap();
    let provider: String = row.try_get("provider").unwrap();
    let method: String = row.try_get("method").unwrap();
    let amount_cents: i64 = row.try_get("amount_cents").unwrap();

    assert_eq!(cabinet_id, f.cabinet_id);
    assert_eq!(patient_id, f.patient_id);
    assert_eq!(quote_id, f.quote_id);
    assert_eq!(status, "paid");
    assert_eq!(provider, "manual");
    assert_eq!(method, "cash");
    assert_eq!(amount_cents, 10000);

    cleanup(&db, &f).await;
}

// ── Test 2 : patient d'un autre cabinet -> 404 (RLS) ─────────────────────────

#[tokio::test]
async fn create_manual_payment_cross_tenant_patient_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let other_cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let key = idem_key("cross-tenant");

    let (status, _) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, other_cabinet_id, "secretary"),
        Some(&key),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 10000,
            "method": "cash"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::NOT_FOUND);

    // Aucun paiement ne doit avoir été créé pour le cabinet ciblé par erreur.
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM payment WHERE cabinet_id = $1")
        .bind(other_cabinet_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(count, 0);

    cleanup(&db, &f).await;
}

// ── Test 3 : method invalide (card, doit passer par PaymentIntent) -> 422 ───

#[tokio::test]
async fn create_manual_payment_with_card_method_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let user_id = Uuid::new_v4();
    let key = idem_key("card-method");

    let (status, _) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        Some(&key),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 10000,
            "method": "card"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test 4 : montant <= 0 -> 422 ─────────────────────────────────────────────

#[tokio::test]
async fn create_manual_payment_with_zero_amount_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let user_id = Uuid::new_v4();
    let key = idem_key("zero-amount");

    let (status, _) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        Some(&key),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 0,
            "method": "check"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test 5 : token practitioner -> 201 (autorisé) ────────────────────────────

#[tokio::test]
async fn create_manual_payment_with_practitioner_token_succeeds() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let user_id = Uuid::new_v4();
    let key = idem_key("practitioner-token");

    let (status, _) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "practitioner"),
        Some(&key),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 5000,
            "method": "bank_transfer"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);

    cleanup(&db, &f).await;
}

// ── Test 6 : devis draft -> 409 invalid_status (#4311) ──────────────────────

#[tokio::test]
async fn create_manual_payment_on_draft_quote_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "draft").await;
    let user_id = Uuid::new_v4();
    let key = idem_key("draft-quote");

    let (status, resp) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        Some(&key),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 100000,
            "method": "cash"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(resp["code"], "invalid_status");

    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM payment WHERE quote_id = $1")
        .bind(f.quote_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(count, 0, "aucun paiement ne doit avoir été créé");

    cleanup(&db, &f).await;
}

// ── Test 7 : montant > reste dû -> 422 (#4311, anti-sur-encaissement) ───────

#[tokio::test]
async fn create_manual_payment_exceeding_remaining_due_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let user_id = Uuid::new_v4();
    let key = idem_key("over-capture");

    // Devis de 100.00 EUR (10000 cents) — tente d'encaisser 1000.00 EUR (20x).
    let (status, resp) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        Some(&key),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 100000,
            "method": "cash"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "resp={resp:?}");

    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM payment WHERE quote_id = $1")
        .bind(f.quote_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(count, 0, "aucun paiement ne doit avoir été créé");

    cleanup(&db, &f).await;
}

// ── Test 8 : deuxième encaissement dépassant le reste dû -> 422 (cumul) ─────

#[tokio::test]
async fn create_manual_payment_second_call_exceeding_remaining_due_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let user_id = Uuid::new_v4();
    let token = make_pro_jwt(user_id, f.cabinet_id, "secretary");

    // Devis de 100.00 EUR : premier encaissement de 60.00 EUR (reste dû 40.00).
    let (status1, _) = create_manual(
        state_with(app_pool().await),
        token.clone(),
        Some(&idem_key("cumul-1")),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 6000,
            "method": "cash"
        }),
    )
    .await;
    assert_eq!(status1, StatusCode::CREATED);

    // Deuxième encaissement de 60.00 EUR : dépasse le reste dû (40.00) même si
    // chaque appel pris isolément est sous le total du devis.
    let (status2, _) = create_manual(
        state_with(app_pool().await),
        token,
        Some(&idem_key("cumul-2")),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 6000,
            "method": "cash"
        }),
    )
    .await;
    assert_eq!(status2, StatusCode::UNPROCESSABLE_ENTITY);

    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM payment WHERE quote_id = $1")
        .bind(f.quote_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(count, 1, "seul le premier encaissement doit exister");

    cleanup(&db, &f).await;
}

// ── Test 9 : header Idempotency-Key absent -> 422 (#4311) ───────────────────

#[tokio::test]
async fn create_manual_payment_without_idempotency_key_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let user_id = Uuid::new_v4();

    let (status, _) = create_manual(
        state_with(app_pool().await),
        make_pro_jwt(user_id, f.cabinet_id, "secretary"),
        None,
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 10000,
            "method": "cash"
        }),
    )
    .await;

    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    cleanup(&db, &f).await;
}

// ── Test 10 : rejeu même clé + même requête -> même payment_id, pas de doublon (#4311) ──

#[tokio::test]
async fn create_manual_payment_replayed_with_same_key_is_idempotent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let user_id = Uuid::new_v4();
    let token = make_pro_jwt(user_id, f.cabinet_id, "secretary");
    let key = idem_key("replay-same");
    let body = json!({
        "patient_id": f.patient_id,
        "quote_id": f.quote_id,
        "amount_cents": 10000,
        "method": "cash"
    });

    let (status1, resp1) = create_manual(
        state_with(app_pool().await),
        token.clone(),
        Some(&key),
        body.clone(),
    )
    .await;
    assert_eq!(status1, StatusCode::CREATED);
    let payment_id1 = resp1["payment_id"].clone();

    let (status2, resp2) =
        create_manual(state_with(app_pool().await), token, Some(&key), body).await;
    assert_eq!(status2, StatusCode::CREATED);
    assert_eq!(
        resp2["payment_id"], payment_id1,
        "le rejeu doit renvoyer le même payment_id, pas en créer un nouveau"
    );

    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM payment WHERE quote_id = $1")
        .bind(f.quote_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(count, 1, "une seule ligne payment malgré les 2 appels");

    cleanup(&db, &f).await;
}

// ── Test 11 : même clé, requête différente -> 409 idempotency_key_conflict ──

#[tokio::test]
async fn create_manual_payment_same_key_different_amount_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let user_id = Uuid::new_v4();
    let token = make_pro_jwt(user_id, f.cabinet_id, "secretary");
    let key = idem_key("replay-conflict");

    let (status1, _) = create_manual(
        state_with(app_pool().await),
        token.clone(),
        Some(&key),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 1000,
            "method": "cash"
        }),
    )
    .await;
    assert_eq!(status1, StatusCode::CREATED);

    // Même clé, montant différent — ne doit jamais renvoyer le paiement du 1er appel.
    let (status2, resp2) = create_manual(
        state_with(app_pool().await),
        token,
        Some(&key),
        json!({
            "patient_id": f.patient_id,
            "quote_id": f.quote_id,
            "amount_cents": 2000,
            "method": "cash"
        }),
    )
    .await;
    assert_eq!(status2, StatusCode::CONFLICT);
    assert_eq!(resp2["code"], "idempotency_key_conflict");

    cleanup(&db, &f).await;
}
