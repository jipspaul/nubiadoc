//! Tests d'intégration : POST /v1/cabinet/conversations/:id/convert-to-appointment (#4159)

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

const JWT_SECRET: &str = "test-jwt-secret-cabinet-conversation-convert";

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

struct Fixtures {
    cabinet_id: Uuid,
    secretary_user_id: Uuid,
    prac_id: Uuid,
    provider_id: Uuid,
    patient_id: Uuid,
    conversation_id: Uuid,
    slot_id: Uuid,
}

async fn setup(db: &PgPool, prefix: &str) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let secretary_user_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let conversation_id = Uuid::new_v4();
    let message_id = Uuid::new_v4();
    let slot_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(secretary_user_id)
    .bind(format!(
        "cc-convert-{}-sec+{}@nubia.test",
        prefix, secretary_user_id
    ))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!(
        "cc-convert-{}-prac+{}@nubia.test",
        prefix, prac_user_id
    ))
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
        .bind(format!("Cabinet CC Convert {} {}", prefix, cabinet_id))
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
         VALUES ($1, $2, $3, $4, 'Dr. Test', true, true)",
    )
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(prac_user_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) VALUES ($1, $2, 'Claire', 'Convert')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO conversation (id, cabinet_id, patient_id, scope, status) \
         VALUES ($1, $2, $3, 'patient_cabinet', 'open')",
    )
    .bind(conversation_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO message \
         (id, cabinet_id, conversation_id, sender_kind, sender_id, body_ciphertext, body_key_ref, triage_flag) \
         VALUES ($1, $2, $3, 'patient', $4, $5, 'poc-stub', 'normal')",
    )
    .bind(message_id)
    .bind(cabinet_id)
    .bind(conversation_id)
    .bind(patient_id)
    .bind("Douleur dent de sagesse, besoin de consulter vite".as_bytes())
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO availability_slot \
         (id, provider_id, cabinet_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, $5, $6, 'open')",
    )
    .bind(slot_id)
    .bind(provider_id)
    .bind(cabinet_id)
    .bind(prac_id)
    .bind(
        "2026-08-10T09:00:00Z"
            .parse::<chrono::DateTime<chrono::Utc>>()
            .unwrap(),
    )
    .bind(
        "2026-08-10T09:30:00Z"
            .parse::<chrono::DateTime<chrono::Utc>>()
            .unwrap(),
    )
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        secretary_user_id,
        prac_id,
        provider_id,
        patient_id,
        conversation_id,
        slot_id,
    }
}

async fn teardown(db: &PgPool, f: &Fixtures) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM audit_log WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM appointment WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM availability_slot WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM message WHERE conversation_id = $1")
        .bind(f.conversation_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM conversation WHERE id = $1")
        .bind(f.conversation_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(f.patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM provider WHERE id = $1")
        .bind(f.provider_id)
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.secretary_user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test : sans JWT → 401 ────────────────────────────────────────────────────

#[tokio::test]
async fn convert_conversation_no_jwt_returns_401() {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    let state = AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/conversations/{}/convert-to-appointment",
                    Uuid::new_v4()
                ))
                .header("content-type", "application/json")
                .body(Body::from(json!({"slot_id": Uuid::new_v4()}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test : rôle secrétaire, conversation + slot valides → 201, appointment
//    'requested', audit_log lié au conversation_id ──────────────────────────

#[tokio::test]
async fn convert_conversation_creates_requested_appointment_and_audit_log() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "ok").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/conversations/{}/convert-to-appointment",
                    f.conversation_id
                ))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(f.secretary_user_id, f.cabinet_id, "secretary")
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(json!({"slot_id": f.slot_id}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["status"], "requested");
    let appointment_id: Uuid = v["appointment_id"].as_str().unwrap().parse().unwrap();

    // L'appointment existe bien en base avec status='requested', motif déduit
    // du dernier message, patient_id déduit de la conversation.
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let appt_row = sqlx::query(
        "SELECT status, patient_id, practitioner_id, motif FROM appointment WHERE id = $1",
    )
    .bind(appointment_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let status: String = appt_row.try_get("status").unwrap();
    let patient_id: Uuid = appt_row.try_get("patient_id").unwrap();
    let practitioner_id: Uuid = appt_row.try_get("practitioner_id").unwrap();
    let motif: Option<String> = appt_row.try_get("motif").unwrap();

    assert_eq!(status, "requested");
    assert_eq!(patient_id, f.patient_id);
    assert_eq!(practitioner_id, f.prac_id);
    assert_eq!(
        motif.as_deref(),
        Some("Douleur dent de sagesse, besoin de consulter vite")
    );

    // audit_log — une entrée liée au conversation_id (owner pool : pas de
    // restriction SELECT/DELETE app-layer sur ce test de vérification).
    let audit_row = sqlx::query(
        "SELECT action, entity, entity_id FROM audit_log \
         WHERE cabinet_id = $1 AND entity_id = $2 AND action = 'convert_to_appointment'",
    )
    .bind(f.cabinet_id)
    .bind(f.conversation_id)
    .fetch_optional(&db)
    .await
    .unwrap();
    let audit_row = audit_row.expect("une entrée audit_log liée au conversation_id est attendue");
    let entity: String = audit_row.try_get("entity").unwrap();
    assert_eq!(entity, "conversation");

    // Le créneau consommé n'est plus 'open'.
    let mut tx2 = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx2)
        .await
        .unwrap();
    let slot_row = sqlx::query("SELECT status FROM availability_slot WHERE id = $1")
        .bind(f.slot_id)
        .fetch_one(&mut *tx2)
        .await
        .unwrap();
    tx2.commit().await.unwrap();
    let slot_status: String = slot_row.try_get("status").unwrap();
    assert_eq!(slot_status, "booked");

    teardown(&db, &f).await;
}

// ── Test : conversation inexistante/hors tenant → 404 ────────────────────────

#[tokio::test]
async fn convert_conversation_not_found_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "404").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/conversations/{}/convert-to-appointment",
                    Uuid::new_v4()
                ))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(f.secretary_user_id, f.cabinet_id, "secretary")
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(json!({"slot_id": f.slot_id}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    teardown(&db, &f).await;
}

// ── Test : slot existant mais non 'open' → 404 (#4399, pas 409 slot_taken :
// réservé au vrai conflit d'insert 23P01, pas à un lookup à 0 ligne) ────────

#[tokio::test]
async fn convert_conversation_slot_not_open_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "taken").await;

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(f.cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query("UPDATE availability_slot SET status = 'booked' WHERE id = $1")
            .bind(f.slot_id)
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
                .uri(format!(
                    "/v1/cabinet/conversations/{}/convert-to-appointment",
                    f.conversation_id
                ))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(f.secretary_user_id, f.cabinet_id, "secretary")
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(json!({"slot_id": f.slot_id}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    teardown(&db, &f).await;
}

// ── Test (#4399) : slot_id totalement inexistant → 404 (pas 409 slot_taken,
// repro exacte de l'issue : un créneau jamais créé ne peut pas être "pris") ──

#[tokio::test]
async fn convert_conversation_unknown_slot_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "unknownslot").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!(
                    "/v1/cabinet/conversations/{}/convert-to-appointment",
                    f.conversation_id
                ))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(f.secretary_user_id, f.cabinet_id, "secretary")
                    ),
                )
                .header("content-type", "application/json")
                .body(Body::from(json!({"slot_id": Uuid::new_v4()}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        response.status(),
        StatusCode::NOT_FOUND,
        "un slot_id inexistant doit renvoyer 404 not_found, pas 409 slot_taken"
    );

    teardown(&db, &f).await;
}
