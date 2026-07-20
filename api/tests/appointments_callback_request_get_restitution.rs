//! Tests d'intégration : restitution de callback_requested_at par les lectures
//! patient (#3845) — dédié, `appointments_callback_request.rs` est déjà proche
//! du plafond de taille (634 lignes).
//!
//! Avant #3845 : POST /appointments/:id/callback-request renvoyait
//! status:"callback_requested" (statut fictif, absent du modèle RDV) mais
//! AUCUN GET (détail ni liste) ne restituait callback_requested_at — la
//! demande de rappel était invisible au rafraîchissement.

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

const JWT_SECRET: &str = "test-jwt-secret-callback-get-restitution";

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

/// Insère cabinet + praticien + patient + RDV `requested`.
/// Retourne (cabinet_id, prac_id, patient_id, appt_id).
async fn insert_fixture(
    db: &PgPool,
    prac_user_id: Uuid,
    patient_account_id: Uuid,
) -> (Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet Callback GET {}", cabinet_id))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Test', 'CallbackGet', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, \
                 now() + INTERVAL '2 days', now() + INTERVAL '2 days 30 min', 'requested', 'test')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (cabinet_id, prac_id, patient_id, appt_id)
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, patient_id: Uuid, prac_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE id = $1")
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

#[tokio::test]
async fn callback_request_status_is_real_and_visible_in_get() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("callback-get+{}@nubia.test", patient_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'CallbackGet', 'Test')",
    )
    .bind(patient_account_id)
    .bind(patient_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("callback-get-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    let (cabinet_id, prac_id, patient_id, appt_id) =
        insert_fixture(&db, prac_user_id, patient_account_id).await;

    let token = make_patient_jwt(patient_user_id, patient_account_id);

    // POST callback-request : status doit être le statut RÉEL du RDV
    // ('requested'), jamais le fictif "callback_requested".
    let post_resp = app(AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        Request::builder()
            .method("POST")
            .uri(format!("/v1/appointments/{}/callback-request", appt_id))
            .header("Authorization", format!("Bearer {}", token))
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();
    assert_eq!(post_resp.status(), StatusCode::OK);
    let post_body = axum::body::to_bytes(post_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let post_json: serde_json::Value = serde_json::from_slice(&post_body).unwrap();
    assert_eq!(
        post_json["status"], "requested",
        "le statut renvoyé doit être un vrai statut RDV, pas 'callback_requested'"
    );
    let posted_ts = post_json["callback_requested_at"]
        .as_str()
        .expect("callback_requested_at doit être présent")
        .to_string();

    // GET détail : callback_requested_at doit être restitué et cohérent.
    let get_resp = app(AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        Request::builder()
            .method("GET")
            .uri(format!("/v1/appointments/{}", appt_id))
            .header("Authorization", format!("Bearer {}", token))
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();
    assert_eq!(get_resp.status(), StatusCode::OK);
    let get_body = axum::body::to_bytes(get_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let get_json: serde_json::Value = serde_json::from_slice(&get_body).unwrap();
    assert_eq!(
        get_json["callback_requested_at"], posted_ts,
        "GET /appointments/:id doit restituer callback_requested_at"
    );
    assert_eq!(get_json["status"], "requested");

    // GET liste : idem, l'item doit porter callback_requested_at.
    let list_resp = app(AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    })
    .oneshot(
        Request::builder()
            .method("GET")
            .uri("/v1/appointments")
            .header("Authorization", format!("Bearer {}", token))
            .body(Body::empty())
            .unwrap(),
    )
    .await
    .unwrap();
    assert_eq!(list_resp.status(), StatusCode::OK);
    let list_body = axum::body::to_bytes(list_resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let list_json: serde_json::Value = serde_json::from_slice(&list_body).unwrap();
    let item = list_json["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["id"].as_str() == Some(&appt_id.to_string()))
        .expect("le RDV doit apparaître dans la liste");
    assert_eq!(
        item["callback_requested_at"], posted_ts,
        "GET /appointments (liste) doit aussi restituer callback_requested_at"
    );

    cleanup(&db, cabinet_id, patient_id, prac_id).await;
}
