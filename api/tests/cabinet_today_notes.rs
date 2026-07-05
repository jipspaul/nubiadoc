//! Tests d'intégration : GET /v1/cabinet/today-notes (#3368 — la route
//! n'existait pas, le dashboard praticien affichait un faux état vide).

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use sqlx::PgPool;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-secret-today-notes";

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

fn make_pro_token(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900;
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: role.into(),
            exp,
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// cabinet + praticien + patient + RDV + séance démarrée aujourd'hui.
async fn insert_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid, Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appt_id = Uuid::new_v4();
    let session_id = Uuid::new_v4();

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
    .bind(format!("today-prac+{}@nubia.test", prac_user_id))
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Today Notes', 'dentaire')",
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
         VALUES ($1, $2, 'Marc', 'Dubois')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', now(), 'in_progress', 'soin')",
    )
    .bind(appt_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO consultation_session \
         (id, cabinet_id, appointment_id, practitioner_id, status) \
         VALUES ($1, $2, $3, $4, 'in_progress')",
    )
    .bind(session_id)
    .bind(cabinet_id)
    .bind(appt_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    (
        cabinet_id,
        prac_id,
        prac_user_id,
        patient_id,
        appt_id,
        session_id,
    )
}

async fn cleanup(db: &PgPool, cabinet_id: Uuid, ids: (Uuid, Uuid, Uuid, Uuid)) {
    let (prac_user_id, patient_id, appt_id, session_id) = ids;
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    for (table, id) in [
        ("consultation_session", session_id),
        ("appointment", appt_id),
        ("patient", patient_id),
    ] {
        sqlx::query(&format!("DELETE FROM {table} WHERE id = $1"))
            .bind(id)
            .execute(&mut *tx)
            .await
            .ok();
    }
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

async fn get(token: &str) -> (StatusCode, serde_json::Value) {
    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/today-notes")
                .header("Authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, json)
}

/// La séance démarrée aujourd'hui apparaît avec initiales + statut, zéro PII.
#[tokio::test]
async fn today_notes_returns_todays_sessions() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, _prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;

    let token = make_pro_token(prac_user_id, cabinet_id, "practitioner");
    let (status, json) = get(&token).await;

    assert_eq!(status, StatusCode::OK, "la route doit exister (#3368)");
    let data = json["data"].as_array().expect("data[]");
    assert_eq!(data.len(), 1);
    assert_eq!(data[0]["id"], session_id.to_string());
    assert_eq!(data[0]["status"], "in_progress");
    assert_eq!(
        data[0]["patient_initials"], "M.D.",
        "initiales uniquement, pas de nom complet (zéro PII sur le dashboard)"
    );
    assert!(data[0]["started_at"].is_string());

    cleanup(
        &db,
        cabinet_id,
        (prac_user_id, patient_id, appt_id, session_id),
    )
    .await;
}

/// Cross-tenant : un autre cabinet ne voit pas la séance.
#[tokio::test]
async fn today_notes_cross_tenant_empty() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, _prac_id, prac_user_id, patient_id, appt_id, session_id) =
        insert_fixture(&db).await;

    let other = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "practitioner");
    let (status, json) = get(&other).await;
    assert_eq!(status, StatusCode::OK);
    let ids: Vec<String> = json["data"]
        .as_array()
        .unwrap_or(&vec![])
        .iter()
        .filter_map(|e| e["id"].as_str().map(String::from))
        .collect();
    assert!(
        !ids.contains(&session_id.to_string()),
        "cross-tenant : la séance ne doit pas fuiter"
    );

    cleanup(
        &db,
        cabinet_id,
        (prac_user_id, patient_id, appt_id, session_id),
    )
    .await;
}

/// Secrétaire → 403 (périmètre journal clinique, praticien uniquement).
#[tokio::test]
async fn today_notes_secretary_403() {
    if !db_available() {
        return;
    }
    let token = make_pro_token(Uuid::new_v4(), Uuid::new_v4(), "secretary");
    let (status, _) = get(&token).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}
