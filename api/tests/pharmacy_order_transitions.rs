//! Tests d'intégration : machine à états + QR de retrait (lot B3, issue #3308)
//! POST /v1/pharmacy/orders/{id}/accept|ready|reject · POST …/pickup-scan
//! POST /v1/account/orders/{id}/cancel · GET …/{id}/pickup-token

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

const JWT_SECRET: &str = "test-jwt-secret-pharmacy-transitions";

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

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600
}

fn patient_jwt(user_id: Uuid, account_id: Uuid) -> String {
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": account_id, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn pharma_jwt(pharmacy_id: Uuid, role: &str) -> String {
    encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "pharma", "pharmacy_id": pharmacy_id,
                "role": role, "exp": exp()}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    user_id: Uuid,
    account_id: Uuid,
    pharmacy_id: Uuid,
    order_id: Uuid,
}

/// Fixture : commande `received` prête à transiter (insérée directement).
async fn seed(db: &PgPool) -> Fixture {
    let user_id = Uuid::new_v4();
    let pro_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let document_id = Uuid::new_v4();
    let prescription_id = Uuid::new_v4();
    let pharmacy_id = Uuid::new_v4();
    let order_id = Uuid::new_v4();

    for (id, kind) in [(user_id, "patient"), (pro_user_id, "pro")] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(id)
        .bind(format!("tr-{}@nubia.test", id))
        .bind(kind)
        .execute(db)
        .await
        .unwrap();
    }
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Jean', 'Demo')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet TR')")
        .bind(cabinet_id)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Jean', 'Demo', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(pro_user_id)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, \
                               mime_type, sha256, scan_status, uploaded_by, size_bytes) \
         VALUES ($1, $2, $3, 'ordonnance', $4, 'ordo.pdf', 'application/pdf', \
                 repeat('0', 64), 'clean', $5, 0)",
    )
    .bind(document_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(format!("sk-{}", document_id))
    .bind(pro_user_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, \
                                   document_id, signed_at) \
         VALUES ($1, $2, $3, $4, 'sent', $5, now())",
    )
    .bind(prescription_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(document_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Pharmacie TR', true)",
    )
    .bind(pharmacy_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO pharmacy_order (id, pharmacy_id, cabinet_id, patient_account_id, \
                                     prescription_id, document_id, created_by_kind, \
                                     pharmacy_name, patient_display_name) \
         VALUES ($1, $2, $3, $4, $5, $6, 'patient', 'Pharmacie TR', 'Jean D.')",
    )
    .bind(order_id)
    .bind(pharmacy_id)
    .bind(cabinet_id)
    .bind(account_id)
    .bind(prescription_id)
    .bind(document_id)
    .execute(db)
    .await
    .unwrap();

    Fixture {
        user_id,
        account_id,
        pharmacy_id,
        order_id,
    }
}

/// Deuxième commande dans LA MÊME pharmacie que `seed`, pour un patient
/// distinct — nécessaire pour reproduire #6349 (scan croisé entre deux
/// commandes `ready` d'un même tenant).
async fn seed_second_order(db: &PgPool, pharmacy_id: Uuid) -> Fixture {
    let user_id = Uuid::new_v4();
    let pro_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let document_id = Uuid::new_v4();
    let prescription_id = Uuid::new_v4();
    let order_id = Uuid::new_v4();

    for (id, kind) in [(user_id, "patient"), (pro_user_id, "pro")] {
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', $3)",
        )
        .bind(id)
        .bind(format!("tr2-{}@nubia.test", id))
        .bind(kind)
        .execute(db)
        .await
        .unwrap();
    }
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Marc', 'Dubois')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale) VALUES ($1, 'Cabinet TR2')")
        .bind(cabinet_id)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Marc', 'Dubois', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(pro_user_id)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO document (id, cabinet_id, patient_id, category, storage_key, filename, \
                               mime_type, sha256, scan_status, uploaded_by, size_bytes) \
         VALUES ($1, $2, $3, 'ordonnance', $4, 'ordo.pdf', 'application/pdf', \
                 repeat('0', 64), 'clean', $5, 0)",
    )
    .bind(document_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(format!("sk-{}", document_id))
    .bind(pro_user_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, \
                                   document_id, signed_at) \
         VALUES ($1, $2, $3, $4, 'sent', $5, now())",
    )
    .bind(prescription_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(document_id)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO pharmacy_order (id, pharmacy_id, cabinet_id, patient_account_id, \
                                     prescription_id, document_id, created_by_kind, \
                                     pharmacy_name, patient_display_name) \
         VALUES ($1, $2, $3, $4, $5, $6, 'patient', 'Pharmacie TR', 'Marc D.')",
    )
    .bind(order_id)
    .bind(pharmacy_id)
    .bind(cabinet_id)
    .bind(account_id)
    .bind(prescription_id)
    .bind(document_id)
    .execute(db)
    .await
    .unwrap();

    Fixture {
        user_id,
        account_id,
        pharmacy_id,
        order_id,
    }
}

async fn call(
    method: &str,
    uri: &str,
    token: &str,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("Authorization", format!("Bearer {}", token));
    if body.is_some() {
        builder = builder.header("content-type", "application/json");
    }
    let response = app(AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        builder
            .body(match body {
                Some(v) => Body::from(v.to_string()),
                None => Body::empty(),
            })
            .unwrap(),
    )
    .await
    .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v = serde_json::from_slice(&bytes).unwrap_or_else(|_| json!({}));
    (status, v)
}

// ── Happy path complet : received → preparing → ready → picked_up ────────────

#[tokio::test]
async fn full_lifecycle_received_to_picked_up() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharma = pharma_jwt(fx.pharmacy_id, "preparator");
    let patient = patient_jwt(fx.user_id, fx.account_id);

    // Le token de retrait n'est pas disponible avant `ready`.
    let (status, _) = call(
        "GET",
        &format!("/v1/account/orders/{}/pickup-token", fx.order_id),
        &patient,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "pas de token avant ready");

    // accept : received → preparing.
    let (status, order) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/accept", fx.order_id),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {order}");
    assert_eq!(order["status"], "preparing");

    // ready : preparing → ready.
    let (status, order) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/ready", fx.order_id),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(order["status"], "ready");
    assert!(order["ready_at"].is_string());

    // Le patient génère son QR (token opaque, jamais stocké en clair).
    let (status, token_body) = call(
        "GET",
        &format!("/v1/account/orders/{}/pickup-token", fx.order_id),
        &patient,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let token = token_body["token"].as_str().unwrap().to_string();
    assert!(token.len() >= 64);

    // #3812 : un GET est safe/idempotent — un ré-appel dans la fenêtre de
    // validité renvoie le MÊME token (pas de re-render/retry qui invalide le
    // QR déjà affiché).
    let (status, token_body2) = call(
        "GET",
        &format!("/v1/account/orders/{}/pickup-token", fx.order_id),
        &patient,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let token2 = token_body2["token"].as_str().unwrap().to_string();
    assert_eq!(token, token2, "un GET répété doit renvoyer le même token");

    // Scan avec le token (identique aux deux appels) : ready → picked_up.
    let (status, order) = call(
        "POST",
        "/v1/pharmacy/orders/pickup-scan",
        &pharma,
        Some(json!({"token": token2, "expected_order_id": fx.order_id})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {order}");
    assert_eq!(order["status"], "picked_up");
    assert!(order["picked_up_at"].is_string());

    // Double scan → 409 (single-use).
    let (status, _) = call(
        "POST",
        "/v1/pharmacy/orders/pickup-scan",
        &pharma,
        Some(json!({"token": token2, "expected_order_id": fx.order_id})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

// ── #3812 : GET pickup-token safe/idempotent ──────────────────────────────────

#[tokio::test]
async fn pickup_token_repeated_get_returns_identical_token_and_expiry() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharma = pharma_jwt(fx.pharmacy_id, "preparator");
    let patient = patient_jwt(fx.user_id, fx.account_id);

    call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/accept", fx.order_id),
        &pharma,
        None,
    )
    .await;
    call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/ready", fx.order_id),
        &pharma,
        None,
    )
    .await;

    let mut tokens = Vec::new();
    let mut expiries = Vec::new();
    for _ in 0..3 {
        let (status, body) = call(
            "GET",
            &format!("/v1/account/orders/{}/pickup-token", fx.order_id),
            &patient,
            None,
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        tokens.push(body["token"].as_str().unwrap().to_string());
        expiries.push(body["expires_at"].as_str().unwrap().to_string());
    }

    assert!(
        tokens.iter().all(|t| t == &tokens[0]),
        "3 GET consécutifs doivent renvoyer le même token : {tokens:?}"
    );
    assert!(
        expiries.iter().all(|e| e == &expiries[0]),
        "expires_at ne doit pas bouger tant que le token précédent est valide"
    );

    // #4273/QA-20260722-1 : le dernier token émis (pas seulement le premier)
    // doit scanner en picked_up — repro exacte du bug (nanoseconde en mémoire
    // vs microseconde en DB désynchronisant le HMAC du 2e appel).
    let (scan_status, scan_body) = call(
        "POST",
        "/v1/pharmacy/orders/pickup-scan",
        &pharma,
        Some(json!({
            "token": tokens.last().unwrap(),
            "expected_order_id": fx.order_id,
        })),
    )
    .await;
    assert_eq!(
        scan_status,
        StatusCode::OK,
        "le dernier token émis doit scanner en 200, pas 404 : {scan_body:?}"
    );
    assert_eq!(scan_body["status"], "picked_up");
}

// ── Transitions illégales ─────────────────────────────────────────────────────

#[tokio::test]
async fn illegal_transitions_return_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharma = pharma_jwt(fx.pharmacy_id, "pharmacist");

    // ready sans accept → 409 (pas de saut d'étape).
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/ready", fx.order_id),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // accept deux fois → 409.
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/accept", fx.order_id),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/accept", fx.order_id),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // reject après accept (preparing) → 200 : assertion corrigée (test
    // périmé). #3723 a élargi `reject` à received|preparing|ready (une
    // commande "ready" ne pouvait plus jamais être rejetée/annulée avant ce
    // fix — cul-de-sac) sans que cette assertion, qui datait d'avant #3723,
    // ait été mise à jour. Repéré en vérifiant #4273 (fichier voisin).
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/reject", fx.order_id),
        &pharma,
        Some(json!({"reason": "trop tard"})),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::OK,
        "reject reste autorisé en preparing (#3723)"
    );
}

// ── Refus ─────────────────────────────────────────────────────────────────────

#[tokio::test]
async fn reject_requires_reason_and_decision_role() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;

    // Le préparateur ne peut pas refuser → 403.
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/reject", fx.order_id),
        &pharma_jwt(fx.pharmacy_id, "preparator"),
        Some(json!({"reason": "Produit indisponible"})),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // Motif vide → 422.
    let pharmacist = pharma_jwt(fx.pharmacy_id, "pharmacist");
    let (status, _) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/reject", fx.order_id),
        &pharmacist,
        Some(json!({"reason": "  "})),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Refus valide → rejected + motif exposé.
    let (status, order) = call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/reject", fx.order_id),
        &pharmacist,
        Some(json!({"reason": "Produit indisponible"})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(order["status"], "rejected");
    assert_eq!(order["rejection_reason"], "Produit indisponible");
}

// ── Annulation patient ────────────────────────────────────────────────────────

#[tokio::test]
async fn patient_cancels_before_ready_only() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let patient = patient_jwt(fx.user_id, fx.account_id);
    let pharma = pharma_jwt(fx.pharmacy_id, "pharmacist");

    // Un autre compte → 404 (RLS).
    let other_user = Uuid::new_v4();
    let other_account = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(other_user)
    .bind(format!("intrus-{}@nubia.test", other_user))
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Intrus', 'X')",
    )
    .bind(other_account)
    .bind(other_user)
    .execute(&db)
    .await
    .unwrap();
    let (status, _) = call(
        "POST",
        &format!("/v1/account/orders/{}/cancel", fx.order_id),
        &patient_jwt(other_user, other_account),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Annulation depuis received → 200.
    let (status, order) = call(
        "POST",
        &format!("/v1/account/orders/{}/cancel", fx.order_id),
        &patient,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(order["status"], "cancelled");

    // Une commande prête n'est plus annulable : nouvelle fixture → ready → 409.
    let fx2 = seed(&db).await;
    let pharma2 = pharma_jwt(fx2.pharmacy_id, "pharmacist");
    call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/accept", fx2.order_id),
        &pharma2,
        None,
    )
    .await;
    call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/ready", fx2.order_id),
        &pharma2,
        None,
    )
    .await;
    let (status, _) = call(
        "POST",
        &format!("/v1/account/orders/{}/cancel", fx2.order_id),
        &patient_jwt(fx2.user_id, fx2.account_id),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let _ = pharma;
}

// ── Scan : cross-tenant et expiration ─────────────────────────────────────────

#[tokio::test]
async fn pickup_scan_cross_tenant_404_and_expired_410() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx = seed(&db).await;
    let pharma = pharma_jwt(fx.pharmacy_id, "pharmacist");
    let patient = patient_jwt(fx.user_id, fx.account_id);

    call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/accept", fx.order_id),
        &pharma,
        None,
    )
    .await;
    call(
        "POST",
        &format!("/v1/pharmacy/orders/{}/ready", fx.order_id),
        &pharma,
        None,
    )
    .await;
    let (_, token_body) = call(
        "GET",
        &format!("/v1/account/orders/{}/pickup-token", fx.order_id),
        &patient,
        None,
    )
    .await;
    let token = token_body["token"].as_str().unwrap().to_string();

    // Une autre pharmacie scanne le token → 404 (anti-énumération, RLS).
    let other_pharmacy = Uuid::new_v4();
    sqlx::query("INSERT INTO pharmacy (id, raison_sociale, is_listed) VALUES ($1, 'Autre', true)")
        .bind(other_pharmacy)
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = call(
        "POST",
        "/v1/pharmacy/orders/pickup-scan",
        &pharma_jwt(other_pharmacy, "pharmacist"),
        Some(json!({"token": token.clone(), "expected_order_id": fx.order_id})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Token expiré → 410.
    sqlx::query(
        "UPDATE pharmacy_order SET pickup_token_expires_at = now() - interval '1 minute' \
         WHERE id = $1",
    )
    .bind(fx.order_id)
    .execute(&db)
    .await
    .unwrap();
    let (status, _) = call(
        "POST",
        "/v1/pharmacy/orders/pickup-scan",
        &pharma,
        Some(json!({"token": token, "expected_order_id": fx.order_id})),
    )
    .await;
    assert_eq!(status, StatusCode::GONE);

    // Token inconnu → 404.
    let (status, _) = call(
        "POST",
        "/v1/pharmacy/orders/pickup-scan",
        &pharma,
        Some(json!({"token": "inconnu", "expected_order_id": fx.order_id})),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

// ── #6349 : scan croisé — repro exacte (cul-de-sac irréversible) ──────────────

#[tokio::test]
async fn pickup_scan_mismatch_makes_no_transition() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let fx_a = seed(&db).await; // CMD-A : la commande ouverte à l'écran.
    let fx_b = seed_second_order(&db, fx_a.pharmacy_id).await; // CMD-B : le QR réellement scanné.
    let pharma = pharma_jwt(fx_a.pharmacy_id, "pharmacist");
    let patient_b = patient_jwt(fx_b.user_id, fx_b.account_id);

    for fx in [&fx_a, &fx_b] {
        call(
            "POST",
            &format!("/v1/pharmacy/orders/{}/accept", fx.order_id),
            &pharma,
            None,
        )
        .await;
        call(
            "POST",
            &format!("/v1/pharmacy/orders/{}/ready", fx.order_id),
            &pharma,
            None,
        )
        .await;
    }

    let (_, token_body_b) = call(
        "GET",
        &format!("/v1/account/orders/{}/pickup-token", fx_b.order_id),
        &patient_b,
        None,
    )
    .await;
    let token_b = token_body_b["token"].as_str().unwrap().to_string();

    // Le pharmacien a CMD-A en main mais scanne (ou saisit) le QR de CMD-B.
    let (status, body) = call(
        "POST",
        "/v1/pharmacy/orders/pickup-scan",
        &pharma,
        Some(json!({"token": token_b, "expected_order_id": fx_a.order_id})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "body: {body}");
    assert_eq!(body["code"], "pickup_order_mismatch");
    assert_eq!(body["order"]["id"], fx_b.order_id.to_string());

    // Aucune écriture : les DEUX commandes restent `ready` (pas de cul-de-sac,
    // pas de commande basculée `picked_up` à l'insu du pharmacien).
    let (status, order_a) = call(
        "GET",
        &format!("/v1/pharmacy/orders/{}", fx_a.order_id),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(order_a["status"], "ready", "body: {order_a}");

    let (status, order_b) = call(
        "GET",
        &format!("/v1/pharmacy/orders/{}", fx_b.order_id),
        &pharma,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(order_b["status"], "ready", "body: {order_b}");
    assert!(order_b["picked_up_at"].is_null());

    // Le token de CMD-B n'a pas été « brûlé » par le refus : il reste
    // utilisable pour le scan correct (sur la bonne commande).
    let (status, order_b2) = call(
        "POST",
        "/v1/pharmacy/orders/pickup-scan",
        &pharma,
        Some(json!({"token": token_b, "expected_order_id": fx_b.order_id})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "body: {order_b2}");
    assert_eq!(order_b2["status"], "picked_up");
}
