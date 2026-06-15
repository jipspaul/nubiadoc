//! Tests d'intégration : POST /v1/auth/select-context

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

const JWT_SECRET: &str = "test-jwt-secret-select-context";

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

/// JWT pro sans cabinet_id (token login — précédant la sélection de contexte).
fn make_pro_jwt(user_id: Uuid) -> String {
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    encode(
        &Header::default(),
        &json!({"sub": user_id, "kind": "pro", "exp": exp}),
        &EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap()
}

// ── Test 1 : contexte valide → 200 + JWT portant cabinet_id + role ─────────────

#[tokio::test]
async fn select_context_valid_returns_200_with_token() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("sc-valid+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, 'Cabinet SC', 'dentiste')",
    )
    .bind(cabinet_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) VALUES ($1, $2, 'admin', true)",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/select-context")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .body(Body::from(json!({"cabinet_id": cabinet_id}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let set_cookie = response.headers().get("set-cookie");
    assert!(set_cookie.is_some(), "Set-Cookie header must be present");
    let cookie_val = set_cookie.unwrap().to_str().unwrap();
    assert!(
        cookie_val.starts_with("nubia_jwt="),
        "cookie name must be nubia_jwt"
    );
    assert!(cookie_val.contains("HttpOnly"), "cookie must be HttpOnly");

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert!(
        v["access_token"].is_string(),
        "access_token must be present"
    );
    assert_eq!(v["token_type"], "Bearer");
    assert!(v["expires_in"].is_number(), "expires_in must be present");

    sqlx::query("DELETE FROM cabinet_membership WHERE user_id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 1b : user multi-contexte → 200, JWT scoped contient cabinet_id + role ──────────────

#[tokio::test]
async fn select_context_multicontext_jwt_contains_cabinet_and_role() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let cabinet_a = Uuid::new_v4();
    let cabinet_b = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("sc-multi+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    for (cid, name) in [
        (cabinet_a, "Cabinet Multi A"),
        (cabinet_b, "Cabinet Multi B"),
    ] {
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentiste')",
        )
        .bind(cid)
        .bind(name)
        .execute(&db)
        .await
        .unwrap();
    }

    // user membre actif de cabinet_a (admin) + ancien membre de cabinet_b (inactif).
    // Contrainte 0099 : un seul active=true AND left_at IS NULL par user_id.
    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) VALUES ($1, $2, 'admin', true)",
    )
    .bind(cabinet_a)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) VALUES ($1, $2, 'practitioner', false)",
    )
    .bind(cabinet_b)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    // Sélectionne cabinet_a (rôle admin).
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/select-context")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .body(Body::from(json!({"cabinet_id": cabinet_a}).to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    // Vérifie Set-Cookie nubia_jwt présent et HttpOnly.
    let set_cookie = response.headers().get("set-cookie");
    assert!(set_cookie.is_some(), "Set-Cookie header must be present");
    let cookie_val = set_cookie.unwrap().to_str().unwrap();
    assert!(
        cookie_val.starts_with("nubia_jwt="),
        "cookie name must be nubia_jwt"
    );
    assert!(cookie_val.contains("HttpOnly"), "cookie must be HttpOnly");

    // Décode le JWT retourné et vérifie cabinet_id + role.
    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    let token_str = v["access_token"]
        .as_str()
        .expect("access_token must be a string");

    let key = jsonwebtoken::DecodingKey::from_secret(JWT_SECRET.as_bytes());
    let mut validation = jsonwebtoken::Validation::default();
    validation.validate_exp = true;
    let decoded = jsonwebtoken::decode::<serde_json::Value>(token_str, &key, &validation)
        .expect("JWT must be decodable with the test secret");
    let claims = decoded.claims;

    assert_eq!(
        claims["cabinet_id"].as_str().unwrap(),
        cabinet_a.to_string(),
        "JWT cabinet_id must match the requested cabinet"
    );
    assert_eq!(
        claims["role"].as_str().unwrap(),
        "admin",
        "JWT role must reflect the membership role"
    );

    // Cleanup.
    for cid in [cabinet_a, cabinet_b] {
        sqlx::query("DELETE FROM cabinet_membership WHERE user_id = $1 AND cabinet_id = $2")
            .bind(user_id)
            .bind(cid)
            .execute(&db)
            .await
            .ok();
        sqlx::query("DELETE FROM cabinet WHERE id = $1")
            .bind(cid)
            .execute(&db)
            .await
            .ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2 : cabinet_id inconnu → 403 no_active_membership ───────────────────

#[tokio::test]
async fn select_context_unknown_cabinet_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("sc-unknown+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let unknown_cabinet_id = Uuid::new_v4();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/select-context")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .body(Body::from(
                    json!({"cabinet_id": unknown_cabinet_id}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    assert!(
        response.headers().get("set-cookie").is_none(),
        "pas de cookie nubia_jwt émis sur 403"
    );

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["error"], "no_active_membership");

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}

// ── Test 2b : token absent → 401 ─────────────────────────────────────────────

#[tokio::test]
async fn select_context_no_token_returns_401() {
    let Some(state) = (async {
        let url = std::env::var("APP_DATABASE_URL").ok()?;
        let pool = sqlx::PgPool::connect(&url).await.ok()?;
        Some(AppState {
            db: pool,
            jwt_secret: JWT_SECRET.to_string(),
            mailer: Arc::new(StubMailer),
        })
    })
    .await
    else {
        return;
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/select-context")
                .header("content-type", "application/json")
                // Pas d'en-tête Authorization → 401
                .body(Body::from(
                    json!({"cabinet_id": Uuid::new_v4()}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

// ── Test 2c : body JSON invalide (cabinet_id manquant) → 422 ─────────────────

#[tokio::test]
async fn select_context_invalid_body_returns_422() {
    let Some(state) = (async {
        let url = std::env::var("APP_DATABASE_URL").ok()?;
        let pool = sqlx::PgPool::connect(&url).await.ok()?;
        Some(AppState {
            db: pool,
            jwt_secret: JWT_SECRET.to_string(),
            mailer: Arc::new(StubMailer),
        })
    })
    .await
    else {
        return;
    };

    // Génère un JWT pro valide mais envoie un body sans `cabinet_id`.
    let user_id = Uuid::new_v4();
    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/select-context")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .body(Body::from(r#"{}"#))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::UNPROCESSABLE_ENTITY);
}

// ── Test 4 : JWT patient → 403 ───────────────────────────────────────────────
// ProClaims extractor : kind != "pro" → AppError::Forbidden.
// select-context est pro-only ; un patient ne doit pas pouvoir l'appeler.

#[tokio::test]
async fn select_context_patient_jwt_returns_403() {
    let Some(state) = (async {
        let url = std::env::var("APP_DATABASE_URL").ok()?;
        let pool = sqlx::PgPool::connect(&url).await.ok()?;
        Some(AppState {
            db: pool,
            jwt_secret: JWT_SECRET.to_string(),
            mailer: Arc::new(StubMailer),
        })
    })
    .await
    else {
        return;
    };

    // JWT patient valide (kind = "patient"), NON pro.
    let user_id = Uuid::new_v4();
    let exp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let patient_token = jsonwebtoken::encode(
        &jsonwebtoken::Header::default(),
        &serde_json::json!({"sub": user_id, "kind": "patient", "account_id": user_id, "exp": exp}),
        &jsonwebtoken::EncodingKey::from_secret(JWT_SECRET.as_bytes()),
    )
    .unwrap();

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/select-context")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", patient_token))
                .body(Body::from(
                    serde_json::json!({"cabinet_id": Uuid::new_v4()}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn select_context_secretariat_from_other_cabinet_returns_403() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let cabinet_a = Uuid::new_v4();
    let cabinet_b = Uuid::new_v4();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'pro')",
    )
    .bind(user_id)
    .bind(format!("sc-cross+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    for (cid, name) in [(cabinet_a, "Cabinet A"), (cabinet_b, "Cabinet B")] {
        sqlx::query(
            "INSERT INTO cabinet (id, raison_sociale, specialite) VALUES ($1, $2, 'dentiste')",
        )
        .bind(cid)
        .bind(name)
        .execute(&db)
        .await
        .unwrap();
    }

    // user membre du cabinet A seulement.
    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) VALUES ($1, $2, 'admin', true)",
    )
    .bind(cabinet_a)
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    // secretariat dans le cabinet B (pas cabinet A).
    let secretariat_b = Uuid::new_v4();
    sqlx::query("INSERT INTO secretariat (id, cabinet_id, name) VALUES ($1, $2, 'Sec B')")
        .bind(secretariat_b)
        .bind(cabinet_b)
        .execute(&db)
        .await
        .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: JWT_SECRET.to_string(),
        mailer: Arc::new(StubMailer),
    };

    let response = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/select-context")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", make_pro_jwt(user_id)))
                .body(Body::from(
                    json!({"cabinet_id": cabinet_a, "secretariat_id": secretariat_b}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    assert!(
        response.headers().get("set-cookie").is_none(),
        "pas de cookie nubia_jwt émis sur 403"
    );

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["error"], "no_active_membership");

    sqlx::query("DELETE FROM cabinet_membership WHERE user_id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
    sqlx::query("DELETE FROM secretariat WHERE id = $1")
        .bind(secretariat_b)
        .execute(&db)
        .await
        .ok();
    for cid in [cabinet_a, cabinet_b] {
        sqlx::query("DELETE FROM cabinet WHERE id = $1")
            .bind(cid)
            .execute(&db)
            .await
            .ok();
    }
    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}
