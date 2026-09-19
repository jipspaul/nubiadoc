//! Tests d'intégration (#7203/DP-F5.b) :
//! - `POST/GET/DELETE /v1/cabinet/quotes/:id/attachments` + lecture patient
//!   `GET /v1/quotes/:id/attachments`.
//! - `GET/POST /v1/cabinet/quotes/:id/attestation` + lecture/signature
//!   patient `GET /v1/quotes/:id/attestation` + `POST …/attestation/sign`.
//! - Règle : tant qu'une attestation existe et n'est pas signée,
//!   `POST /v1/quotes/:id/sign` (signature du devis) renvoie `409`.

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

const JWT_SECRET: &str = "test-jwt-secret-quote-attachments-attestation";

/// Id d'un courrier type global seedé (migration 0267), utilisable comme
/// `template_ref` valide sans dépendre d'un cabinet particulier.
const GLOBAL_LETTER_TEMPLATE_ID: &str = "02670000-0000-0000-0000-000000000001";

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

struct Fixture {
    cabinet_id: Uuid,
    patient_account_user_id: Uuid,
    patient_account_id: Uuid,
    patient_id: Uuid,
    quote_id: Uuid,
    document_id: Uuid,
}

/// Seed : cabinet + patient (compte + fiche) + devis au statut `status` +
/// un document (`consentement`) déjà rattaché au patient, réutilisable comme
/// pièce jointe (`document_id`).
async fn seed(db: &PgPool, status: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let account_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();
    let document_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(account_user_id)
    .bind(format!("quote-attach+{account_user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Test', 'Attachment')",
    )
    .bind(account_id)
    .bind(account_user_id)
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet QuoteAttach {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Test', 'Attachment', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
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

    sqlx::query(
        "INSERT INTO document \
         (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, sha256) \
         VALUES ($1, $2, $3, 'consentement', 'test/consentement.pdf', 'consentement.pdf', \
                 'application/pdf', $4)",
    )
    .bind(document_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind("0".repeat(64))
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        patient_account_user_id: account_user_id,
        patient_account_id: account_id,
        patient_id,
        quote_id,
        document_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_attachment WHERE quote_id = $1")
        .bind(f.quote_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote_information_attestation WHERE quote_id = $1")
        .bind(f.quote_id)
        .execute(&mut *tx)
        .await
        .ok();
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
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();

    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.patient_account_user_id)
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

async fn call(
    state: AppState,
    method: &str,
    uri: String,
    token: String,
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

// ── Pièces jointes ───────────────────────────────────────────────────────

// Test 1 : cabinet dépose une pièce (document_id), la liste, puis la retire.
#[tokio::test]
async fn cabinet_can_create_list_and_delete_attachment() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "draft").await;
    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "practitioner");

    let (status, created) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/cabinet/quotes/{}/attachments", f.quote_id),
        token.clone(),
        Some(json!({ "kind": "consent", "document_id": f.document_id })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(created["kind"], "consent");
    assert_eq!(created["document_id"], f.document_id.to_string());
    let attachment_id = created["id"].as_str().unwrap().to_string();

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        format!("/v1/cabinet/quotes/{}/attachments", f.quote_id),
        token.clone(),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list["data"].as_array().unwrap().len(), 1);

    let (status, _) = call(
        state_with(app_pool().await),
        "DELETE",
        format!(
            "/v1/cabinet/quotes/{}/attachments/{attachment_id}",
            f.quote_id
        ),
        token.clone(),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        format!("/v1/cabinet/quotes/{}/attachments", f.quote_id),
        token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list["data"].as_array().unwrap().len(), 0);

    cleanup(&db, &f).await;
}

// Test 2 : document_id ET template_ref fournis ensemble → 422 (XOR).
#[tokio::test]
async fn attachment_with_both_document_and_template_ref_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "draft").await;
    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "practitioner");

    let (status, body) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/cabinet/quotes/{}/attachments", f.quote_id),
        token,
        Some(json!({
            "kind": "consent",
            "document_id": f.document_id,
            "template_ref": GLOBAL_LETTER_TEMPLATE_ID,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body["code"], "validation_error");

    cleanup(&db, &f).await;
}

// Test 3 : modèle de courrier global (`template_ref`) → 201.
#[tokio::test]
async fn attachment_with_valid_letter_template_ref_returns_201() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "draft").await;
    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "practitioner");

    let (status, body) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/cabinet/quotes/{}/attachments", f.quote_id),
        token,
        Some(json!({ "kind": "letter", "template_ref": GLOBAL_LETTER_TEMPLATE_ID })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(body["template_ref"], GLOBAL_LETTER_TEMPLATE_ID);
    assert!(body["document_id"].is_null());

    cleanup(&db, &f).await;
}

// Test 4 : devis déjà signé → 409 quote_locked, pas de nouvelle pièce jointe.
#[tokio::test]
async fn attachment_creation_on_signed_quote_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "signed").await;
    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "practitioner");

    let (status, body) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/cabinet/quotes/{}/attachments", f.quote_id),
        token,
        Some(json!({ "kind": "consent", "document_id": f.document_id })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "quote_locked");

    cleanup(&db, &f).await;
}

// Test 5 : le patient voit les pièces jointes d'un devis envoyé.
#[tokio::test]
async fn patient_sees_attachments_of_sent_quote() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "sent").await;
    let pro_token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/cabinet/quotes/{}/attachments", f.quote_id),
        pro_token,
        Some(json!({ "kind": "consent", "document_id": f.document_id })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        format!("/v1/quotes/{}/attachments", f.quote_id),
        make_patient_jwt(f.patient_account_user_id, f.patient_account_id),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let data = list["data"].as_array().unwrap();
    assert_eq!(data.len(), 1);
    assert_eq!(data[0]["kind"], "consent");

    cleanup(&db, &f).await;
}

// Test 6 : un devis brouillon reste invisible du patient — liste vide, pas d'erreur.
#[tokio::test]
async fn patient_does_not_see_attachments_of_draft_quote() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "draft").await;
    let pro_token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/cabinet/quotes/{}/attachments", f.quote_id),
        pro_token,
        Some(json!({ "kind": "consent", "document_id": f.document_id })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, list) = call(
        state_with(app_pool().await),
        "GET",
        format!("/v1/quotes/{}/attachments", f.quote_id),
        make_patient_jwt(f.patient_account_user_id, f.patient_account_id),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list["data"].as_array().unwrap().len(), 0);

    cleanup(&db, &f).await;
}

// ── Attestation d'information ────────────────────────────────────────────

// Test 7 : une attestation non signée existe déjà → 409 sur un second dépôt.
#[tokio::test]
async fn second_attestation_while_first_unsigned_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "sent").await;
    let token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "practitioner");

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/cabinet/quotes/{}/attestation", f.quote_id),
        token.clone(),
        Some(json!({ "body": "Je reconnais avoir été informé(e) des risques." })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, body) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/cabinet/quotes/{}/attestation", f.quote_id),
        token,
        Some(json!({ "body": "Deuxième version du texte." })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "attestation_already_pending");

    cleanup(&db, &f).await;
}

// Test 8 : attestation non signée → la signature du devis est bloquée (409),
// puis débloquée une fois l'attestation signée par le patient.
#[tokio::test]
async fn unsigned_attestation_blocks_quote_sign_until_signed() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "sent").await;
    let pro_token = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "practitioner");
    let patient_token = make_patient_jwt(f.patient_account_user_id, f.patient_account_id);

    let (status, _) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/cabinet/quotes/{}/attestation", f.quote_id),
        pro_token,
        Some(json!({ "body": "Je reconnais avoir été informé(e) des risques." })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    // Tant que l'attestation n'est pas signée : /sign refuse.
    let (status, body) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/quotes/{}/sign", f.quote_id),
        patient_token.clone(),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(body["code"], "attestation_not_signed");

    // Le patient consulte puis signe l'attestation.
    let (status, attestation) = call(
        state_with(app_pool().await),
        "GET",
        format!("/v1/quotes/{}/attestation", f.quote_id),
        patient_token.clone(),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(attestation["signed_at"].is_null());

    let (status, signed) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/quotes/{}/attestation/sign", f.quote_id),
        patient_token.clone(),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(signed["signed"], true);
    let signed_at = signed["signed_at"].as_str().unwrap().to_string();

    // Idempotence : un second appel renvoie le même `signed_at`.
    let (status, signed_again) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/quotes/{}/attestation/sign", f.quote_id),
        patient_token.clone(),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(signed_again["signed_at"], signed_at);

    // L'attestation signée ne bloque plus la signature du devis.
    let (status, body) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/quotes/{}/sign", f.quote_id),
        patient_token,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["signed"], true);

    cleanup(&db, &f).await;
}

// Test 9 : régression — sans attestation, la signature du devis fonctionne
// toujours (comportement pré-#7203 inchangé).
#[tokio::test]
async fn sign_quote_without_attestation_still_works() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db, "sent").await;

    let (status, body) = call(
        state_with(app_pool().await),
        "POST",
        format!("/v1/quotes/{}/sign", f.quote_id),
        make_patient_jwt(f.patient_account_user_id, f.patient_account_id),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["signed"], true);

    cleanup(&db, &f).await;
}
