//! Tests d'intégration : `/v1/account/access-requests*` (#6119).
//!
//! Invitation d'un proche ADULTE — distinct de `/v1/account/dependents`
//! (compte géré sans mot de passe, pour un mineur) : ici l'invité a son
//! propre compte patient et n'obtient qu'un accès en lecture, après avoir
//! accepté. Couvre les 7 routes absentes avant ce fix (404 uniforme).

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

const JWT_SECRET: &str = "test-jwt-secret-access-requests";

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

async fn create_patient_account(db: &PgPool, label: &str) -> (Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("{}+{}@nubia.test", label, user_id))
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Prenom', 'Nom')",
    )
    .bind(account_id)
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
    (user_id, account_id)
}

async fn test_state() -> AppState {
    AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn send_request(token: &str, body: Value) -> axum::response::Response {
    app(test_state().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/access-requests")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap()
}

async fn post_action(token: &str, id: &str, action: &str) -> axum::response::Response {
    app(test_state().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/account/access-requests/{}/{}", id, action))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap()
}

async fn body_json(response: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

// ── Cycle complet : envoi → liste → acceptation → révocation ────────────────

#[tokio::test]
async fn access_request_full_lifecycle() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (requester_user, requester_account) = create_patient_account(&db, "ar-requester").await;
    let (invitee_user, invitee_account) = create_patient_account(&db, "ar-invitee").await;

    let requester_token = make_patient_jwt(requester_user, requester_account);
    let invitee_token = make_patient_jwt(invitee_user, invitee_account);

    // 1. Envoi — 201 + statut envoyee.
    let created = send_request(
        &requester_token,
        json!({
            "first_name": "Jean",
            "last_name": "Dupont",
            "relationship": "conjoint",
            "channel": "email",
            "scope": ["rendez_vous", "documents"],
            "email": "jean.dupont@example.test",
        }),
    )
    .await;
    assert_eq!(created.status(), StatusCode::CREATED);
    let created_json = body_json(created).await;
    assert_eq!(created_json["status"], "envoyee");
    assert_eq!(created_json["channel"], "email");
    let request_id = created_json["id"].as_str().unwrap().to_string();
    Uuid::parse_str(&request_id).expect("id doit être un UUID valide");

    // 2. Liste — la demande envoyée apparaît pour le requester.
    let list = app(test_state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/access-requests")
                .header("Authorization", format!("Bearer {}", requester_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(list.status(), StatusCode::OK);
    let list_json = body_json(list).await;
    let items = list_json.as_array().unwrap();
    assert!(items.iter().any(|it| it["id"] == request_id));

    // 3. Le requester ne peut pas accepter sa propre demande → 404.
    let self_accept = post_action(&requester_token, &request_id, "accept").await;
    assert_eq!(self_accept.status(), StatusCode::NOT_FOUND);

    // 4. L'invité accepte — 200 + statut acceptee.
    let accepted = post_action(&invitee_token, &request_id, "accept").await;
    assert_eq!(accepted.status(), StatusCode::OK);
    let accepted_json = body_json(accepted).await;
    assert_eq!(accepted_json["status"], "acceptee");

    // 5. Une seconde acceptation (déjà décidée) → 404.
    let re_accept = post_action(&invitee_token, &request_id, "accept").await;
    assert_eq!(re_accept.status(), StatusCode::NOT_FOUND);

    // 6. L'invité révoque l'accès accordé — 204.
    let revoked = post_action(&invitee_token, &request_id, "revoke").await;
    assert_eq!(revoked.status(), StatusCode::NO_CONTENT);

    // 7. Une seconde révocation → 404 (déjà révoqué).
    let re_revoke = post_action(&invitee_token, &request_id, "revoke").await;
    assert_eq!(re_revoke.status(), StatusCode::NOT_FOUND);

    // 8. Le requester lui-même ne peut pas révoquer (pas l'invité) → 404.
    let requester_revoke = post_action(&requester_token, &request_id, "revoke").await;
    assert_eq!(requester_revoke.status(), StatusCode::NOT_FOUND);
}

// ── Refus ────────────────────────────────────────────────────────────────

#[tokio::test]
async fn access_request_refuse() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (requester_user, requester_account) = create_patient_account(&db, "ar-req-refuse").await;
    let (invitee_user, invitee_account) = create_patient_account(&db, "ar-inv-refuse").await;
    let requester_token = make_patient_jwt(requester_user, requester_account);
    let invitee_token = make_patient_jwt(invitee_user, invitee_account);

    let created = send_request(
        &requester_token,
        json!({
            "first_name": "Marie",
            "last_name": "Martin",
            "relationship": "autre",
            "channel": "sms",
            "scope": [],
            "phone": "+33600000001",
        }),
    )
    .await;
    assert_eq!(created.status(), StatusCode::CREATED);
    let request_id = body_json(created).await["id"].as_str().unwrap().to_string();

    let refused = post_action(&invitee_token, &request_id, "refuse").await;
    assert_eq!(refused.status(), StatusCode::OK);
    assert_eq!(body_json(refused).await["status"], "refusee");

    // Refusée → n'apparaît plus comme acceptable (déjà décidée).
    let re_accept = post_action(&invitee_token, &request_id, "accept").await;
    assert_eq!(re_accept.status(), StatusCode::NOT_FOUND);
}

// ── Resend + cancel (DELETE, soft-delete) ───────────────────────────────────

#[tokio::test]
async fn access_request_resend_then_cancel_hides_from_list() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (requester_user, requester_account) = create_patient_account(&db, "ar-req-cancel").await;
    let requester_token = make_patient_jwt(requester_user, requester_account);

    let created = send_request(
        &requester_token,
        json!({
            "first_name": "Paul",
            "last_name": "Petit",
            "relationship": "enfant",
            "channel": "email",
            "scope": ["dossier_medical"],
            "email": "paul.petit@example.test",
        }),
    )
    .await;
    assert_eq!(created.status(), StatusCode::CREATED);
    let request_id = body_json(created).await["id"].as_str().unwrap().to_string();

    // Resend — 200, toujours envoyee.
    let resent = post_action(&requester_token, &request_id, "resend").await;
    assert_eq!(resent.status(), StatusCode::OK);
    assert_eq!(body_json(resent).await["status"], "envoyee");

    // Cancel — 204.
    let cancel = app(test_state().await)
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/account/access-requests/{}", request_id))
                .header("Authorization", format!("Bearer {}", requester_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(cancel.status(), StatusCode::NO_CONTENT);

    // La demande annulée disparaît de la liste (soft-delete applicatif, jamais de DELETE SQL).
    let list = app(test_state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/access-requests")
                .header("Authorization", format!("Bearer {}", requester_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let items = body_json(list).await;
    assert!(!items
        .as_array()
        .unwrap()
        .iter()
        .any(|it| it["id"] == request_id));

    let row_still_exists: i64 =
        sqlx::query_scalar("SELECT count(*) FROM account_access_request WHERE id = $1::uuid")
            .bind(&request_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(
        row_still_exists, 1,
        "cancel ne doit jamais DELETE la ligne SQL (§07 §10)"
    );

    // Une demande annulée ne peut plus être relancée ni annulée à nouveau.
    let resend_after_cancel = post_action(&requester_token, &request_id, "resend").await;
    assert_eq!(resend_after_cancel.status(), StatusCode::NOT_FOUND);
}

// ── Doublon (#4475-like) ────────────────────────────────────────────────────

#[tokio::test]
async fn access_request_duplicate_active_invite_returns_409() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (requester_user, requester_account) = create_patient_account(&db, "ar-req-dup").await;
    let requester_token = make_patient_jwt(requester_user, requester_account);

    let body = json!({
        "first_name": "Sophie",
        "last_name": "Bernard",
        "relationship": "conjoint",
        "channel": "email",
        "scope": ["rendez_vous"],
        "email": "sophie.bernard@example.test",
    });

    let first = send_request(&requester_token, body.clone()).await;
    assert_eq!(first.status(), StatusCode::CREATED);

    let second = send_request(&requester_token, body).await;
    assert_eq!(second.status(), StatusCode::CONFLICT);
    assert_eq!(body_json(second).await["code"], "duplicate_access_request");
}

// ── Validation : canal sms sans téléphone → 422 ─────────────────────────────

#[tokio::test]
async fn access_request_sms_without_phone_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (requester_user, requester_account) = create_patient_account(&db, "ar-req-invalid").await;
    let requester_token = make_patient_jwt(requester_user, requester_account);

    let response = send_request(
        &requester_token,
        json!({
            "first_name": "Luc",
            "last_name": "Moreau",
            "relationship": "autre",
            "channel": "sms",
            "scope": [],
        }),
    )
    .await;
    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}
