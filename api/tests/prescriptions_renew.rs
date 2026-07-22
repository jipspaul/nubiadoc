//! Tests d'intégration : POST /v1/cabinet/prescriptions/{id}/renew (#4131)

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

const JWT_SECRET: &str = "test-secret-prescriptions-renew";

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
        &json!({
            "sub": sub,
            "kind": "pro",
            "cabinet_id": cabinet_id,
            "role": "practitioner",
            "exp": exp
        }),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixture {
    cabinet_id: Uuid,
    prac_user_id: Uuid,
    prac_id: Uuid,
    patient_id: Uuid,
    source_prescription_id: Uuid,
}

/// Seed : cabinet + practitioner + patient + appointment passé (garde
/// relation-de-soin) + ordonnance `signed` avec 2 lignes.
async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let source_prescription_id = Uuid::new_v4();

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
    .bind(format!("presc-renew+{prac_user_id}@nubia.test"))
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Presc Renew Test', 'dentaire')",
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
         VALUES ($1, $2, 'Patient', 'Renew')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, motif) \
         VALUES ($1, $2, $3, $4, now() - interval '1 hour', now(), 'done', 'contrôle')",
    )
    .bind(Uuid::new_v4())
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO prescription (id, cabinet_id, patient_id, practitioner_id, status, signed_at) \
         VALUES ($1, $2, $3, $4, 'signed', now() - interval '30 days')",
    )
    .bind(source_prescription_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO prescription_item \
         (cabinet_id, prescription_id, label, form, posology, duration, quantity) \
         VALUES \
         ($1, $2, 'Amoxicilline 1g', 'comprimé', '1 cp x 2/jour', '7 jours', 'QSP 14 cp'), \
         ($1, $2, 'Paracétamol 1g', 'comprimé', '1 cp x 3/jour', '5 jours', NULL)",
    )
    .bind(cabinet_id)
    .bind(source_prescription_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        prac_user_id,
        prac_id,
        patient_id,
        source_prescription_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM prescription_item WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM prescription WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

fn state_with(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

async fn renew(
    state: AppState,
    prescription_id: Uuid,
    token: &str,
) -> (StatusCode, serde_json::Value) {
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/v1/cabinet/prescriptions/{prescription_id}/renew"))
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
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

// ── Test 1 : renouveler une ordonnance signed crée un brouillon avec les mêmes lignes ──

#[tokio::test]
async fn renew_signed_prescription_creates_draft_with_same_items() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let (status, resp) = renew(
        state_with(app_pool().await),
        f.source_prescription_id,
        &token,
    )
    .await;

    assert_eq!(status, StatusCode::CREATED);
    let new_id: Uuid = resp["prescription_id"].as_str().unwrap().parse().unwrap();
    assert_ne!(new_id, f.source_prescription_id);

    let presc_row = sqlx::query("SELECT status, patient_id FROM prescription WHERE id = $1")
        .bind(new_id)
        .fetch_one(&db)
        .await
        .unwrap();
    let status: String = sqlx::Row::try_get(&presc_row, "status").unwrap();
    let patient_id: Uuid = sqlx::Row::try_get(&presc_row, "patient_id").unwrap();
    assert_eq!(status, "draft");
    assert_eq!(patient_id, f.patient_id);

    let items = sqlx::query(
        "SELECT label, posology, duration FROM prescription_item \
         WHERE prescription_id = $1 ORDER BY label",
    )
    .bind(new_id)
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(items.len(), 2);
    let labels: Vec<String> = items
        .iter()
        .map(|r| sqlx::Row::try_get::<String, _>(r, "label").unwrap())
        .collect();
    assert_eq!(
        labels,
        vec!["Amoxicilline 1g".to_string(), "Paracétamol 1g".to_string()]
    );

    cleanup(&db, &f).await;
}

// ── Test 2 : renouveler une ordonnance d'un autre cabinet → 404 ─────────────

#[tokio::test]
async fn renew_prescription_of_other_cabinet_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;

    // Second cabinet, sans lien avec l'ordonnance source.
    let other_cabinet_id = Uuid::new_v4();
    let other_prac_user_id = Uuid::new_v4();
    let other_prac_id = Uuid::new_v4();

    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(other_cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .unwrap();
        sqlx::query(
            "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
        )
        .bind(other_prac_user_id)
        .bind(format!("presc-renew-other+{other_prac_user_id}@nubia.test"))
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) \
             VALUES ($1, 'Cabinet Presc Renew Other', 'dentaire')",
        )
        .bind(other_cabinet_id)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
            .bind(other_prac_id)
            .bind(other_cabinet_id)
            .bind(other_prac_user_id)
            .execute(&mut *tx)
            .await
            .unwrap();
        tx.commit().await.unwrap();
    }

    let other_token = make_practitioner_token(other_prac_user_id, other_cabinet_id);
    let (status, _) = renew(
        state_with(app_pool().await),
        f.source_prescription_id,
        &other_token,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Cleanup du second cabinet.
    {
        let mut tx = db.begin().await.unwrap();
        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(other_cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM practitioner WHERE cabinet_id = $1")
            .bind(other_cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        sqlx::query("DELETE FROM cabinet WHERE id = $1")
            .bind(other_cabinet_id)
            .execute(&mut *tx)
            .await
            .ok();
        tx.commit().await.ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(other_prac_user_id)
        .execute(&db)
        .await
        .ok();

    cleanup(&db, &f).await;
}

// ── Test 3 : ordonnance inexistante → 404 ────────────────────────────────────

#[tokio::test]
async fn renew_unknown_prescription_returns_404() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;
    let token = make_practitioner_token(f.prac_user_id, f.cabinet_id);

    let (status, _) = renew(state_with(app_pool().await), Uuid::new_v4(), &token).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}
