//! Tests d'intégration : `FcmJobDispatcher` (#6321).
//!
//! Vérifie l'échange OAuth2 (JWT RS256 signé → access token via un mock du
//! `token_uri` du compte de service) puis le POST FCM HTTP v1
//! `messages:send` vers un mock `fcm_base_url`, la purge d'un device sur
//! réponse `UNREGISTERED`, et le fallback silencieux sans
//! `FIREBASE_SERVICE_ACCOUNT`.
//!
//! `enqueue_push_notification` est fire-and-forget (envoi FCM dans un
//! `tokio::spawn` séparé) : un court délai après l'appel laisse le temps aux
//! requêtes HTTP mockées d'arriver, même pattern que
//! `tests/brevo_mailer.rs`.

use serde_json::{json, Value};
use sqlx::{PgPool, Row};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use uuid::Uuid;
use wiremock::matchers::{method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

use nubia_api::{FcmJobDispatcher, JobDispatcher, StubJobDispatcher};

// Clé RSA-2048 PKCS#8 jetable, générée uniquement pour ces tests (`openssl
// genrsa 2048`) — ne signe jamais rien en dehors de ce fichier.
const TEST_PRIVATE_KEY: &str = "-----BEGIN PRIVATE KEY-----
MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQDOEdJkq+GfyWSC
NLe2T0QwjK26DcOTtjjFrZQjJFYAE1yBbIS7G1YMz85oTSccRzMh51unMN/a6T2V
Iy0NRAswoHklYc1k4tIf7XCfYNdw+0DEjwtjqBk5hnam5oJ0pdqzBTKc4JbeBzLP
3EjQoG+F4I0dSWYM1HuS21lnbrRzF7ojs+rwbDvaPkvLv8NhpeicYNS9ARkkavYL
MT/Iu1JmfDEqq7o93HNfftWmFEQfgMuI62Y10H3AYB2m8ticutNfGd6Ywrb3/aiY
Rn9wjrSF1CV7SxVn7sqkmteDe1ENp/Zfnk2J2WYv4jzDthPs4pmoK7TBC+FNOWHS
+i0y5cRhAgMBAAECggEAHaFrZsVeRnsPZDePWPwR2odH7bJP9nvjsuzwGZN+eDlQ
el2vwjW+jE4PKGk7n/HO9OePAr3g2lniXID31+n6T+4rLUhgX8rLmwKpyIkEwX6n
Q/wrj5NauS5P/lSz2nEEvuwW6H7Uwq03TbMnlzQShSYSNG1a6qpc8HNw6hH9iXTU
VOm6g5HmuurhGRbgsTn0ndGI0hNhxObglzqUc4jEWRpZTcTlJnh+VDJi+3V8BPyN
1iJXve0FBjIHjymS4zTDU61JoCRV0O2K5cFdf/O8e+hgR/1eo2Izk3kQ+sYAfOfI
LToNd174g7CBx3xoHUPQS+uzGfvmTzJA6NQy7WJvtwKBgQDwSCmXmw7RQYIHUXsF
prpAthkVluYT9D1vSU6WhLz0fDHzmXZCOAnaRfFsNi6lN3sHLJDrjhPDCS3oV2xz
6h6xJe7ItHuYM86u8wXAbqY6QyVmvpCUNRjc0WJP9CbcWsYDqyeHngVxKyK6duel
DAAXTubnWo+8CCxN+G1c+H2lWwKBgQDbjLrRrM0n9ol+WxwQ15OnzAifVZYgtp54
QugCDhOWOHSG8JH1RpwmJCQt00IKXNyu3gMyne/Nk57hIZVcS7bPV1HQ8iyiZIWV
5aEm2t0tnvTGMq4Es/Jw4iGTUEcfr1SBYZZjplowJCpF0JkJDh5M1rHjJ8kV7o1r
yckdf/ud8wKBgFZbeSdVwTOP+a2rqS1UyOftCoLp4vMU+ud+T1JljovH/yPv6cLO
5Sufq68aohUbJYpkiAlA3PVh3S/+C6p1YGaGnZVg2HLRW90g1tZcbj3OWCjfIJND
qhXi4xSdSUI1FanH38MsFgSgXjDp/0MgVwAJiY9oyvPndBTpzlR1sqK1AoGAeNoH
gCF5sLTRzH8EfPTdr3Dtkh9/izRbGOHjajYra/ZZlmnYPkaG76vXSm5OnPuu8ob9
BaDQfr3yqARffjWjRJDRVY3pKd7hdbi4M3YoZ9Nm8660AZy4KJEhYEDBVdyiTLHW
IbZRUMynhFSl2MkvvqYzt1GQLAVrTVj+3sEzVScCgYBf5FORMkONHaMULZZiiszK
/XU6FojM45vNIYxy7pL4w3lkLZDxsrzirTkZUfjVQxysFTWBpyvvWK3PQw3G20rz
PwHS2UQ91fQ9+RUENJrjNDzkObW2utpqshF0vu27GjSXT/vbxKi7N5MqKcvkR13W
kwyxcnZCrdg3r227AEtKgw==
-----END PRIVATE KEY-----";

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

async fn wait_for_requests() {
    tokio::time::sleep(std::time::Duration::from_millis(400)).await;
}

fn service_account_json(token_uri: &str) -> String {
    json!({
        "project_id": "test-project",
        "client_email": "test@test-project.iam.gserviceaccount.com",
        "private_key": TEST_PRIVATE_KEY,
        "token_uri": token_uri,
    })
    .to_string()
}

/// Insère un patient + un device actif + une notification, retourne
/// `(app_user_id, device_id, notification_id)`. Cleanup via `ON DELETE
/// CASCADE` (device/notification référencent `app_user`).
async fn seed_patient_with_device_and_notification(
    db: &PgPool,
    kind: &str,
    data: Value,
) -> (Uuid, Uuid, Uuid) {
    let user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("fcm-dispatcher+{user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    let device_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO device (id, app_user_id, fcm_token, platform) VALUES ($1, $2, $3, 'android')",
    )
    .bind(device_id)
    .bind(user_id)
    .bind("tok-fcm-dispatcher-test")
    .execute(db)
    .await
    .unwrap();

    let notification_id: Uuid = sqlx::query(
        "INSERT INTO notification \
         (app_user_id, kind, title, body_ciphertext, body_key_ref, data) \
         VALUES ($1, $2, 'Vous avez un nouveau message', '\\x00'::bytea, 'stub', $3) \
         RETURNING id",
    )
    .bind(user_id)
    .bind(kind)
    .bind(data)
    .fetch_one(db)
    .await
    .unwrap()
    .try_get("id")
    .unwrap();

    (user_id, device_id, notification_id)
}

async fn cleanup(db: &PgPool, user_id: Uuid) {
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
}

#[tokio::test]
async fn enqueue_push_notification_sends_real_fcm_push() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let (user_id, _device_id, notification_id) = seed_patient_with_device_and_notification(
        &owner_db,
        "appointment_confirmed",
        json!({ "appointment_id": "11111111-1111-1111-1111-111111111111" }),
    )
    .await;

    let mock_server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/token"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "access_token": "test-access-token",
            "expires_in": 3599,
            "token_type": "Bearer",
        })))
        .expect(1)
        .mount(&mock_server)
        .await;

    Mock::given(method("POST"))
        .and(path("/v1/projects/test-project/messages:send"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_json(json!({ "name": "projects/test-project/messages/0" })),
        )
        .expect(1)
        .mount(&mock_server)
        .await;

    let dispatcher = FcmJobDispatcher::with_service_account_json(
        Arc::new(StubJobDispatcher),
        app_pool().await,
        &service_account_json(&format!("{}/token", mock_server.uri())),
        mock_server.uri(),
    );

    dispatcher.enqueue_push_notification(user_id, notification_id);
    wait_for_requests().await;

    let requests = mock_server.received_requests().await.unwrap();
    let send_request = requests
        .iter()
        .find(|r| r.url.path() == "/v1/projects/test-project/messages:send")
        .expect("un POST messages:send attendu");

    assert_eq!(
        send_request.headers.get("authorization").unwrap(),
        "Bearer test-access-token"
    );
    let body: Value = serde_json::from_slice(&send_request.body).unwrap();
    assert_eq!(body["message"]["token"], "tok-fcm-dispatcher-test");
    assert_eq!(
        body["message"]["notification"]["title"],
        "Vous avez un nouveau message"
    );
    assert_eq!(body["message"]["data"]["kind"], "appointment_confirmed");
    assert_eq!(
        body["message"]["data"]["notification_id"],
        notification_id.to_string()
    );
    assert_eq!(
        body["message"]["data"]["deeplink"],
        "/appointments/11111111-1111-1111-1111-111111111111"
    );
    // Zéro PII : le corps chiffré/le contenu métier n'apparaissent jamais.
    assert!(!body.to_string().contains("appointment_id"));

    cleanup(&owner_db, user_id).await;
}

#[tokio::test]
async fn unregistered_fcm_response_purges_the_dead_device() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let (user_id, device_id, notification_id) =
        seed_patient_with_device_and_notification(&owner_db, "message_received", json!({})).await;

    let mock_server = MockServer::start().await;

    Mock::given(method("POST"))
        .and(path("/token"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({
            "access_token": "test-access-token",
            "expires_in": 3599,
            "token_type": "Bearer",
        })))
        .mount(&mock_server)
        .await;

    Mock::given(method("POST"))
        .and(path("/v1/projects/test-project/messages:send"))
        .respond_with(ResponseTemplate::new(404).set_body_json(json!({
            "error": {
                "code": 404,
                "message": "Requested entity was not found.",
                "status": "NOT_FOUND",
                "details": [{
                    "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
                    "errorCode": "UNREGISTERED"
                }]
            }
        })))
        .mount(&mock_server)
        .await;

    let dispatcher = FcmJobDispatcher::with_service_account_json(
        Arc::new(StubJobDispatcher),
        app_pool().await,
        &service_account_json(&format!("{}/token", mock_server.uri())),
        mock_server.uri(),
    );

    dispatcher.enqueue_push_notification(user_id, notification_id);
    wait_for_requests().await;

    let deleted_at: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query("SELECT deleted_at FROM device WHERE id = $1")
            .bind(device_id)
            .fetch_one(&owner_db)
            .await
            .unwrap()
            .try_get("deleted_at")
            .unwrap();
    assert!(
        deleted_at.is_some(),
        "un token UNREGISTERED doit être purgé (deleted_at posé)"
    );

    cleanup(&owner_db, user_id).await;
}

/// Compte les appels reçus, pour vérifier que `FcmJobDispatcher` délègue
/// bien à `inner` avant/indépendamment de tout envoi FCM.
struct RecordingDispatcher(Arc<AtomicUsize>);

impl JobDispatcher for RecordingDispatcher {
    fn enqueue_verify_provider(&self, _verification_id: Uuid) {}
    fn enqueue_notify_callback(&self, _appointment_id: Uuid, _cabinet_id: Uuid) {}
    fn enqueue_push_notification(&self, _app_user_id: Uuid, _notification_id: Uuid) {
        self.0.fetch_add(1, Ordering::SeqCst);
    }
    fn enqueue_interop_notification(
        &self,
        _cabinet_id: Uuid,
        _resource_type: &str,
        _resource_id: Uuid,
    ) {
    }
}

/// Sans `FIREBASE_SERVICE_ACCOUNT` (dev local / LXC sans le secret) :
/// `FcmJobDispatcher::new` ne doit tenter aucun appel réseau et se contenter
/// de déléguer à `inner` — fallback stub inchangé (contrat de l'issue #6321).
#[tokio::test]
async fn without_service_account_env_falls_back_to_inner_only() {
    assert!(
        std::env::var("FIREBASE_SERVICE_ACCOUNT").is_err(),
        "ce test suppose FIREBASE_SERVICE_ACCOUNT absent de l'environnement CI"
    );

    let calls = Arc::new(AtomicUsize::new(0));
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let dispatcher = FcmJobDispatcher::new(Arc::new(RecordingDispatcher(calls.clone())), db);

    dispatcher.enqueue_push_notification(Uuid::new_v4(), Uuid::new_v4());
    wait_for_requests().await;

    assert_eq!(
        calls.load(Ordering::SeqCst),
        1,
        "inner doit toujours être appelé"
    );
}
