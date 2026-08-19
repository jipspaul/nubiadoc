//! Tests d'intégration : DELETE /v1/account/dependents/{id}

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

const JWT_SECRET: &str = "test-jwt-secret-dependents-delete";

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

// ── Test 1 : happy path — 204 + proche absent de GET après révocation ─────────

#[tokio::test]
async fn dependent_delete_happy_path_returns_204_and_hides_dependent() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_user_id)
    .bind(format!("guardian-del+{}@nubia.test", guardian_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Tuteur')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_user_id)
    .bind(format!("dependent-del+{}@nubia.test", dependent_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'Proche')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(&db)
    .await
    .unwrap();

    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'enfant', true)",
        )
        .bind(guardian_account_id)
        .bind(dependent_account_id)
        .execute(&rls_db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(guardian_user_id, guardian_account_id);

    // DELETE → 204
    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/account/dependents/{}", dependent_account_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    // GET /v1/account/dependents → tableau vide (proche révoqué exclu)
    let list_response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/account/dependents")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(list_response.status(), StatusCode::OK);
    let body = axum::body::to_bytes(list_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(json.as_array().expect("tableau").is_empty());
}

// ── Test 2 : double DELETE → 404 ──────────────────────────────────────────────

#[tokio::test]
async fn dependent_delete_twice_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_user_id)
    .bind(format!("guardian-del2+{}@nubia.test", guardian_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'Tuteur2')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_user_id)
    .bind(format!("dependent-del2+{}@nubia.test", dependent_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'Proche2')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(&db)
    .await
    .unwrap();

    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'enfant', true)",
        )
        .bind(guardian_account_id)
        .bind(dependent_account_id)
        .execute(&rls_db)
        .await
        .unwrap();
    }

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let token = make_patient_jwt(guardian_user_id, guardian_account_id);
    let uri = format!("/v1/account/dependents/{}", dependent_account_id);

    // Premier DELETE → 204
    let r1 = app(state.clone())
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(&uri)
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r1.status(), StatusCode::NO_CONTENT);

    // Second DELETE → 404
    let r2 = app(state)
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(&uri)
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r2.status(), StatusCode::NOT_FOUND);
}

// ── Test 3 : RDV futur du dépendant annulé en cascade + créneau libéré (#5679) ─

#[tokio::test]
async fn dependent_delete_cancels_future_appointment_and_releases_slot() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let guardian_user_id = Uuid::new_v4();
    let guardian_account_id = Uuid::new_v4();
    let dependent_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let slot_id = Uuid::new_v4();
    let appointment_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(guardian_user_id)
    .bind(format!("guardian-del3+{}@nubia.test", guardian_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Marc', 'Tuteur3')",
    )
    .bind(guardian_account_id)
    .bind(guardian_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(dependent_user_id)
    .bind(format!("dependent-del3+{}@nubia.test", dependent_user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'QAGhost', 'Lyon3')",
    )
    .bind(dependent_account_id)
    .bind(dependent_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("del3-prac+{}@nubia.test", prac_user_id))
    .execute(&db)
    .await
    .unwrap();

    {
        let rls_db = app_pool().await;
        sqlx::query(
            "INSERT INTO account_guardianship \
             (guardian_account_id, dependent_account_id, relationship, active) \
             VALUES ($1, $2, 'enfant', true)",
        )
        .bind(guardian_account_id)
        .bind(dependent_account_id)
        .execute(&rls_db)
        .await
        .unwrap();
    }

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentaire')",
        )
        .bind(cabinet_id)
        .bind(format!("Cabinet Lyon {}", cabinet_id))
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
            "INSERT INTO provider (id, cabinet_id, practitioner_id, user_id, display_name, is_listed, rpps_verified) \
             VALUES ($1, $2, $3, $4, 'Dr. Hugo Marin', true, true)",
        )
        .bind(provider_id)
        .bind(cabinet_id)
        .bind(prac_id)
        .bind(prac_user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        sqlx::query(
            "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
             VALUES ($1, $2, 'QAGhost', 'Lyon3', $3)",
        )
        .bind(patient_id)
        .bind(cabinet_id)
        .bind(dependent_account_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        // Créneau tenu par le RDV du dépendant (booked).
        sqlx::query(
            "INSERT INTO availability_slot \
             (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status, online_booking) \
             VALUES ($1, $2, $3, $4, \
                     now() + interval '5 days', \
                     now() + interval '5 days 30 minutes', \
                     'booked', true)",
        )
        .bind(slot_id)
        .bind(provider_id)
        .bind(cabinet_id)
        .bind(prac_id)
        .execute(&mut *tx)
        .await
        .unwrap();

        // RDV futur `requested` pris par le tuteur pour le dépendant.
        sqlx::query(
            "INSERT INTO appointment \
             (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif, slot_id) \
             VALUES ($1, $2, $3, $4, \
                     now() + interval '5 days', \
                     now() + interval '5 days 30 minutes', \
                     'requested', 'QA ghost orphan', $5)",
        )
        .bind(appointment_id)
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(prac_id)
        .bind(slot_id)
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
    let token = make_patient_jwt(guardian_user_id, guardian_account_id);

    // DELETE du dépendant → 204
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/v1/account/dependents/{}", dependent_account_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    // Le RDV doit être `cancelled`, plus `requested` orphelin (#5679).
    let appt_row = sqlx::query("SELECT status, cancelled_at FROM appointment WHERE id = $1")
        .bind(appointment_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let status: String = appt_row.try_get("status").unwrap();
    let cancelled_at: Option<chrono::DateTime<chrono::Utc>> =
        appt_row.try_get("cancelled_at").unwrap();
    assert_eq!(status, "cancelled");
    assert!(cancelled_at.is_some());

    // Le créneau doit être libéré (redevient réservable pour d'autres patients).
    let slot_row = sqlx::query("SELECT status FROM availability_slot WHERE id = $1")
        .bind(slot_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let slot_status: String = slot_row.try_get("status").unwrap();
    assert_eq!(slot_status, "open");
}
