//! Tests d'intégration : visibilité/gestion par le tuteur d'un RDV pris pour
//! un dépendant (#4274/QA-20260722-2 — migration 0196).
//!
//! Un RDV `on_behalf_of` un dépendant est rattaché au `patient_account_id` du
//! DÉPENDANT (create_appointment), jamais du tuteur. Avant #4274, le tuteur
//! ne pouvait ni le voir (GET détail/liste) ni le gérer (checkin/cancel) —
//! RLS scopée uniquement sur son propre compte.

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

const JWT_SECRET: &str = "test-jwt-secret-dependent-appt-guardian";

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

/// Toutes les IDs générées par [`insert_dependent_appointment_fixture`], pour
/// un nettoyage complet en fin de test (cabinet, RDV, comptes, tutelle).
struct DependentAppointmentFixture {
    cabinet_id: Uuid,
    prac_id: Uuid,
    prac_user_id: Uuid,
    patient_id: Uuid,
    appt_id: Uuid,
    guardian_user_id: Uuid,
    guardian_account_id: Uuid,
    dependent_user_id: Uuid,
}

/// Fixture complète : cabinet + praticien + tuteur (Marc) + dépendant (Jade),
/// guardianship active, 1 RDV rattaché au dépendant.
async fn insert_dependent_appointment_fixture(
    db: &PgPool,
    status: &str,
    starts_at_offset_minutes: i64,
) -> DependentAppointmentFixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES \
         ($1, $2, 'hash', 'pro'), ($3, $4, 'hash', 'patient'), ($5, $6, 'hash', 'patient')",
    )
    .bind(prac_user_id)
    .bind(format!("dep-appt-prac+{}@nubia.test", prac_user_id))
    .bind(guardian_user_id)
    .bind(format!("dep-appt-guardian+{}@nubia.test", guardian_user_id))
    .bind(dependent_user_id)
    .bind(format!(
        "dep-appt-dependent+{}@nubia.test",
        dependent_user_id
    ))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) VALUES \
         ($1, $2, 'Marc', 'Tuteur'), ($3, $4, 'Jade', 'Dependante')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO account_guardianship (guardian_account_id, dependent_account_id, relationship, active) \
         VALUES ($1, $2, 'enfant', true)",
    )
    .bind(guardian_account_id)
    .bind(dependent_account_id)
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
        .bind(format!("Cabinet Dependent Appt Test {}", cabinet_id))
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
        "INSERT INTO patient (id, cabinet_id, patient_account_id, first_name, last_name) \
         VALUES ($1, $2, $3, 'Jade', 'Dependante')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(dependent_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, \
                 now() + ($5 || ' minutes')::interval, \
                 now() + ($5 || ' minutes')::interval + interval '30 minutes', \
                 $6, 'contrôle')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .bind(starts_at_offset_minutes.to_string())
    .bind(status)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    DependentAppointmentFixture {
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        guardian_user_id,
        guardian_account_id,
        dependent_user_id,
    }
}

/// Nettoyage complet : RDV/cabinet puis tutelle puis comptes (app_user en
/// dernier — cascade sur patient_account, migration 0015).
async fn cleanup_fixture(db: &PgPool, f: &DependentAppointmentFixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM checkin_event WHERE appointment_id = $1")
        .bind(f.appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM audit_log WHERE entity_id = $1")
        .bind(f.appt_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE id = $1")
        .bind(f.appt_id)
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

    sqlx::query("DELETE FROM account_guardianship WHERE guardian_account_id = $1")
        .bind(f.guardian_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1 OR id = $2 OR id = $3")
        .bind(f.prac_user_id)
        .bind(f.guardian_user_id)
        .bind(f.dependent_user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : le tuteur voit le RDV du dépendant en détail ET en liste ──────

#[tokio::test]
async fn guardian_sees_dependent_appointment_in_get_and_list() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let f = insert_dependent_appointment_fixture(&db, "confirmed", 60 * 24 * 3).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let jwt = make_patient_jwt(f.guardian_user_id, f.guardian_account_id);

    // GET détail — 200, avant #4274 c'était 404 (RDV rattaché au dépendant,
    // invisible pour le tuteur en session).
    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}", f.appt_id))
                .header("Authorization", format!("Bearer {}", jwt))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        response.status(),
        StatusCode::OK,
        "le tuteur doit voir le détail du RDV du dépendant"
    );
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["id"], f.appt_id.to_string());

    // GET liste — le RDV du dépendant doit y figurer.
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/appointments")
                .header("Authorization", format!("Bearer {}", jwt))
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
    let items = v["data"].as_array().expect("data doit être un tableau");
    assert!(
        items.iter().any(|it| it["id"] == f.appt_id.to_string()),
        "le RDV du dépendant doit figurer dans la liste du tuteur"
    );

    cleanup_fixture(&db, &f).await;
}

// ── Test 2 : le tuteur peut checkin PUIS annuler le RDV du dépendant ───────

#[tokio::test]
async fn guardian_can_checkin_and_cancel_dependent_appointment() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    // starts_at dans 10 min : à l'intérieur de la fenêtre de checkin (±60 min).
    let f = insert_dependent_appointment_fixture(&db, "confirmed", 10).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let jwt = make_patient_jwt(f.guardian_user_id, f.guardian_account_id);

    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/appointments/{}/checkin", f.appt_id))
                .header("Authorization", format!("Bearer {}", jwt))
                .header("content-type", "application/json")
                .body(Body::from("{}"))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        response.status(),
        StatusCode::OK,
        "le tuteur doit pouvoir checkin le RDV du dépendant"
    );

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/appointments/{}/cancel", f.appt_id))
                .header("Authorization", format!("Bearer {}", jwt))
                .header("content-type", "application/json")
                .body(Body::from("{}"))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        response.status(),
        StatusCode::OK,
        "le tuteur doit pouvoir annuler le RDV du dépendant (checked_in → cancelled autorisé)"
    );

    cleanup_fixture(&db, &f).await;
}

// ── Test 2b : le tuteur accède queue/callback-request/preparation/directions
// du RDV du dépendant (#4363 — 4 handlers oubliés par le fix #4274) ────────

#[tokio::test]
async fn guardian_accesses_queue_callback_preparation_directions_for_dependent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let f = insert_dependent_appointment_fixture(&db, "requested", 60 * 24 * 3).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let jwt = make_patient_jwt(f.guardian_user_id, f.guardian_account_id);

    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}/queue", f.appt_id))
                .header("Authorization", format!("Bearer {}", jwt))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        response.status(),
        StatusCode::OK,
        "queue : le tuteur doit voir la file du RDV du dépendant (#4363)"
    );

    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/appointments/{}/callback-request", f.appt_id))
                .header("Authorization", format!("Bearer {}", jwt))
                .header("content-type", "application/json")
                .body(Body::from("{}"))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        response.status(),
        StatusCode::OK,
        "callback-request : le tuteur doit pouvoir demander un rappel (#4363)"
    );

    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}/preparation", f.appt_id))
                .header("Authorization", format!("Bearer {}", jwt))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        response.status(),
        StatusCode::OK,
        "preparation : le tuteur doit voir la préparation du RDV du dépendant (#4363)"
    );

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}/directions", f.appt_id))
                .header("Authorization", format!("Bearer {}", jwt))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        response.status(),
        StatusCode::OK,
        "directions : le tuteur doit voir l'itinéraire du RDV du dépendant (#4363)"
    );

    cleanup_fixture(&db, &f).await;
}

// ── Test 3 : régression — un compte SANS lien de tutelle ne voit pas le RDV ─

#[tokio::test]
async fn unrelated_account_still_gets_404_on_dependent_appointment() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let f = insert_dependent_appointment_fixture(&db, "confirmed", 60 * 24 * 3).await;

    // Tiers sans aucun lien de tutelle avec le dépendant.
    let stranger_user_id = Uuid::new_v4();
    let stranger_account_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(stranger_user_id)
    .bind(format!("dep-appt-stranger+{}@nubia.test", stranger_user_id))
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Karim', 'Tiers')",
    )
    .bind(stranger_account_id)
    .bind(stranger_user_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let jwt = make_patient_jwt(stranger_user_id, stranger_account_id);

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/appointments/{}", f.appt_id))
                .header("Authorization", format!("Bearer {}", jwt))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "un tiers sans lien de tutelle ne doit toujours pas voir le RDV du dépendant"
    );

    cleanup_fixture(&db, &f).await;
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(stranger_user_id)
        .execute(&db)
        .await
        .ok();
}
