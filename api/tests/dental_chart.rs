//! Tests d'intégration : GET + PUT /v1/cabinet/patients/:id/dental-chart (§14)
//!
//! Tests requis par l'issue #782 :
//! 1. GET avec token secretary → 403 (R.4127-72)
//! 2. GET avec token praticien → 200 { teeth, updated_at }
//! 3. PUT avec token praticien → 200, jsonb persisté en base

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

const JWT_SECRET: &str = "test-secret-dental-chart";

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

fn make_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

fn exp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 900
}

fn make_practitioner_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "practitioner".into(),
            exp: exp(),
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

fn make_secretary_token(sub: Uuid, cabinet_id: Uuid) -> String {
    #[derive(serde::Serialize)]
    struct Claims {
        sub: Uuid,
        kind: String,
        cabinet_id: Uuid,
        role: String,
        exp: u64,
    }
    encode(
        &Header::default(),
        &Claims {
            sub,
            kind: "pro".into(),
            cabinet_id,
            role: "secretary".into(),
            exp: exp(),
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

/// Insère les fixtures minimales : cabinet + app_user + patient + appointment.
/// Retourne `(cabinet_id, user_id, patient_id)`.
async fn insert_fixtures(db: &PgPool) -> (Uuid, Uuid, Uuid) {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("dc-prac+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Dental Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    sqlx::query("INSERT INTO practitioner (id, cabinet_id, user_id) VALUES ($1, $2, $3)")
        .bind(prac_id)
        .bind(cabinet_id)
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .unwrap();

    sqlx::query(
        "INSERT INTO patient (id, cabinet_id, first_name, last_name) \
         VALUES ($1, $2, 'Marie', 'Durand')",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();

    // Appointment passé : le praticien a consulté ce patient (requis par E.2.16.c).
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

    tx.commit().await.unwrap();

    (cabinet_id, user_id, patient_id)
}

async fn cleanup_fixtures(db: &PgPool, cabinet_id: Uuid, user_id: Uuid, patient_id: Uuid) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM dental_chart WHERE patient_id = $1")
        .bind(patient_id)
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
    tx.commit().await.ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(db)
        .await
        .ok();
}

// ── Test 1 : GET avec token secretary → 403 ───────────────────────────────────

#[tokio::test]
async fn get_dental_chart_secretary_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let secretary_id = Uuid::new_v4();
    let token = make_secretary_token(secretary_id, cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/dental-chart", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::FORBIDDEN);

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 2 : GET avec token praticien → 200 { teeth, updated_at } ─────────────

#[tokio::test]
async fn get_dental_chart_practitioner_returns_200() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(format!("/v1/cabinet/patients/{}/dental-chart", patient_id))
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(v["teeth"].is_object(), "teeth doit être un objet");
    assert!(
        v["updated_at"].is_string(),
        "updated_at doit être une chaîne"
    );

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 3 : PUT → 200, jsonb persisté en base ────────────────────────────────

#[tokio::test]
async fn put_dental_chart_persists_teeth_jsonb() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;

    let token = make_practitioner_token(user_id, cabinet_id);
    let teeth = json!({
        "11": { "status": "present", "notes": "légère usure" },
        "36": { "status": "carie", "notes": "à traiter" }
    });

    let resp = app(make_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/v1/cabinet/patients/{}/dental-chart", patient_id))
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", token))
                .body(Body::from(json!({ "teeth": teeth }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(resp.status(), StatusCode::OK);

    let bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert!(
        v["updated_at"].is_string(),
        "updated_at doit être une chaîne"
    );

    // Vérifie la persistance en base (rôle owner).
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    let row = sqlx::query(
        "SELECT teeth_status FROM dental_chart WHERE patient_id = $1 AND cabinet_id = $2",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let stored: serde_json::Value = row.try_get("teeth_status").unwrap();
    assert_eq!(
        stored, teeth,
        "teeth_status persisté doit correspondre au body envoyé"
    );

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 4 : PUT valeur de dent invalide → 422 (#3838) ───────────────────────

#[tokio::test]
async fn put_dental_chart_invalid_tooth_value_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;
    let token = make_practitioner_token(user_id, cabinet_id);

    let bad_bodies = [
        // Statut inconnu (chaîne libre).
        json!({"teeth": {"11": {"status": "TOTALLY_BOGUS_STATUS_XYZ"}}}),
        // Valeur scalaire au lieu d'un objet {status}.
        json!({"teeth": {"22": 99999}}),
        // Objet sans clé "status" du tout.
        json!({"teeth": {"33": {"nested": [1, 2, 3]}}}),
        // Clé additionnelle non reconnue.
        json!({"teeth": {"11": {"status": "sain", "unknown_field": "x"}}}),
    ];

    for body in bad_bodies {
        let resp = app(make_state(app_pool().await))
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/v1/cabinet/patients/{}/dental-chart", patient_id))
                    .header("content-type", "application/json")
                    .header("Authorization", format!("Bearer {}", token))
                    .body(Body::from(body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(
            resp.status(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "body accepté à tort : {body}"
        );
    }

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}

// ── Test 5 : PUT code de dent hors notation FDI → 422 (#4046) ────────────────
//
// `validate_teeth` (dental_chart.rs) valide déjà les clés (couverte
// uniquement côté valeurs par le test 4) : quadrant 1-4 → dent 1-8 (FDI
// permanente, 11-48), quadrant 5-8 → dent 1-5 (FDI lait, 51-85). Ce test
// comble ce trou de couverture ciblé par l'issue #4046, la validation
// elle-même existant déjà (#3838) — pas de changement fonctionnel requis.
#[tokio::test]
async fn put_dental_chart_invalid_tooth_code_returns_422() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let (cabinet_id, user_id, patient_id) = insert_fixtures(&db).await;
    let token = make_practitioner_token(user_id, cabinet_id);

    let bad_bodies = [
        // Quadrant 0 : hors FDI (1-8 uniquement).
        json!({"teeth": {"01": {"status": "sain"}}}),
        // Quadrant 9 : hors FDI.
        json!({"teeth": {"91": {"status": "sain"}}}),
        // Quadrant permanent (1-4) mais dent 9 : hors 1-8.
        json!({"teeth": {"19": {"status": "sain"}}}),
        // Quadrant lait (5-8) mais dent 6 : hors 1-5.
        json!({"teeth": {"56": {"status": "sain"}}}),
        // Longueur ≠ 2.
        json!({"teeth": {"111": {"status": "sain"}}}),
        // Non numérique.
        json!({"teeth": {"AB": {"status": "sain"}}}),
    ];

    for body in bad_bodies {
        let resp = app(make_state(app_pool().await))
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/v1/cabinet/patients/{}/dental-chart", patient_id))
                    .header("content-type", "application/json")
                    .header("Authorization", format!("Bearer {}", token))
                    .body(Body::from(body.to_string()))
                    .unwrap(),
            )
            .await
            .unwrap();

        assert_eq!(
            resp.status(),
            StatusCode::UNPROCESSABLE_ENTITY,
            "code dent accepté à tort : {body}"
        );
    }

    cleanup_fixtures(&db, cabinet_id, user_id, patient_id).await;
}
