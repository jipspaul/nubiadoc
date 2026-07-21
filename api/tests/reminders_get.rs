//! Tests d'intégration : GET /v1/reminders

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

const JWT_SECRET: &str = "test-jwt-secret-reminders";

fn make_patient_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_pro_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "cabinet_id": Uuid::new_v4(), "role": "admin",
                "account_id": Uuid::nil(), "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn lazy_state() -> AppState {
    let db = PgPool::connect_lazy(
        &std::env::var("APP_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
    )
    .unwrap();
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

// ── Test 1 : happy path → 200 + data est un tableau (rappels réels, pas mockés) ─
// Le rappel "prevention" codé en dur (identique pour tout patient) a été
// retiré (#3880) : un patient sans RDV ni devis réels reçoit désormais
// `data: []`, pas un item fictif.

#[tokio::test]
async fn reminders_list_returns_200_with_array() {
    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(Uuid::new_v4())),
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

    assert!(
        v["data"].is_array(),
        "la réponse doit contenir un champ data tableau"
    );
}

// ── Test 2 : structure des items → champs obligatoires présents ───────────────

#[tokio::test]
async fn reminders_items_have_required_fields() {
    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(Uuid::new_v4())),
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

    for item in v["data"].as_array().unwrap() {
        assert!(item["id"].is_string(), "id doit être une string");
        assert!(item["type"].is_string(), "type doit être une string");
        assert!(item["title"].is_string(), "title doit être une string");
        assert!(item["due_at"].is_string(), "due_at doit être une string");
        assert!(item["status"].is_string(), "status doit être une string");
    }
}

// ── Test 3 : sans JWT → 401 ───────────────────────────────────────────────────

#[tokio::test]
async fn reminders_no_jwt_returns_401() {
    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 4 : token pro → 403 ─────────────────────────────────────────────────

#[tokio::test]
async fn reminders_pro_token_returns_403() {
    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(Uuid::new_v4())),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

// ── Test 5 : token expiré → 401 ──────────────────────────────────────────────

#[tokio::test]
async fn reminders_expired_jwt_returns_401() {
    let exp_past: u64 = 1_000_000; // timestamp passé
    let expired_token = encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp_past}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header("Authorization", format!("Bearer {}", expired_token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 6 : le rappel "prevention" codé en dur a été retiré (#3880) ─────────
// Régression #3880 : le rappel prevention (id/titre/due_at constants,
// due_at fixe déjà passée) était renvoyé à l'identique pour tout patient,
// même sans aucune donnée clinique réelle.

#[tokio::test]
async fn reminders_no_hardcoded_prevention_stub() {
    let response = app(lazy_state())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_patient_jwt(Uuid::new_v4())),
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

    for item in v["data"].as_array().unwrap() {
        assert_ne!(
            item["id"].as_str(),
            Some("c3d4e5f6-a7b8-9012-cdef-234567890123"),
            "l'id constant du rappel prevention codé en dur ne doit plus apparaître"
        );
        assert_ne!(
            item["type"].as_str(),
            Some("prevention"),
            "le type prevention (stub) ne doit plus être émis"
        );
    }
}

// ── Test 7 : devis "sent" → rappel type quote + metadata.quote_id (#3795) ────
// Régression #3795 : le rappel devis était type="document" avec
// metadata.document_id=<quote_id> — GET /documents/:id sur cet id renvoie
// 404 (ce n'est pas un document). Doit être type="quote" + quote_id.

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

async fn owner_pool() -> PgPool {
    let url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_owner@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

#[tokio::test]
async fn reminders_sent_quote_has_quote_type_and_quote_id() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let quote_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("reminders-quote+{patient_user_id}@nubia.test"))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Marc', 'Reminders')",
    )
    .bind(account_id)
    .bind(patient_user_id)
    .execute(&db)
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
        .bind(format!("Cabinet Reminders Test {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Marc', 'Reminders', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO quote (id, cabinet_id, patient_id, status, total_amount) \
         VALUES ($1, $2, $3, 'sent', 50)",
    )
    .bind(quote_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    let state = AppState {
        db: PgPool::connect(
            &std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
        )
        .await
        .unwrap(),
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let token = encode(
        &Header::default(),
        &json!({
            "sub": patient_user_id, "kind": "patient", "account_id": account_id,
            "exp": SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() + 3600
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header("Authorization", format!("Bearer {token}"))
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

    let items = v["data"].as_array().unwrap();
    let quote_reminder = items
        .iter()
        .find(|i| i["id"].as_str() == Some(&quote_id.to_string()))
        .expect("le rappel du devis sent doit être présent");

    assert_eq!(
        quote_reminder["type"].as_str(),
        Some("quote"),
        "le type doit être quote, pas document (id non résoluble via /documents/:id)"
    );
    assert_eq!(
        quote_reminder["metadata"]["quote_id"].as_str(),
        Some(quote_id.to_string().as_str())
    );
    assert!(
        quote_reminder["metadata"].get("document_id").is_none(),
        "document_id ne doit plus être émis (id n'est pas un document)"
    );

    // Cleanup
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM quote WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE id = $1")
        .bind(patient_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(patient_user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 8 : rappels réels de `reminder` (#4077) — triés + cross-tenant ─────
// Insère 2 lignes `reminder` (passée + future) pour un patient : GET
// /v1/reminders doit renvoyer les deux, triées par due_at ASC. Un autre
// patient (compte différent) ne doit voir aucune des deux (RLS
// reminder_patient_read, migration 0171).

#[tokio::test]
async fn reminders_real_reminder_rows_returned_sorted_and_cross_tenant_isolated() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;

    let cabinet_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let appointment_id = Uuid::new_v4();
    let reminder_past_id = Uuid::new_v4();
    let reminder_future_id = Uuid::new_v4();

    // Autre patient (compte distinct), sans aucun rappel — vérifie le
    // cloisonnement cross-tenant.
    let other_patient_user_id = Uuid::new_v4();
    let other_account_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("reminders-real+{patient_user_id}@nubia.test"))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(other_patient_user_id)
    .bind(format!(
        "reminders-real-other+{other_patient_user_id}@nubia.test"
    ))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("reminders-real-prac+{prac_user_id}@nubia.test"))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Alice', 'RealReminders')",
    )
    .bind(account_id)
    .bind(patient_user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Bob', 'OtherPatient')",
    )
    .bind(other_account_id)
    .bind(other_patient_user_id)
    .execute(&db)
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
        .bind(format!("Cabinet Reminders Real {cabinet_id}"))
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
         VALUES ($1, $2, 'Alice', 'RealReminders', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, now() + interval '3 days', \
                 now() + interval '3 days' + interval '30 minutes', 'confirmed')",
    )
    .bind(appointment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Rappel PASSÉ (scheduled_at déjà écoulé) — doit apparaître en premier
    // (due_at ASC).
    sqlx::query(
        "INSERT INTO reminder \
         (id, cabinet_id, appointment_id, patient_id, scheduled_at, kind, channel, status) \
         VALUES ($1, $2, $3, $4, now() - interval '1 day', 'rdv_confirmation', 'push', 'pending')",
    )
    .bind(reminder_past_id)
    .bind(cabinet_id)
    .bind(appointment_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Rappel FUTUR — doit apparaître en second.
    sqlx::query(
        "INSERT INTO reminder \
         (id, cabinet_id, appointment_id, patient_id, scheduled_at, kind, channel, status) \
         VALUES ($1, $2, $3, $4, now() + interval '2 days', 'rdv_rappel', 'push', 'pending')",
    )
    .bind(reminder_future_id)
    .bind(cabinet_id)
    .bind(appointment_id)
    .bind(patient_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    let make_token = |user_id: Uuid, account: Uuid| {
        encode(
            &Header::default(),
            &json!({
                "sub": user_id, "kind": "patient", "account_id": account,
                "exp": SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs() + 3600
            }),
            &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
        )
        .unwrap()
    };

    async fn app_pool() -> PgPool {
        PgPool::connect(
            &std::env::var("APP_DATABASE_URL")
                .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into()),
        )
        .await
        .unwrap()
    }

    // Patient propriétaire : les deux rappels, triés par due_at ASC (le
    // passé avant le futur).
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_token(patient_user_id, account_id)),
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
    let items = v["data"].as_array().unwrap();

    let positions: Vec<usize> = [reminder_past_id, reminder_future_id]
        .iter()
        .map(|id| {
            items
                .iter()
                .position(|i| i["id"].as_str() == Some(&id.to_string()))
                .unwrap_or_else(|| panic!("rappel {id} attendu dans la réponse"))
        })
        .collect();
    assert!(
        positions[0] < positions[1],
        "le rappel passé doit apparaître avant le rappel futur (due_at ASC), positions: {positions:?}"
    );

    // Autre patient : ni l'un ni l'autre rappel ne doit être visible.
    let state2 = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let response2 = app(state2)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/reminders")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_token(other_patient_user_id, other_account_id)
                    ),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response2.status(), StatusCode::OK);
    let body2 = axum::body::to_bytes(response2.into_body(), usize::MAX)
        .await
        .unwrap();
    let v2: serde_json::Value = serde_json::from_slice(&body2).unwrap();
    let items2 = v2["data"].as_array().unwrap();
    assert!(
        !items2
            .iter()
            .any(|i| i["id"].as_str() == Some(&reminder_past_id.to_string())
                || i["id"].as_str() == Some(&reminder_future_id.to_string())),
        "un autre patient ne doit voir aucun des deux rappels (RLS reminder_patient_read)"
    );

    // Cleanup
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM reminder WHERE cabinet_id = $1")
        .bind(cabinet_id)
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
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(account_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(other_account_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(patient_user_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_patient_user_id)
        .execute(&db)
        .await
        .ok();
}
