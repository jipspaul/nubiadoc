//! Tests d'intégration : signature concurrente (« double-submit ») d'une
//! ordonnance et d'un devis — #7012, #6794, #7015.
//!
//! Reproduit le scénario QA : N requêtes `POST …/sign` lancées EN PARALLÈLE
//! sur le même objet. Avant le correctif, la garde de statut était un
//! read-then-write sans verrou : toutes les requêtes lisaient `draft`/`sent`
//! avant qu'aucune n'écrive.
//! - Ordonnance : N × 200, N signatures eIDAS, N PDF dans le coffre du
//!   patient dont N-1 orphelins (#7012, #6794).
//! - Devis : 1 × 200 + (N-1) × 500 `internal_error` (#7015).
//!
//! Règle attendue (doc12 §10 / §17) : le perdant d'une course reçoit
//! EXACTEMENT la réponse d'un second appel séquentiel — `409 invalid_status`
//! pour l'ordonnance, `200` idempotent (même `signed_at`) pour le devis —
//! et jamais un 5xx. Une seule signature / un seul document en base.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use futures_util::future::join_all;
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-signature-concurrency";

/// Nombre de requêtes simultanées (≥ 4, comme le scénario QA).
const CONCURRENCY: usize = 4;

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

fn make_patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({
            "sub": user_id,
            "kind": "patient",
            "account_id": account_id,
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

/// Lance `CONCURRENCY` fois le même `POST` (sans body) en parallèle sur un
/// même routeur cloné, et renvoie `(status, body JSON)` pour chacune.
async fn post_concurrently(
    router: axum::Router,
    uri: String,
    token: String,
) -> Vec<(StatusCode, serde_json::Value)> {
    let futures = (0..CONCURRENCY).map(|_| {
        let router = router.clone();
        let uri = uri.clone();
        let token = token.clone();
        async move {
            let response = router
                .oneshot(
                    Request::builder()
                        .method("POST")
                        .uri(uri)
                        .header("Authorization", format!("Bearer {token}"))
                        .body(Body::empty())
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
    });
    join_all(futures).await
}

// ═════════════════════════════════════════════════════════════════════════════
// Ordonnance — POST /v1/cabinet/prescriptions/:id/sign (#7012, #6794)
// ═════════════════════════════════════════════════════════════════════════════

struct PrescriptionFixture {
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
    prescription_id: Uuid,
}

/// Cabinet + praticien + patient + ordonnance `draft` (même squelette que
/// `prescriptions_sign.rs`, ids uniques — base partagée).
async fn seed_prescription(db: &PgPool) -> PrescriptionFixture {
    let f = PrescriptionFixture {
        cabinet_id: Uuid::new_v4(),
        prac_user_id: Uuid::new_v4(),
        prac_id: Uuid::new_v4(),
        patient_id: Uuid::new_v4(),
        prescription_id: Uuid::new_v4(),
    };

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(f.prac_user_id)
    .bind(format!("sig-conc-prac+{}@nubia.test", f.prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Signature Concurrente', 'dentaire')",
    )
    .bind(f.cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(f.prac_id)
        .bind(f.cabinet_id)
        .bind(f.prac_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Patient', 'Concurrence')",
    )
    .bind(f.patient_id)
    .bind(f.cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status) \
         VALUES ($1, $2, $3, $4, 'draft')",
    )
    .bind(f.prescription_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .bind(f.prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    f
}

async fn cleanup_prescription(db: &PgPool, f: &PrescriptionFixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("UPDATE prescription SET document_id = NULL, signature_id = NULL WHERE id = $1")
        .bind(f.prescription_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM prescription WHERE id = $1")
        .bind(f.prescription_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM document WHERE patient_id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM signature WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(f.prac_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

/// #7012 / #6794 : N signatures simultanées d'une même ordonnance → exactement
/// une 200, les autres `409 invalid_status`, aucun 5xx ; une seule ligne
/// `signature`, un seul `document(category='ordonnance')` dans le coffre du
/// patient, référencé par l'ordonnance.
#[tokio::test]
async fn concurrent_prescription_sign_yields_exactly_one_signature_and_document() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed_prescription(&db).await;

    let router = app(state_with(app_pool().await));
    let results = post_concurrently(
        router,
        format!("/v1/cabinet/prescriptions/{}/sign", f.prescription_id),
        make_pro_jwt(f.prac_user_id, f.cabinet_id, "practitioner"),
    )
    .await;

    let statuses: Vec<StatusCode> = results.iter().map(|(s, _)| *s).collect();
    assert!(
        statuses.iter().all(|s| !s.is_server_error()),
        "aucun 5xx attendu sur une course prévisible, obtenu {statuses:?}"
    );
    let ok: Vec<&serde_json::Value> = results
        .iter()
        .filter(|(s, _)| *s == StatusCode::OK)
        .map(|(_, v)| v)
        .collect();
    assert_eq!(
        ok.len(),
        1,
        "exactement UNE signature doit aboutir, obtenu {statuses:?}"
    );
    let conflicts = results
        .iter()
        .filter(|(s, v)| *s == StatusCode::CONFLICT && v["code"] == "invalid_status")
        .count();
    assert_eq!(
        conflicts,
        CONCURRENCY - 1,
        "les perdants doivent recevoir 409 invalid_status (comme en séquentiel), obtenu {results:?}"
    );

    let winner_document_id = Uuid::parse_str(ok[0]["document_id"].as_str().unwrap()).unwrap();

    // État en base : une seule signature, un seul document, référencé.
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let signatures: i64 =
        sqlx::query_scalar("SELECT count(*) FROM signature WHERE cabinet_id = $1")
            .bind(f.cabinet_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
    let documents: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM document WHERE patient_id = $1 AND category = 'ordonnance'",
    )
    .bind(f.patient_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    let row = sqlx::query("SELECT status, document_id FROM prescription WHERE id = $1")
        .bind(f.prescription_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();

    assert_eq!(signatures, 1, "une seule signature eIDAS par ordonnance");
    assert_eq!(
        documents, 1,
        "un seul PDF dans le coffre-fort du patient (pas d'orphelin)"
    );
    let status: String = sqlx::Row::try_get(&row, "status").unwrap();
    let document_id: Option<Uuid> = sqlx::Row::try_get(&row, "document_id").unwrap();
    assert_eq!(status, "signed");
    assert_eq!(document_id, Some(winner_document_id));

    cleanup_prescription(&db, &f).await;
}

// ═════════════════════════════════════════════════════════════════════════════
// Devis — POST /v1/quotes/:id/sign (#7015)
// ═════════════════════════════════════════════════════════════════════════════

struct QuoteFixture {
    cabinet_id: Uuid,
    practitioner_user_id: Uuid,
    patient_account_user_id: Uuid,
    patient_account_id: Uuid,
    patient_id: Uuid,
    quote_id: Uuid,
}

/// Cabinet + membre `practitioner` + patient (compte app + fiche) + devis
/// au statut `status` (même squelette que `quote_lifecycle_notifications.rs`).
async fn seed_quote_with_status(db: &PgPool, status: &str) -> QuoteFixture {
    let f = QuoteFixture {
        cabinet_id: Uuid::new_v4(),
        practitioner_user_id: Uuid::new_v4(),
        patient_account_user_id: Uuid::new_v4(),
        patient_account_id: Uuid::new_v4(),
        patient_id: Uuid::new_v4(),
        quote_id: Uuid::new_v4(),
    };

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(f.practitioner_user_id)
    .bind(format!(
        "sig-conc-practitioner+{}@nubia.test",
        f.practitioner_user_id
    ))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(f.patient_account_user_id)
    .bind(format!(
        "sig-conc-patient+{}@nubia.test",
        f.patient_account_user_id
    ))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Concurrence')",
    )
    .bind(f.patient_account_id)
    .bind(f.patient_account_user_id)
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(f.cabinet_id)
        .bind(format!("Cabinet Signature Concurrente {}", f.cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) \
         VALUES ($1, $2, 'practitioner', true)",
    )
    .bind(f.cabinet_id)
    .bind(f.practitioner_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Test', 'Concurrence', $3)",
    )
    .bind(f.patient_id)
    .bind(f.cabinet_id)
    .bind(f.patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount, currency) \
         VALUES ($1, $2, $3, $4, 150.00, 'EUR')",
    )
    .bind(f.quote_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    f
}

async fn seed_quote(db: &PgPool) -> QuoteFixture {
    seed_quote_with_status(db, "sent").await
}

async fn cleanup_quote(db: &PgPool, f: &QuoteFixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    // Le devis signé est immuable (trigger 0051) : suppression directe, en
    // retirant d'abord la référence document pour libérer la FK.
    sqlx::query("DELETE FROM quote WHERE id = $1")
        .bind(f.quote_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM document WHERE patient_id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
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

    sqlx::query("DELETE FROM notification WHERE app_user_id IN ($1, $2)")
        .bind(f.practitioner_user_id)
        .bind(f.patient_account_user_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id IN ($1, $2)")
        .bind(f.practitioner_user_id)
        .bind(f.patient_account_user_id)
        .execute(db)
        .await
        .ok();
}

/// #7015 : N signatures simultanées d'un même devis → N × 200 idempotents
/// (tous avec le MÊME `signed_at`), aucun 5xx ; un seul `signed_at` en base,
/// un seul `document(category='devis')` dans le coffre du patient.
#[tokio::test]
async fn concurrent_quote_sign_is_idempotent_and_never_500() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed_quote(&db).await;

    let router = app(state_with(app_pool().await));
    let results = post_concurrently(
        router,
        format!("/v1/quotes/{}/sign", f.quote_id),
        make_patient_jwt(f.patient_account_user_id, f.patient_account_id),
    )
    .await;

    let statuses: Vec<StatusCode> = results.iter().map(|(s, _)| *s).collect();
    assert!(
        statuses.iter().all(|s| !s.is_server_error()),
        "aucun 5xx attendu sur une course prévisible, obtenu {statuses:?}"
    );
    assert!(
        statuses.iter().all(|s| *s == StatusCode::OK),
        "le perdant reçoit 200 idempotent (comme en séquentiel), obtenu {results:?}"
    );
    let signed_ats: std::collections::BTreeSet<String> = results
        .iter()
        .map(|(_, v)| v["signed_at"].as_str().unwrap_or("").to_string())
        .collect();
    assert_eq!(
        signed_ats.len(),
        1,
        "toutes les réponses doivent porter le même signed_at, obtenu {signed_ats:?}"
    );
    assert!(
        !signed_ats.iter().next().unwrap().is_empty(),
        "signed_at doit être renseigné"
    );

    // État en base : devis signé une fois, un seul document.
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query("SELECT status, signed_at, document_id FROM quote WHERE id = $1")
        .bind(f.quote_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    let documents: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM document WHERE patient_id = $1 AND category = 'devis'",
    )
    .bind(f.patient_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let status: String = sqlx::Row::try_get(&row, "status").unwrap();
    let signed_at: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::Row::try_get(&row, "signed_at").unwrap();
    let document_id: Option<Uuid> = sqlx::Row::try_get(&row, "document_id").unwrap();
    assert_eq!(status, "signed");
    assert_eq!(
        signed_at.map(|d| d.to_rfc3339()).as_deref(),
        signed_ats.iter().next().map(String::as_str)
    );
    assert_eq!(documents, 1, "un seul PDF de devis dans le coffre-fort");
    assert!(document_id.is_some(), "quote.document_id doit être posé");

    cleanup_quote(&db, &f).await;
}

// ═════════════════════════════════════════════════════════════════════════════
// Devis — POST /v1/cabinet/quotes/:id/send (#7016)
// ═════════════════════════════════════════════════════════════════════════════

/// #7016 : N envois simultanés d'un même devis `draft` → N × 200 idempotents,
/// aucun 5xx, mais EXACTEMENT UNE notification `quote_received` pour le
/// patient (un double-clic sur « Envoyer » ne doit pas doubler la
/// notification, contrairement à un read-then-write sans verrou).
#[tokio::test]
async fn concurrent_quote_send_yields_exactly_one_patient_notification() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed_quote_with_status(&db, "draft").await;

    let router = app(state_with(app_pool().await));
    let results = post_concurrently(
        router,
        format!("/v1/cabinet/quotes/{}/send", f.quote_id),
        make_pro_jwt(f.practitioner_user_id, f.cabinet_id, "practitioner"),
    )
    .await;

    let statuses: Vec<StatusCode> = results.iter().map(|(s, _)| *s).collect();
    assert!(
        statuses.iter().all(|s| !s.is_server_error()),
        "aucun 5xx attendu sur une course prévisible, obtenu {statuses:?}"
    );
    assert!(
        statuses.iter().all(|s| *s == StatusCode::OK),
        "chaque envoi doit renvoyer 200 (idempotent), obtenu {results:?}"
    );

    let notifications: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM notification WHERE app_user_id = $1 AND kind = $2",
    )
    .bind(f.patient_account_user_id)
    .bind("quote_received")
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(
        notifications, 1,
        "un seul geste d'envoi doit produire UNE seule notification patient, obtenu {results:?}"
    );

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let status: String = sqlx::query_scalar("SELECT status FROM quote WHERE id = $1")
        .bind(f.quote_id)
        .fetch_one(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(status, "sent");

    cleanup_quote(&db, &f).await;
}
