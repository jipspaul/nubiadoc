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

// ── #7009 : le rattachement direct est réservé à un enfant mineur ───────────

async fn post_dependent(token: &str, body: Value) -> axum::response::Response {
    app(test_state().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/account/dependents")
                .header("Authorization", format!("Bearer {}", token))
                .header("Content-Type", "application/json")
                .body(Body::from(serde_json::to_vec(&body).unwrap()))
                .unwrap(),
        )
        .await
        .unwrap()
}

async fn get_json(token: &str, uri: &str) -> Value {
    let response = app(test_state().await)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(uri)
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK, "GET {uri}");
    body_json(response).await
}

/// Compte patient dont l'e-mail `app_user` est imposé (pour qu'une demande
/// d'accès adressée à cet e-mail puisse lui être rapprochée).
async fn create_patient_account_with_email(
    db: &PgPool,
    email: &str,
    first_name: &str,
    last_name: &str,
) -> (Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(email)
    .execute(db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, $3, $4)",
    )
    .bind(account_id)
    .bind(user_id)
    .bind(first_name)
    .bind(last_name)
    .execute(db)
    .await
    .unwrap();
    (user_id, account_id)
}

async fn active_guardianship_count(db: &PgPool, guardian: Uuid, dependent: Uuid) -> i64 {
    sqlx::query_scalar(
        "SELECT count(*) FROM account_guardianship \
         WHERE guardian_account_id = $1 AND dependent_account_id = $2 AND active = true",
    )
    .bind(guardian)
    .bind(dependent)
    .fetch_one(db)
    .await
    .unwrap()
}

async fn notification_count(db: &PgPool, app_user_id: Uuid, kind: &str) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM notification WHERE app_user_id = $1 AND kind = $2")
        .bind(app_user_id)
        .bind(kind)
        .fetch_one(db)
        .await
        .unwrap()
}

#[tokio::test]
async fn direct_dependent_of_an_adult_is_refused_server_side() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (user, account) = create_patient_account(&db, "ar-adult-direct").await;
    let token = make_patient_jwt(user, account);

    // Conjoint sans date de naissance : exactement la requête émise par le
    // bouton « Envoyer la demande » avant ce fix (QA-20260915-19).
    let spouse = post_dependent(
        &token,
        json!({
            "first_name": "QA16Proof",
            "last_name": "ConsentementFacade",
            "relationship": "conjoint",
        }),
    )
    .await;
    assert_eq!(spouse.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body_json(spouse).await["code"], "adult_requires_consent");

    // Adulte de 41 ans déclaré « conjoint » avec date de naissance : refusé.
    let adult = post_dependent(
        &token,
        json!({
            "first_name": "QA16",
            "last_name": "AdulteSansAccord",
            "birth_date": "1985-04-12",
            "relationship": "conjoint",
        }),
    )
    .await;
    assert_eq!(adult.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body_json(adult).await["code"], "adult_requires_consent");

    // « Enfant » majeur : l'étiquette ne suffit pas, l'âge tranche.
    let adult_child = post_dependent(
        &token,
        json!({
            "first_name": "QA16",
            "last_name": "EnfantMajeur",
            "birth_date": "1985-04-12",
            "relationship": "enfant",
        }),
    )
    .await;
    assert_eq!(adult_child.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        body_json(adult_child).await["code"],
        "adult_requires_consent"
    );

    // « Enfant » sans date de naissance : rien ne prouve la minorité.
    let no_dob = post_dependent(
        &token,
        json!({
            "first_name": "QA16",
            "last_name": "SansDate",
            "relationship": "enfant",
        }),
    )
    .await;
    assert_eq!(no_dob.status(), StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(body_json(no_dob).await["code"], "validation_error");

    // Aucun compte géré n'a été créé par ces quatre tentatives.
    let count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM account_guardianship WHERE guardian_account_id = $1",
    )
    .bind(account)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(count, 0);

    // Le parcours enfant mineur reste inchangé (saisie directe).
    let minor = post_dependent(
        &token,
        json!({
            "first_name": "Lucas",
            "last_name": "Marchand",
            "birth_date": "2015-03-10",
            "relationship": "enfant",
        }),
    )
    .await;
    assert_eq!(minor.status(), StatusCode::CREATED);
}

// ── Demande → acceptation → accès ; refus → rien ; isolation ────────────────

#[tokio::test]
async fn access_request_grants_guardianship_only_after_acceptance() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (requester_user, requester_account) =
        create_patient_account_with_email(&db, &unique_email("julie"), "Julie", "Martin").await;
    let invitee_email = unique_email("emile");
    let (invitee_user, invitee_account) =
        create_patient_account_with_email(&db, &invitee_email, "Émile", "Martin").await;
    let (third_user, third_account) = create_patient_account(&db, "ar-third").await;

    let requester_token = make_patient_jwt(requester_user, requester_account);
    let invitee_token = make_patient_jwt(invitee_user, invitee_account);
    let third_token = make_patient_jwt(third_user, third_account);

    // 1. Envoi : demande en attente, e-mail + périmètre conservés, aucun accès.
    let created = send_request(
        &requester_token,
        json!({
            "first_name": "Émile",
            "last_name": "Martin",
            "relationship": "conjoint",
            "channel": "email",
            "scope": ["rendez_vous", "documents", "messages"],
            "email": invitee_email.to_uppercase(),
        }),
    )
    .await;
    assert_eq!(created.status(), StatusCode::CREATED);
    let created_json = body_json(created).await;
    assert_eq!(created_json["status"], "envoyee");
    assert_eq!(created_json["direction"], "sent");
    assert_eq!(
        created_json["scope"],
        json!(["rendez_vous", "documents", "messages"])
    );
    let request_id = created_json["id"].as_str().unwrap().to_string();

    assert_eq!(
        active_guardianship_count(&db, requester_account, invitee_account).await,
        0,
        "aucun accès ne doit exister tant que l'invité n'a pas accepté"
    );
    let dependents = get_json(&requester_token, "/v1/account/dependents").await;
    assert!(!dependents
        .as_array()
        .unwrap()
        .iter()
        .any(|d| d["dependent_account_id"] == invitee_account.to_string()));

    // 2. Délivrance : l'invité voit la demande reçue (avec le nom du
    //    demandeur) et une notification in-app a été déposée.
    let received = get_json(&invitee_token, "/v1/account/access-requests").await;
    let item = received
        .as_array()
        .unwrap()
        .iter()
        .find(|it| it["id"] == request_id)
        .expect("la demande doit apparaître côté invité");
    assert_eq!(item["direction"], "received");
    assert_eq!(item["status"], "envoyee");
    assert_eq!(item["requester_first_name"], "Julie");
    assert_eq!(item["requester_last_name"], "Martin");
    assert_eq!(
        notification_count(&db, invitee_user, "access_request_received").await,
        1
    );

    // 3. Isolation : un tiers ne voit pas la demande et ne peut pas la décider.
    let third_list = get_json(&third_token, "/v1/account/access-requests").await;
    assert!(!third_list
        .as_array()
        .unwrap()
        .iter()
        .any(|it| it["id"] == request_id));
    let third_accept = post_action(&third_token, &request_id, "accept").await;
    assert_eq!(third_accept.status(), StatusCode::NOT_FOUND);
    assert_eq!(
        active_guardianship_count(&db, requester_account, third_account).await,
        0
    );

    // 4. Acceptation avec périmètre ajusté (l'invité décide de l'étendue).
    let accepted = app(test_state().await)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/account/access-requests/{}/accept", request_id))
                .header("Authorization", format!("Bearer {}", invitee_token))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    serde_json::to_vec(&json!({"scope": ["rendez_vous"]})).unwrap(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(accepted.status(), StatusCode::OK);
    let accepted_json = body_json(accepted).await;
    assert_eq!(accepted_json["status"], "acceptee");
    assert_eq!(accepted_json["direction"], "received");
    assert_eq!(accepted_json["scope"], json!(["rendez_vous"]));

    // L'accès est désormais matérialisé : lien de tutelle délégué actif,
    // l'invité figure dans « Comptes que vous gérez » du demandeur.
    assert_eq!(
        active_guardianship_count(&db, requester_account, invitee_account).await,
        1
    );
    let authority: String = sqlx::query_scalar(
        "SELECT authority FROM account_guardianship \
         WHERE guardian_account_id = $1 AND dependent_account_id = $2 AND active = true",
    )
    .bind(requester_account)
    .bind(invitee_account)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(authority, "delegated");
    let dependents = get_json(&requester_token, "/v1/account/dependents").await;
    assert!(dependents
        .as_array()
        .unwrap()
        .iter()
        .any(|d| d["dependent_account_id"] == invitee_account.to_string()
            && d["relationship"] == "conjoint"));
    assert_eq!(
        notification_count(&db, requester_user, "access_request_decided").await,
        1
    );

    // 5. Le demandeur voit la demande acceptée (plus seulement les « envoyee »).
    let sent = get_json(&requester_token, "/v1/account/access-requests").await;
    let item = sent
        .as_array()
        .unwrap()
        .iter()
        .find(|it| it["id"] == request_id)
        .unwrap();
    assert_eq!(item["status"], "acceptee");
    assert_eq!(item["direction"], "sent");
    assert!(item["decided_at"].is_string());

    // 6. Révocation symétrique (#7004) : le demandeur peut aussi retirer l'accès.
    let revoked = post_action(&requester_token, &request_id, "revoke").await;
    assert_eq!(revoked.status(), StatusCode::NO_CONTENT);
    assert_eq!(
        active_guardianship_count(&db, requester_account, invitee_account).await,
        0
    );
    assert_eq!(
        notification_count(&db, invitee_user, "access_request_revoked").await,
        1
    );
    let sent = get_json(&requester_token, "/v1/account/access-requests").await;
    let item = sent
        .as_array()
        .unwrap()
        .iter()
        .find(|it| it["id"] == request_id)
        .unwrap();
    assert!(item["revoked_at"].is_string());
}

#[tokio::test]
async fn access_request_refused_grants_nothing() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (requester_user, requester_account) = create_patient_account(&db, "ar-req-nothing").await;
    let invitee_email = unique_email("refusant");
    let (invitee_user, invitee_account) =
        create_patient_account_with_email(&db, &invitee_email, "Nadia", "Refus").await;
    let requester_token = make_patient_jwt(requester_user, requester_account);
    let invitee_token = make_patient_jwt(invitee_user, invitee_account);

    let created = send_request(
        &requester_token,
        json!({
            "first_name": "Nadia",
            "last_name": "Refus",
            "relationship": "autre",
            "channel": "email",
            "scope": ["dossier_medical"],
            "email": invitee_email,
        }),
    )
    .await;
    assert_eq!(created.status(), StatusCode::CREATED);
    let request_id = body_json(created).await["id"].as_str().unwrap().to_string();

    let refused = post_action(&invitee_token, &request_id, "refuse").await;
    assert_eq!(refused.status(), StatusCode::OK);
    assert_eq!(body_json(refused).await["status"], "refusee");

    assert_eq!(
        active_guardianship_count(&db, requester_account, invitee_account).await,
        0,
        "un refus n'ouvre aucun accès"
    );
    let dependents = get_json(&requester_token, "/v1/account/dependents").await;
    assert!(!dependents
        .as_array()
        .unwrap()
        .iter()
        .any(|d| d["dependent_account_id"] == invitee_account.to_string()));

    // Le demandeur voit le refus dans sa liste ; rien à révoquer.
    let sent = get_json(&requester_token, "/v1/account/access-requests").await;
    let item = sent
        .as_array()
        .unwrap()
        .iter()
        .find(|it| it["id"] == request_id)
        .unwrap();
    assert_eq!(item["status"], "refusee");
    let revoke = post_action(&requester_token, &request_id, "revoke").await;
    assert_eq!(revoke.status(), StatusCode::NOT_FOUND);
}

/// Cas le plus courant (maquette, « trois points non tranchés » n°1) :
/// l'invité n'a pas encore de compte à l'envoi ; une fois inscrit avec le
/// même e-mail, il retrouve la demande reçue et peut la décider.
#[tokio::test]
async fn access_request_is_visible_to_invitee_registered_after_sending() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (requester_user, requester_account) = create_patient_account(&db, "ar-req-late").await;
    let requester_token = make_patient_jwt(requester_user, requester_account);
    let invitee_email = unique_email("tardif");

    let created = send_request(
        &requester_token,
        json!({
            "first_name": "Sam",
            "last_name": "Tardif",
            "relationship": "conjoint",
            "channel": "email",
            "scope": ["rendez_vous"],
            "email": invitee_email,
        }),
    )
    .await;
    assert_eq!(created.status(), StatusCode::CREATED);
    let request_id = body_json(created).await["id"].as_str().unwrap().to_string();

    // Inscription APRÈS l'envoi.
    let (invitee_user, invitee_account) =
        create_patient_account_with_email(&db, &invitee_email, "Sam", "Tardif").await;
    let invitee_token = make_patient_jwt(invitee_user, invitee_account);

    let received = get_json(&invitee_token, "/v1/account/access-requests").await;
    let item = received
        .as_array()
        .unwrap()
        .iter()
        .find(|it| it["id"] == request_id)
        .expect("rapprochée par e-mail, la demande doit apparaître côté invité");
    assert_eq!(item["direction"], "received");

    let accepted = post_action(&invitee_token, &request_id, "accept").await;
    assert_eq!(accepted.status(), StatusCode::OK);
    assert_eq!(
        active_guardianship_count(&db, requester_account, invitee_account).await,
        1
    );

    // Révocation côté invité : le lien tombe, le demandeur est prévenu.
    let revoked = post_action(&invitee_token, &request_id, "revoke").await;
    assert_eq!(revoked.status(), StatusCode::NO_CONTENT);
    assert_eq!(
        active_guardianship_count(&db, requester_account, invitee_account).await,
        0
    );
    assert_eq!(
        notification_count(&db, requester_user, "access_request_revoked").await,
        1
    );
}

fn unique_email(label: &str) -> String {
    format!("{label}+{}@nubia.test", Uuid::new_v4())
}
