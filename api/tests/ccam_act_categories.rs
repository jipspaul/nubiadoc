//! Tests d'intégration : `GET/PUT /v1/cabinet/settings/act-categories`
//! (réglage cabinet) + filtrage par catégories activées sur
//! `GET /v1/ccam/acts` (#7186).

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

const JWT_SECRET: &str = "test-secret-ccam-act-categories";

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

fn make_token(sub: Uuid, cabinet_id: Uuid, role: &str) -> String {
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
            role: role.into(),
            exp: exp(),
        },
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

struct Fixtures {
    cabinet_id: Uuid,
    user_id: Uuid,
    /// Code CCAM unique à ce fichier de test.
    code: String,
}

/// Cabinet + app_user (admin) + une ligne `ccam_act` de catégorie `chirurgie`.
async fn insert_fixtures(db: &PgPool) -> Fixtures {
    let cabinet_id = Uuid::new_v4();
    let user_id = Uuid::new_v4();
    let code = format!("T{}", &Uuid::new_v4().simple().to_string()[..6]).to_uppercase();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("ccam-act-categories+{}@nubia.test", user_id))
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) \
         VALUES ($1, 'Cabinet Act-Categories Test', 'dentaire')",
    )
    .bind(cabinet_id)
    .execute(db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO ccam_act \
         (code, label, tarif_cents, secteur1_cents, optam_cents, panier_sante, active, category) \
         VALUES ($1, 'Acte de chirurgie de test #7186', 1000, 1000, NULL, NULL, true, 'chirurgie')",
    )
    .bind(&code)
    .execute(db)
    .await
    .unwrap();

    Fixtures {
        cabinet_id,
        user_id,
        code,
    }
}

async fn cleanup_fixtures(db: &PgPool, f: &Fixtures) {
    sqlx::query("DELETE FROM ccam_act WHERE code = $1")
        .bind(&f.code)
        .execute(db)
        .await
        .ok();
    // `cabinet_act_category_setting` n'a pas de ON DELETE CASCADE depuis
    // `cabinet` — nettoyage explicite avant de supprimer le cabinet.
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(f.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet_act_category_setting WHERE cabinet_id = $1")
        .bind(f.cabinet_id)
        .execute(&mut *tx)
        .await
        .ok();
    tx.commit().await.ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(f.cabinet_id)
        .execute(db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(f.user_id)
        .execute(db)
        .await
        .ok();
}

async fn request(
    db: PgPool,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        builder = builder.header("authorization", format!("Bearer {t}"));
    }
    let body = match body {
        Some(v) => {
            builder = builder.header("content-type", "application/json");
            Body::from(serde_json::to_vec(&v).unwrap())
        }
        None => Body::empty(),
    };
    let response = app(make_state(db))
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null),
    )
}

// ── Test 1 : GET par défaut → toutes les catégories connues, enabled=true ────

#[tokio::test]
async fn get_returns_all_categories_enabled_by_default() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = insert_fixtures(&owner_db).await;
    let token = make_token(f.user_id, f.cabinet_id, "admin");

    let (status, json) = request(
        app_pool().await,
        "GET",
        "/v1/cabinet/settings/act-categories",
        Some(&token),
        None,
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    let data = json["data"].as_array().expect("data tableau");
    assert_eq!(data.len(), 12, "12 catégories connues (CHECK migration 0283)");
    assert!(
        data.iter().all(|c| c["enabled"] == true),
        "aucun override posé → tout activé par défaut"
    );
    assert!(data.iter().any(|c| c["category"] == "chirurgie"));

    cleanup_fixtures(&owner_db, &f).await;
}

// ── Test 2 : secrétaire/praticien → 403 (réservé admin/manager) ──────────────

#[tokio::test]
async fn get_forbidden_for_non_admin_roles() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = insert_fixtures(&owner_db).await;

    for role in ["secretary", "practitioner"] {
        let token = make_token(Uuid::new_v4(), f.cabinet_id, role);
        let (status, _) = request(
            app_pool().await,
            "GET",
            "/v1/cabinet/settings/act-categories",
            Some(&token),
            None,
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "role {role} doit être 403");
    }

    cleanup_fixtures(&owner_db, &f).await;
}

// ── Test 3 : PUT catégorie inconnue → 400 ─────────────────────────────────────

#[tokio::test]
async fn put_rejects_unknown_category() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = insert_fixtures(&owner_db).await;
    let token = make_token(f.user_id, f.cabinet_id, "manager");

    let (status, json) = request(
        app_pool().await,
        "PUT",
        "/v1/cabinet/settings/act-categories",
        Some(&token),
        Some(json!({"categories": [{"category": "inconnu", "enabled": false}]})),
    )
    .await;

    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(json["code"], "invalid_act_category");

    cleanup_fixtures(&owner_db, &f).await;
}

// ── Test 4 : PUT désactive une catégorie → GET la reflète, et le catalogue
//    CCAM (`GET /v1/ccam/acts`) masque les actes de cette catégorie —
//    `?all=true` les fait réapparaître. ────────────────────────────────────

#[tokio::test]
async fn disabling_category_filters_ccam_catalog() {
    if !db_available() {
        return;
    }
    let owner_db = owner_pool().await;
    let f = insert_fixtures(&owner_db).await;
    let admin_token = make_token(f.user_id, f.cabinet_id, "admin");

    // Avant désactivation : l'acte de test (catégorie chirurgie) est visible.
    let (status, json) = request(
        app_pool().await,
        "GET",
        &format!("/v1/ccam/acts?q={}", f.code),
        Some(&make_token(Uuid::new_v4(), f.cabinet_id, "practitioner")),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(json["data"]
        .as_array()
        .unwrap()
        .iter()
        .any(|a| a["code"] == f.code));

    // Désactive `chirurgie` pour ce cabinet via l'endpoint de réglage.
    let (status, json) = request(
        app_pool().await,
        "PUT",
        "/v1/cabinet/settings/act-categories",
        Some(&admin_token),
        Some(json!({"categories": [{"category": "chirurgie", "enabled": false}]})),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let chirurgie = json["data"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["category"] == "chirurgie")
        .expect("chirurgie dans la réponse");
    assert_eq!(chirurgie["enabled"], false);

    // GET reflète bien l'override.
    let (status, json) = request(
        app_pool().await,
        "GET",
        "/v1/cabinet/settings/act-categories",
        Some(&admin_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        json["data"]
            .as_array()
            .unwrap()
            .iter()
            .find(|c| c["category"] == "chirurgie")
            .unwrap()["enabled"],
        false
    );

    // Le catalogue CCAM masque désormais l'acte de chirurgie de test.
    let practitioner_token = make_token(Uuid::new_v4(), f.cabinet_id, "practitioner");
    let (status, json) = request(
        app_pool().await,
        "GET",
        &format!("/v1/ccam/acts?q={}", f.code),
        Some(&practitioner_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        !json["data"]
            .as_array()
            .unwrap()
            .iter()
            .any(|a| a["code"] == f.code),
        "acte de catégorie désactivée masqué du catalogue"
    );

    // `?all=true` bypasse le filtre (ex. écran de réglage).
    let (status, json) = request(
        app_pool().await,
        "GET",
        &format!("/v1/ccam/acts?q={}&all=true", f.code),
        Some(&practitioner_token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        json["data"]
            .as_array()
            .unwrap()
            .iter()
            .any(|a| a["code"] == f.code),
        "`all=true` doit tout montrer, y compris les catégories désactivées"
    );

    cleanup_fixtures(&owner_db, &f).await;
}
