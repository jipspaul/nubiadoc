//! Tests d'intégration : grille tarifaire labo (#7164, DP-F19.b)
//! - POST /v1/cabinet/lab-price-list/import
//! - GET /v1/cabinet/lab-price-list
//! - POST /v1/cabinet/lab-work-orders avec price_list_item_id

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

const JWT_SECRET: &str = "test-jwt-secret-lab-price-list";

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
    user_id: Uuid,
    patient_id: Uuid,
}

async fn seed(db: &PgPool) -> Fixture {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let prac_id = Uuid::new_v4();
    let patient_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("labpricelist+{user_id}@nubia.test"))
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
         VALUES ($1, 'Cabinet LabPriceList Test', 'dentaire')",
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
         VALUES ($1, $2, 'Patient', 'LabPriceList')",
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
    tx.commit().await.unwrap();

    Fixture {
        cabinet_id,
        user_id,
        patient_id,
    }
}

async fn cleanup(db: &PgPool, f: &Fixture) {
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM lab_work_order WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM lab_price_list WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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
    sqlx::query("DELETE FROM patient WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
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
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

#[tokio::test]
async fn import_csv_creates_items_and_reimport_updates_price() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let csv = "lab_name;item_label;item_code;price\n\
               Dentalis;Couronne céramique;CR-CER;250.00\n\
               Dentalis;Bridge 3 éléments;BR-3;600,50\n\
               ;Colonne décalée;BAD;10\n\
               Dentalis;Prix aberrant;OVF;88888888888\n";

    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/lab-price-list/import")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(f.user_id, f.cabinet_id, "admin")),
                )
                .body(Body::from(json!({ "csv": csv }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["imported"].as_array().unwrap().len(), 2);
    assert_eq!(
        v["errors"].as_array().unwrap().len(),
        2,
        "colonne décalée ET prix aberrant (hors borne, ex-débordement i32) rejetés"
    );
    assert_eq!(v["imported"][0]["price_cents"], 25000);
    assert_eq!(
        v["imported"][1]["price_cents"], 60050,
        "virgule décimale tolérée comme séparateur"
    );
    assert!(
        v["errors"]
            .as_array()
            .unwrap()
            .iter()
            .any(|e| e["raw"].as_str().unwrap().contains("88888888888")
                && e["error"] == "prix_invalide"),
        "un prix hors de toute plausibilité métier doit être rejeté, pas saturé silencieusement à i32::MAX"
    );

    // Liste : les 2 lignes importées apparaissent.
    let list_response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/lab-price-list")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(f.user_id, f.cabinet_id, "admin")),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(list_response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(list_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let items: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let items = items.as_array().unwrap();
    assert_eq!(items.len(), 2);

    // Réimport même jour, même labo/code, prix corrigé -> mise à jour (pas
    // de doublon, pas d'erreur de contrainte unique).
    let csv_update = "Dentalis;Couronne céramique;CR-CER;275.00\n";
    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/lab-price-list/import")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(f.user_id, f.cabinet_id, "admin")),
                )
                .body(Body::from(json!({ "csv": csv_update }).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(v["errors"].as_array().unwrap().len(), 0);
    assert_eq!(v["imported"][0]["price_cents"], 27500);

    let list_response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/v1/cabinet/lab-price-list")
                .header(
                    "Authorization",
                    format!("Bearer {}", make_pro_jwt(f.user_id, f.cabinet_id, "admin")),
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let bytes = axum::body::to_bytes(list_response.into_body(), usize::MAX)
        .await
        .unwrap();
    let items: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let items = items.as_array().unwrap();
    assert_eq!(items.len(), 2, "toujours 2 lignes, pas de doublon");
    let cr_cer = items.iter().find(|i| i["item_code"] == "CR-CER").unwrap();
    assert_eq!(cr_cer["price_cents"], 27500);

    cleanup(&db, &f).await;
}

#[tokio::test]
async fn create_lab_work_order_with_price_list_item_prefills_and_validates_ownership() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let f = seed(&db).await;

    let item_id = Uuid::new_v4();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO lab_price_list (id, cabinet_id, lab_name, item_label, item_code, price_cents) \
         VALUES ($1, $2, 'Dentalis', 'Couronne céramique', 'CR-CER', 25000)",
    )
    .bind(item_id)
    .bind(f.cabinet_id)
    .execute(&mut *tx)
    .await
    .unwrap();
    tx.commit().await.unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state.clone())
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/lab-work-orders")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(f.user_id, f.cabinet_id, "practitioner")
                    ),
                )
                .body(Body::from(
                    json!({
                        "patient_id": f.patient_id,
                        "lab_name": "Dentalis",
                        "purchase_price_cents": 25000,
                        "price_list_item_id": item_id
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::CREATED);

    // Un price_list_item_id d'un AUTRE cabinet doit être rejeté (404).
    let foreign_item_id = Uuid::new_v4();
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/lab-work-orders")
                .header("content-type", "application/json")
                .header(
                    "Authorization",
                    format!(
                        "Bearer {}",
                        make_pro_jwt(f.user_id, f.cabinet_id, "practitioner")
                    ),
                )
                .body(Body::from(
                    json!({
                        "patient_id": f.patient_id,
                        "lab_name": "Dentalis",
                        "purchase_price_cents": 25000,
                        "price_list_item_id": foreign_item_id
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    cleanup(&db, &f).await;
}
