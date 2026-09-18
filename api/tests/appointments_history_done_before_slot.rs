//! Tests d'intégration : GET /v1/appointments?filter=history|upcoming — #6875.
//!
//! Un patient arrivé en avance, reçu et clôturé AVANT l'heure de son créneau
//! (`status = 'done'`, `starts_at` encore futur) n'apparaissait dans AUCUN des
//! deux onglets de « Mes RDV » : `upcoming` ignore `done`, et `past` exigeait
//! `starts_at <= now()`. Les deux vues doivent partitionner l'ensemble des RDV :
//! un statut terminal suffit à ranger le RDV dans l'historique.

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

const JWT_SECRET: &str = "test-jwt-secret-appointments-history-done";

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

struct Fixture {
    user_id: Uuid,
    account_id: Uuid,
    prac_user_id: Uuid,
    cabinet_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
    /// RDV `done` dont le créneau est encore dans le futur (+20 min).
    done_early_id: Uuid,
    /// RDV `cancelled` dont le créneau est encore dans le futur (+3 jours).
    cancelled_future_id: Uuid,
    /// RDV `confirmed` à venir (témoin : reste dans `upcoming`).
    confirmed_future_id: Uuid,
}

async fn insert_fixture(db: &PgPool) -> Fixture {
    let f = Fixture {
        user_id: Uuid::new_v4(),
        account_id: Uuid::new_v4(),
        prac_user_id: Uuid::new_v4(),
        cabinet_id: Uuid::new_v4(),
        prac_id: Uuid::new_v4(),
        patient_id: Uuid::new_v4(),
        done_early_id: Uuid::new_v4(),
        cancelled_future_id: Uuid::new_v4(),
        confirmed_future_id: Uuid::new_v4(),
    };

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(f.user_id)
    .bind(format!("appts-hist-done+{}@nubia.test", f.user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Marc', 'Avance')",
    )
    .bind(f.account_id)
    .bind(f.user_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(f.prac_user_id)
    .bind(format!(
        "appts-hist-done-prac+{}@nubia.test",
        f.prac_user_id
    ))
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
        .bind(format!("Cabinet Hist Done {}", f.cabinet_id))
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
        "INSERT INTO patient \
         (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Marc', 'Avance', $3)",
    )
    .bind(f.patient_id)
    .bind(f.cabinet_id)
    .bind(f.account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Cas #6875 : reçu en avance, clôturé 20 min AVANT l'heure du créneau.
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, completed_at) \
         VALUES ($1, $2, $3, $4, \
                 now() + interval '20 minutes', now() + interval '50 minutes', 'done', now())",
    )
    .bind(f.done_early_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .bind(f.prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Statut terminal `cancelled` sur un créneau futur : même règle.
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, cancelled_at) \
         VALUES ($1, $2, $3, $4, \
                 now() + interval '3 days', now() + interval '3 days 30 minutes', 'cancelled', now())",
    )
    .bind(f.cancelled_future_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .bind(f.prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Témoin : RDV confirmé à venir, reste dans `upcoming` et hors `history`.
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, \
                 now() + interval '5 days', now() + interval '5 days 30 minutes', 'confirmed')",
    )
    .bind(f.confirmed_future_id)
    .bind(f.cabinet_id)
    .bind(f.patient_id)
    .bind(f.prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();
    f
}

async fn cleanup_fixture(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
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
    tx.commit().await.ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2")
        .bind(f.user_id)
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

async fn list_ids(f: &Fixture, filter: &str) -> Vec<String> {
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments?filter={filter}&limit=100"))
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(f.user_id, f.account_id)),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    v["data"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|a| a["id"].as_str().map(str::to_owned))
        .collect()
}

// ── Test 1 : RDV done avant l'heure de son créneau → présent dans history ───

#[tokio::test]
async fn appointments_history_includes_done_with_future_starts_at() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db).await;

    let history = list_ids(&f, "history").await;
    assert!(
        history.contains(&f.done_early_id.to_string()),
        "le RDV done clôturé avant son créneau doit être dans l'historique (#6875)"
    );
    assert!(
        history.contains(&f.cancelled_future_id.to_string()),
        "un RDV annulé (statut terminal) appartient à l'historique même si son créneau est futur"
    );
    assert!(
        !history.contains(&f.confirmed_future_id.to_string()),
        "un RDV confirmé à venir ne doit pas être dans l'historique"
    );

    cleanup_fixture(&db, &f).await;
}

// ── Test 2 : les deux onglets partitionnent — done n'est pas dans upcoming ──

#[tokio::test]
async fn appointments_upcoming_excludes_done_and_keeps_confirmed_future() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db).await;

    let upcoming = list_ids(&f, "upcoming").await;
    assert!(
        !upcoming.contains(&f.done_early_id.to_string()),
        "un RDV done ne doit pas être « à venir »"
    );
    assert!(
        !upcoming.contains(&f.cancelled_future_id.to_string()),
        "un RDV annulé ne doit pas être « à venir »"
    );
    assert!(
        upcoming.contains(&f.confirmed_future_id.to_string()),
        "le RDV confirmé à venir reste dans upcoming"
    );

    cleanup_fixture(&db, &f).await;
}
