//! Tests d'intégration : `POST /v1/cabinet/appointments/series` (#4088).

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-appointment-series";

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

struct Fixture {
    cabinet_id: Uuid,
    practitioner_id: Uuid,
    patient_id: Uuid,
}

async fn insert_fixture(db: &PgPool, tag: &str) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let practitioner_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query("INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')")
        .bind(cabinet_id)
        .bind(format!("Cabinet AppointmentSeries {tag} {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("appt-series-{tag}+{user_id}@nubia.test"))
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(practitioner_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES ($1, $2, 'Serge', 'Series')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        practitioner_id,
        patient_id,
    }
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
    sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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
}

/// Spec de l'issue : création atomique de 3 RDV liés par recurrence_id.
#[tokio::test]
async fn create_series_creates_three_linked_appointments() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "atomic").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointments/series")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "practitioner_id": f.practitioner_id,
                        "patient_id": f.patient_id,
                        "motif": "Parodontologie",
                        "occurrences": [
                            {"starts_at": "2026-09-01T09:00:00Z", "ends_at": "2026-09-01T09:30:00Z"},
                            {"starts_at": "2026-09-08T09:00:00Z", "ends_at": "2026-09-08T09:30:00Z"},
                            {"starts_at": "2026-09-15T09:00:00Z", "ends_at": "2026-09-15T09:30:00Z"}
                        ]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let appointments = v["appointments"].as_array().unwrap();
    assert_eq!(appointments.len(), 3, "3 RDV créés");
    let recurrence_id = v["recurrence_id"].as_str().unwrap();

    let db_count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM appointment WHERE recurrence_id = $1::uuid")
            .bind(recurrence_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(
        db_count, 3,
        "les 3 RDV partagent le même recurrence_id en base"
    );

    cleanup_fixture(&db, &f).await;
}

/// Spec de l'issue : rollback complet si le 2e créneau est occupé.
#[tokio::test]
async fn create_series_rolls_back_entirely_on_conflict() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "rollback").await;

    // Pré-occupe le créneau du 2e RDV de la série à venir.
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO appointment \
             (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
             VALUES ($1, $2, $3, '2026-10-08 09:00+00', '2026-10-08 09:30+00', 'confirmed')",
        )
        .bind(f.cabinet_id)
        .bind(f.patient_id)
        .bind(f.practitioner_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointments/series")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "practitioner_id": f.practitioner_id,
                        "patient_id": f.patient_id,
                        "motif": "Parodontologie",
                        "occurrences": [
                            {"starts_at": "2026-10-01T09:00:00Z", "ends_at": "2026-10-01T09:30:00Z"},
                            {"starts_at": "2026-10-08T09:00:00Z", "ends_at": "2026-10-08T09:30:00Z"},
                            {"starts_at": "2026-10-15T09:00:00Z", "ends_at": "2026-10-15T09:30:00Z"}
                        ]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CONFLICT);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "slot_taken");

    // Rollback complet : le 1er RDV (non conflictuel) n'a PAS été créé non plus.
    let db_count: i64 = {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        let count = sqlx::query_scalar(
            "SELECT count(*) FROM appointment WHERE starts_at = '2026-10-01T09:00:00Z'::timestamptz",
        )
        .fetch_one(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
        count
    };
    assert_eq!(
        db_count, 0,
        "rollback complet : même le 1er RDV (sans conflit) n'est pas créé"
    );

    cleanup_fixture(&db, &f).await;
}

/// Non-régression : occurrences vide → 422.
#[tokio::test]
async fn create_series_empty_occurrences_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "empty").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointments/series")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "practitioner_id": f.practitioner_id,
                        "patient_id": f.patient_id,
                        "occurrences": []
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);

    cleanup_fixture(&db, &f).await;
}

/// #4342 : une occurrence entièrement dans le passé → 422
/// `start_at_not_future` (parité avec `create_cabinet_slot`/`create_booking`)
/// et AUCUN RDV n'est créé, même les occurrences futures de la même série.
#[tokio::test]
async fn create_series_past_occurrence_returns_422_start_at_not_future() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "past").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointments/series")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "practitioner_id": f.practitioner_id,
                        "patient_id": f.patient_id,
                        "motif": "QA-series-past",
                        "occurrences": [
                            {"starts_at": "2020-01-06T09:00:00Z", "ends_at": "2020-01-06T09:30:00Z"},
                            {"starts_at": "2026-09-08T09:00:00Z", "ends_at": "2026-09-08T09:30:00Z"}
                        ]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "start_at_not_future");

    let db_count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM appointment WHERE cabinet_id = $1")
            .bind(f.cabinet_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(
        db_count, 0,
        "aucun RDV créé, même l'occurrence future de la série"
    );

    cleanup_fixture(&db, &f).await;
}

/// #4344 : une occurrence chevauchant une indisponibilité praticien
/// (`availability_slot.status='blocked'`) → 409 `slot_taken`, aucun RDV créé.
#[tokio::test]
async fn create_series_overlapping_blocked_slot_returns_409_slot_taken() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "blocked").await;

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO availability_slot \
             (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status) \
             VALUES ($1, NULL, $2, $3, '2027-09-09T14:00:00Z', '2027-09-09T15:00:00Z', 'blocked')",
        )
        .bind(Uuid::new_v4())
        .bind(f.cabinet_id)
        .bind(f.practitioner_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointments/series")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "practitioner_id": f.practitioner_id,
                        "patient_id": f.patient_id,
                        "motif": "QA-overlap-blocked",
                        "occurrences": [
                            {"starts_at": "2027-09-09T14:15:00Z", "ends_at": "2027-09-09T14:45:00Z"}
                        ]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CONFLICT);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["code"], "slot_taken");

    let db_count: i64 =
        sqlx::query_scalar("SELECT count(*) FROM appointment WHERE cabinet_id = $1")
            .bind(f.cabinet_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(db_count, 0, "aucun RDV créé sur l'indisponibilité");

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query("DELETE FROM availability_slot WHERE cabinet_id = $1")
            .bind(f.cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        tx.commit().await.unwrap();
    }

    cleanup_fixture(&db, &f).await;
}

/// #4408 : une occurrence chevauchant un `availability_slot` publié `open`
/// doit le consommer (`booked`), comme `create_cabinet_appointment` et
/// `create_appointment` — sinon le créneau reste visible dans
/// `/search/slots` (fantôme) alors qu'un RDV l'occupe déjà.
#[tokio::test]
async fn create_series_consumes_overlapping_open_slot() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "consume").await;
    let slot_id = Uuid::new_v4();

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO availability_slot \
             (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status, online_booking) \
             VALUES ($1, NULL, $2, $3, '2027-10-11T15:00:00Z', '2027-10-11T15:30:00Z', 'open', true)",
        )
        .bind(slot_id)
        .bind(f.cabinet_id)
        .bind(f.practitioner_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointments/series")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary")
                    ),
                )
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "practitioner_id": f.practitioner_id,
                        "patient_id": f.patient_id,
                        "motif": "QA-consume-open-slot",
                        "occurrences": [
                            {"starts_at": "2027-10-11T15:00:00Z", "ends_at": "2027-10-11T15:30:00Z"}
                        ]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let slot_status: String = {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        let row = sqlx::query("SELECT status FROM availability_slot WHERE id = $1")
            .bind(slot_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
        row.try_get("status").unwrap()
    };
    assert_eq!(
        slot_status, "booked",
        "le créneau chevauché par la série doit être consommé, pas rester 'open' (fantôme)"
    );

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query("DELETE FROM availability_slot WHERE cabinet_id = $1")
            .bind(f.cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        tx.commit().await.unwrap();
    }

    cleanup_fixture(&db, &f).await;
}

/// Régression #4577 (doublon de #4576, déjà corrigé par 43a63ed0) : le RDV
/// créé par une série doit porter `slot_id` (pas NULL) sur le créneau
/// consommé, afin que la reprogrammation (PATCH /v1/cabinet/appointments/:id)
/// libère bien le créneau d'origine — sinon il reste `booked` à vie, orphelin
/// de tout RDV.
#[tokio::test]
async fn create_series_appointment_slot_id_is_linked_and_released_on_reschedule() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = insert_fixture(&db, "reschedule").await;
    let origin_slot_id = Uuid::new_v4();
    let dest_slot_id = Uuid::new_v4();

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO availability_slot \
             (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status, online_booking) \
             VALUES ($1, NULL, $2, $3, '2027-11-23T05:13:00Z', '2027-11-23T05:38:00Z', 'open', true)",
        )
        .bind(origin_slot_id)
        .bind(f.cabinet_id)
        .bind(f.practitioner_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO availability_slot \
             (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status, online_booking) \
             VALUES ($1, NULL, $2, $3, '2027-11-23T07:33:00Z', '2027-11-23T07:58:00Z', 'open', true)",
        )
        .bind(dest_slot_id)
        .bind(f.cabinet_id)
        .bind(f.practitioner_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        tx.commit().await.unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let secretary_jwt = make_pro_jwt(Uuid::new_v4(), f.cabinet_id, "secretary");

    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/appointments/series")
                .header("Authorization", format!("Bearer {secretary_jwt}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({
                        "practitioner_id": f.practitioner_id,
                        "patient_id": f.patient_id,
                        "motif": "QA-4577-reschedule",
                        "occurrences": [
                            {"starts_at": "2027-11-23T05:13:00Z", "ends_at": "2027-11-23T05:38:00Z"}
                        ]
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let appointment_id: Uuid = json["appointments"][0]["id"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap();

    // Le RDV de série doit porter slot_id = origin_slot_id (pas NULL).
    let linked_slot_id: Option<Uuid> = {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        let row = sqlx::query("SELECT slot_id FROM appointment WHERE id = $1")
            .bind(appointment_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
        row.try_get("slot_id").unwrap()
    };
    assert_eq!(
        linked_slot_id,
        Some(origin_slot_id),
        "le RDV créé par une série doit être lié au créneau consommé (slot_id), \
         sinon les voies de libération (reschedule/no-show/cancel) ne le retrouvent jamais"
    );

    // Reprogrammation vers le créneau de destination.
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("PATCH")
                .uri(format!("/v1/cabinet/appointments/{appointment_id}"))
                .header("Authorization", format!("Bearer {secretary_jwt}"))
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"starts_at": "2027-11-23T07:33:00Z"}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // Le créneau d'origine doit être repassé 'open' (libéré).
    let origin_status: String = {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        let row = sqlx::query("SELECT status FROM availability_slot WHERE id = $1")
            .bind(origin_slot_id)
            .fetch_one(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
        row.try_get("status").unwrap()
    };
    assert_eq!(
        origin_status, "open",
        "le créneau d'origine d'un RDV de série doit être libéré (status='open') \
         après reprogrammation, pas rester 'booked' orphelin (#4577)"
    );

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query("DELETE FROM availability_slot WHERE cabinet_id = $1")
            .bind(f.cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        tx.commit().await.unwrap();
    }

    cleanup_fixture(&db, &f).await;
}
