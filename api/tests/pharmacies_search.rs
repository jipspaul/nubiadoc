//! Tests d'intégration : GET /v1/pharmacies — annuaire public (lot B1, issue #3306)

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

const JWT_SECRET: &str = "test-jwt-secret-pharmacies-search";

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

fn test_state(db: PgPool) -> AppState {
    AppState {
        db,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    }
}

/// Insère une pharmacie avec géolocalisation optionnelle (lng, lat).
async fn seed_pharmacy(
    db: &PgPool,
    name: &str,
    is_listed: bool,
    lnglat: Option<(f64, f64)>,
) -> Uuid {
    let id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO pharmacy (id, raison_sociale, is_listed, geo) \
         VALUES ($1, $2, $3, \
                 CASE WHEN $4::float8 IS NOT NULL \
                      THEN ST_SetSRID(ST_MakePoint($4, $5), 4326)::geography END)",
    )
    .bind(id)
    .bind(name)
    .bind(is_listed)
    .bind(lnglat.map(|(lng, _)| lng))
    .bind(lnglat.map(|(_, lat)| lat))
    .execute(db)
    .await
    .unwrap();
    id
}

async fn get_pharmacies(uri: &str) -> (StatusCode, serde_json::Value) {
    let response = app(test_state(app_pool().await))
        .oneshot(
            Request::builder()
                .method("GET")
                .uri(uri)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value =
        serde_json::from_slice(&body).unwrap_or_else(|_| serde_json::json!({}));
    (status, v)
}

// ── Test 1 : recherche par nom → seule la pharmacie listée sort ───────────────

#[tokio::test]
async fn search_returns_listed_pharmacy_only() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let marker = Uuid::new_v4().simple().to_string();
    let listed_id = seed_pharmacy(&db, &format!("Pharma-{marker} Listée"), true, None).await;
    seed_pharmacy(&db, &format!("Pharma-{marker} Cachée"), false, None).await;

    let (status, v) = get_pharmacies(&format!("/v1/pharmacies?q=Pharma-{marker}")).await;
    assert_eq!(status, StatusCode::OK);
    let data = v["data"].as_array().unwrap();
    assert_eq!(data.len(), 1, "seule la pharmacie listée doit sortir");
    assert_eq!(data[0]["id"], serde_json::json!(listed_id));
    assert!(
        data[0]["distance_m"].is_null(),
        "pas de point → pas de distance"
    );
}

// ── Test 2 : tri par distance + rayon ─────────────────────────────────────────

#[tokio::test]
async fn search_sorts_by_distance_and_honors_radius() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let marker = Uuid::new_v4().simple().to_string();
    // Paris centre (2.35, 48.86) ; proche ~1 km ; lointaine ~ Marseille.
    let near_id = seed_pharmacy(
        &db,
        &format!("Geo-{marker} Proche"),
        true,
        Some((2.36, 48.86)),
    )
    .await;
    let far_id = seed_pharmacy(
        &db,
        &format!("Geo-{marker} Lointaine"),
        true,
        Some((5.37, 43.30)),
    )
    .await;

    // Sans rayon : les deux sortent, la plus proche d'abord, distance_m renseignée.
    let (status, v) =
        get_pharmacies(&format!("/v1/pharmacies?q=Geo-{marker}&lat=48.86&lng=2.35")).await;
    assert_eq!(status, StatusCode::OK);
    let data = v["data"].as_array().unwrap();
    assert_eq!(data.len(), 2);
    assert_eq!(data[0]["id"], serde_json::json!(near_id));
    assert_eq!(data[1]["id"], serde_json::json!(far_id));
    assert!(data[0]["distance_m"].as_f64().unwrap() < data[1]["distance_m"].as_f64().unwrap());

    // Avec rayon 10 km : seule la proche sort.
    let (status, v) = get_pharmacies(&format!(
        "/v1/pharmacies?q=Geo-{marker}&lat=48.86&lng=2.35&radius_km=10"
    ))
    .await;
    assert_eq!(status, StatusCode::OK);
    let data = v["data"].as_array().unwrap();
    assert_eq!(data.len(), 1, "la pharmacie hors rayon doit être exclue");
    assert_eq!(data[0]["id"], serde_json::json!(near_id));
}

// ── Test 3 : lat sans lng → 422 ───────────────────────────────────────────────

#[tokio::test]
async fn search_lat_without_lng_returns_422() {
    if !db_available() {
        return;
    }
    let (status, _) = get_pharmacies("/v1/pharmacies?lat=48.86").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 4 : radius sans point → 422 ──────────────────────────────────────────

#[tokio::test]
async fn search_radius_without_point_returns_422() {
    if !db_available() {
        return;
    }
    let (status, _) = get_pharmacies("/v1/pharmacies?radius_km=5").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 5 : route publique, sans JWT → 200 ───────────────────────────────────

#[tokio::test]
async fn search_is_public_no_jwt_required() {
    if !db_available() {
        return;
    }
    let (status, v) = get_pharmacies("/v1/pharmacies").await;
    assert_eq!(status, StatusCode::OK);
    assert!(v["data"].is_array());
}
