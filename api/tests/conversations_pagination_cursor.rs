//! Test d'intégration ciblé : GET /v1/conversations — curseur de pagination
//! quand une page se termine sur un fil sans message (#3771).

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde_json::json;
use sqlx::PgPool;
use std::collections::HashSet;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-conv-pagination";

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

/// Cabinet + patient + 3 fils AVEC message (horodatages distincts) + 2 fils
/// SANS message (last_message_at NULL — cf. #3771). Triés `DESC NULLS LAST`,
/// les 2 fils vides tombent donc en fin de liste, exactement la frontière de
/// page qui déclenchait le curseur null.
async fn setup_fixture(db: &PgPool) -> (Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("convpag-pro+{user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("convpag-patient+{patient_user_id}@nubia.test"))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Camille', 'Pagination')",
    )
    .bind(account_id)
    .bind(patient_user_id)
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
        .bind(format!("Cabinet ConvPag Test {cabinet_id}"))
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name, patient_account_id) \
         VALUES ($1, $2, 'Camille', 'Pagination', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // 3 fils AVEC message, horodatages distincts (plus récent en premier).
    for i in 0..3i64 {
        let conv_id = Uuid::new_v4();
        sqlx::query("INSERT INTO conversation (id, cabinet_id, patient_id) VALUES ($1, $2, $3)")
            .bind(conv_id)
            .bind(cabinet_id)
            .bind(patient_id)
            .execute(&mut *tx)
            .await
            .unwrap();

        sqlx::query(
            "INSERT INTO message \
             (id, cabinet_id, conversation_id, sender_kind, body_ciphertext, body_key_ref, created_at) \
             VALUES ($1, $2, $3, 'patient', 'salut', 'poc', now() - ($4 || ' minutes')::interval)",
        )
        .bind(Uuid::new_v4())
        .bind(cabinet_id)
        .bind(conv_id)
        .bind(i.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    }

    // 2 fils SANS message (last_message_at NULL — la frontière de page #3771).
    for _ in 0..2 {
        sqlx::query("INSERT INTO conversation (id, cabinet_id, patient_id) VALUES ($1, $2, $3)")
            .bind(Uuid::new_v4())
            .bind(cabinet_id)
            .bind(patient_id)
            .execute(&mut *tx)
            .await
            .unwrap();
    }

    tx.commit().await.unwrap();

    (cabinet_id, patient_user_id, account_id)
}

async fn cleanup_fixture(db: &PgPool, cabinet_id: Uuid, patient_user_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM message WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM conversation WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(patient_user_id)
        .execute(db)
        .await
        .ok();
}

/// Reproduction exacte de #3771 : `limit=3` place la 3e conversation avec
/// message en fin de page — `next_cursor` doit rester non-null (2 fils vides
/// restent à parcourir), et paginer jusqu'au bout doit atteindre les 5 fils
/// sans doublon.
#[tokio::test]
async fn conversations_cursor_stays_reachable_across_null_last_message_at_boundary() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, patient_user_id, account_id) = setup_fixture(&db).await;

    let mut seen: HashSet<String> = HashSet::new();
    let mut cursor: Option<String> = None;
    let mut pages = 0;

    loop {
        pages += 1;
        assert!(pages <= 10, "boucle de pagination anormalement longue");

        let state = AppState {
            db: app_pool().await,
            jwt_secret: JWT_SECRET.to_string(),
            mailer: Arc::new(StubMailer),
        };

        let uri = match &cursor {
            Some(c) => format!("/v1/conversations?limit=3&cursor={}", urlencode(c)),
            None => "/v1/conversations?limit=3".to_string(),
        };

        let response = app(state)
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(uri)
                    .header(
                        "Authorization",
                        format!("Bearer {}", make_patient_jwt(patient_user_id, account_id)),
                    )
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(response.status(), StatusCode::OK);
        let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();

        let data = v["data"].as_array().unwrap();
        for item in data {
            let id = item["id"].as_str().unwrap().to_string();
            assert!(
                seen.insert(id),
                "conversation vue deux fois — doublon de curseur"
            );
        }

        let next_cursor = v["page"]["next_cursor"].as_str().map(str::to_string);
        if next_cursor.is_none() {
            break;
        }
        cursor = next_cursor;
    }

    assert_eq!(
        seen.len(),
        5,
        "les 5 conversations (3 avec message + 2 vides) doivent toutes être atteignables"
    );

    cleanup_fixture(&db, cabinet_id, patient_user_id).await;
}

fn urlencode(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' | '.' | '~' => c.to_string(),
            _ => format!("%{:02X}", c as u32),
        })
        .collect()
}
