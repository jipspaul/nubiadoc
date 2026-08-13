//! Tests d'intégration : POST /v1/cabinet/waiting-room/call-next

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

const JWT_SECRET: &str = "test-secret-call-next";

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

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &json!({ "sub": sub, "kind": "pro", "cabinet_id": cabinet_id, "role": "practitioner", "exp": exp }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_patient_token(sub: Uuid, account_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &json!({ "sub": sub, "kind": "patient", "account_id": account_id, "exp": exp }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère cabinet + praticien + patient + appointment `checked_in`.
/// Retourne `(cabinet_id, prac_user_id, patient_id, appt_id)`.
async fn insert_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("callnext-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet CallNext', 'dentaire')",
    )
    .bind(cabinet_id)
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
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Dupont')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif, checkin_at) \
         VALUES ($1, $2, $3, $4, now() - interval '30 minutes', now() + interval '30 minutes', \
                 'checked_in', 'détartrage', now() - interval '10 minutes')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    (cabinet_id, prac_user_id, patient_id, appt_id)
}

async fn cleanup_fixture(
    db: &PgPool,
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    patient_id: Uuid,
    appt_id: Uuid,
) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

// ── Test 1 : praticien, file non vide → 200 + called:true ────────────────────

#[tokio::test]
async fn call_next_practitioner_happy_path() {
    if !db_available() {
        return;
    }

    let owner_db = owner_pool().await;
    let app_db = app_pool().await;

    let (cabinet_id, prac_user_id, patient_id, appt_id) = insert_fixture(&owner_db).await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let token = make_practitioner_token(prac_user_id, cabinet_id);
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/waiting-room/call-next")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["called"], true);
    assert_eq!(body["appointment_id"], appt_id.to_string());

    cleanup_fixture(&owner_db, cabinet_id, prac_user_id, patient_id, appt_id).await;
}

// ── Test 2 : file vide → 200 + called:false ───────────────────────────────────

#[tokio::test]
async fn call_next_empty_queue_returns_called_false() {
    if !db_available() {
        return;
    }

    let owner_db = owner_pool().await;
    let app_db = app_pool().await;

    // Cabinet sans aucun RDV checked_in.
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    {
        let mut tx = owner_db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(prac_user_id)
        .bind(format!("callnext-empty+{}@nubia.test", prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet Empty', 'dentaire')",
        )
        .bind(cabinet_id)
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
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let token = make_practitioner_token(prac_user_id, cabinet_id);
    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/waiting-room/call-next")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["called"], false);
    assert!(body.get("appointment_id").is_none() || body["appointment_id"].is_null());

    // Cleanup.
    let mut tx = owner_db.begin().await.unwrap();
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}

// ── Test 3 : token patient → 403 ─────────────────────────────────────────────

#[tokio::test]
async fn call_next_patient_token_returns_403() {
    if !db_available() {
        return;
    }

    let app_db = app_pool().await;

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let server = app(state);

    let patient_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let token = make_patient_token(patient_user_id, account_id);

    let response = server
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/waiting-room/call-next")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 4 : call-next appelle le patient en tête de la file VISIBLE (#4869) ──

/// Régression #4869 : `call-next` appelait un RDV `checked_in` de la veille
/// (fenêtre glissante ±24h) invisible dans `GET /waiting-room` (scopé
/// `date_trunc('day', now())`), sautant le patient réellement en tête. Les
/// deux endpoints doivent partager la même fenêtre et le même ordre FIFO.
#[tokio::test]
async fn call_next_calls_head_of_visible_waiting_room() {
    if !db_available() {
        return;
    }

    let owner_db = owner_pool().await;
    let app_db = app_pool().await;

    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let stale_patient_id = Uuid::new_v4();
    let today_patient_id = Uuid::new_v4();
    let stale_appt_id = Uuid::new_v4();
    let today_appt_id = Uuid::new_v4();

    {
        let mut tx = owner_db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(prac_user_id)
        .bind(format!("callnext-window+{}@nubia.test", prac_user_id))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet Window', 'dentaire')",
        )
        .bind(cabinet_id)
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

        // Patient resté checked_in depuis la veille (checkin_at antérieur ⇒ tête de FIFO).
        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
             VALUES ($1, $2, 'Marc', 'Dubois')",
        )
        .bind(stale_patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO appointment \
             (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif, checkin_at) \
             VALUES ($1, $2, $3, $4, now() - interval '18 hours', now() - interval '17 hours 30 minutes', \
                     'checked_in', 'détartrage', now() - interval '17 hours 45 minutes')",
        )
        .bind(stale_appt_id)
        .bind(cabinet_id)
        .bind(stale_patient_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        // Patient du jour, arrivé après (checkin_at récent).
        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
             VALUES ($1, $2, 'Jade', 'Martin')",
        )
        .bind(today_patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO appointment \
             (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif, checkin_at) \
             VALUES ($1, $2, $3, $4, now() - interval '5 minutes', now() + interval '25 minutes', \
                     'checked_in', 'détartrage', now())",
        )
        .bind(today_appt_id)
        .bind(cabinet_id)
        .bind(today_patient_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_practitioner_token(prac_user_id, cabinet_id);

    // La salle d'attente doit voir les DEUX RDV (fenêtre glissante alignée sur call-next),
    // le RDV de la veille en tête (checkin_at le plus ancien).
    let wr_response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/waiting-room")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(wr_response.status(), StatusCode::OK);
    let wr_bytes = axum::body::to_bytes(wr_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let wr_body: serde_json::Value = serde_json::from_slice(&wr_bytes).unwrap();
    let wr_data = wr_body["data"].as_array().unwrap();
    assert_eq!(
        wr_data.len(),
        2,
        "waiting-room doit voir les 2 RDV checked_in (jour + veille dans la fenêtre ±24h)"
    );
    assert_eq!(
        wr_data[0]["appointment_id"], stale_appt_id.to_string(),
        "le RDV de la veille, checked-in en premier, doit être en tête de la salle d'attente"
    );

    // call-next doit appeler exactement ce même RDV en tête, pas sauter au RDV du jour.
    let call_response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/waiting-room/call-next")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(call_response.status(), StatusCode::OK);
    let call_bytes = axum::body::to_bytes(call_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let call_body: serde_json::Value = serde_json::from_slice(&call_bytes).unwrap();
    assert_eq!(call_body["called"], true);
    assert_eq!(
        call_body["appointment_id"], stale_appt_id.to_string(),
        "call-next doit appeler le patient en tête de la file VISIBLE, pas sauter au RDV du jour"
    );

    // Cleanup.
    let mut tx = owner_db.begin().await.unwrap();
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
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
}
