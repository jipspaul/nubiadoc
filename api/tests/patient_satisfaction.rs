//! Tests d'intégration : agrégat de satisfaction sur GET /v1/cabinet/patients/:id (#4161)

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

const JWT_SECRET: &str = "test-jwt-secret-patient-satisfaction";

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
    prac_id: Uuid,
    prac_user_id: Uuid,
    provider_id: Uuid,
    patient_id: Uuid,
    patient_account_id: Uuid,
}

async fn setup(db: &PgPool, tag: &str) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let prac_user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let provider_id = Uuid::new_v4();
    let patient_user_id = Uuid::new_v4();
    let patient_account_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let appointment_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(prac_user_id)
    .bind(format!("patsat-{}-prac+{}@nubia.test", tag, prac_user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(patient_user_id)
    .bind(format!("patsat-{}-pat+{}@nubia.test", tag, patient_user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name) \
         VALUES ($1, $2, 'Claire', 'Satisfaction')",
    )
    .bind(patient_account_id)
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
        .bind(format!("Cabinet PatSat {} {}", tag, cabinet_id))
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
        "INSERT INTO provider \
         (id, cabinet_id, practitioner_id, user_id, display_name, is_listed, rpps_verified) \
         VALUES ($1, $2, $3, $4, 'Dr. PatSat', true, true)",
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
         VALUES ($1, $2, 'Claire', 'Satisfaction', $3)",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .bind(patient_account_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Relation de soin requise pour que le praticien voie la fiche complète
    // (garde `has_appointment` de get_cabinet_patient).
    sqlx::query(
        "INSERT INTO appointment \
         (id, cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status) \
         VALUES ($1, $2, $3, $4, \
                 now() - interval '7 days', now() - interval '7 days' + interval '1 hour', \
                 'done')",
    )
    .bind(appointment_id)
    .bind(cabinet_id)
    .bind(patient_id)
    .bind(prac_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    tx.commit().await.unwrap();

    Fixtures {
        cabinet_id,
        prac_id,
        prac_user_id,
        provider_id,
        patient_id,
        patient_account_id,
    }
}

/// Insère un avis avec un `created_at` explicite (déterminisme du "dernier avis").
async fn insert_review(
    db: &PgPool,
    provider_id: Uuid,
    patient_account_id: Uuid,
    rating: i32,
    status: &str,
    comment: Option<&str>,
    days_ago: i64,
) {
    sqlx::query(
        "INSERT INTO review \
         (provider_id, patient_account_id, rating, comment, status, author_display, \
          idempotency_key, created_at) \
         VALUES ($1, $2, $3, $4, $5, 'Claire S.', $6, now() - ($7 || ' days')::interval)",
    )
    .bind(provider_id)
    .bind(patient_account_id)
    .bind(rating)
    .bind(comment)
    .bind(status)
    .bind(Uuid::new_v4().to_string())
    .bind(days_ago.to_string())
    .execute(db)
    .await
    .unwrap();
}

async fn teardown(db: &PgPool, f: &Fixtures) {
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
    sqlx::query("DELETE FROM review WHERE patient_account_id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM patient_account WHERE id = $1")
        .bind(f.patient_account_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.prac_user_id)
        .execute(db)
        .await
        .ok();
}

#[tokio::test]
async fn patient_detail_with_two_reviews_exposes_satisfaction_aggregate() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "two").await;

    // 2 avis publiés : 3 étoiles (il y a 2 jours), 5 étoiles (hier, le plus récent).
    insert_review(
        &db,
        f.provider_id,
        f.patient_account_id,
        3,
        "published",
        None,
        2,
    )
    .await;
    insert_review(
        &db,
        f.provider_id,
        f.patient_account_id,
        5,
        "published",
        Some("Excellent accueil"),
        1,
    )
    .await;
    // Avis pending : ne doit PAS compter dans l'agrégat.
    insert_review(
        &db,
        f.provider_id,
        f.patient_account_id,
        1,
        "pending",
        None,
        0,
    )
    .await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", f.patient_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(f.prac_user_id, f.cabinet_id, "practitioner")
                    ),
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

    let satisfaction = &v["satisfaction"];
    assert_eq!(satisfaction["review_count"], 2);
    assert_eq!(satisfaction["avg_rating"], 4.0, "moyenne de 3 et 5 = 4.0");
    assert_eq!(satisfaction["last_review"]["rating"], 5);
    assert_eq!(satisfaction["last_review"]["comment"], "Excellent accueil");

    teardown(&db, &f).await;
}

#[tokio::test]
async fn patient_detail_without_reviews_satisfaction_is_null() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = setup(&db, "none").await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}", f.patient_id))
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(f.prac_user_id, f.cabinet_id, "practitioner")
                    ),
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

    assert_eq!(v["satisfaction"], serde_json::Value::Null);

    teardown(&db, &f).await;
}
