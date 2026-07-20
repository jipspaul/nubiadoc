//! Test d'intégration ciblé : POST /v1/cabinet/members avec un token patient
//! valide doit renvoyer 403 (pas 401) — #3806.
//!
//! Fichier dédié plutôt qu'ajout dans cabinet_members.rs (déjà 881 lignes,
//! au-dessus du plafond CLAUDE.md).

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

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok()
}

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL")
        .unwrap_or_else(|_| "postgres://nubia_app@localhost:5432/nubia".into());
    PgPool::connect(&url).await.unwrap()
}

/// Régression #3806 : `ProAdminOrManagerClaims` décodait la struct pro
/// complète (cabinet_id/role obligatoires, absents d'un token patient) AVANT
/// de tester `kind` -> échec serde -> 401, indistinguable d'un token
/// corrompu/expiré côté front (risque de logout/boucle de login).
#[tokio::test]
async fn post_members_patient_token_returns_403_not_401() {
    if !db_available() {
        return;
    }
    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret".into(),
        mailer: Arc::new(StubMailer),
    };

    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + 3600;
    let patient_token = encode(
        &Header::default(),
        &json!({"sub": Uuid::new_v4(), "kind": "patient", "account_id": Uuid::new_v4(), "exp": exp}),
        &EncodingKey::from_secret(b"test-secret"),
    )
    .unwrap();

    let body = json!({
        "email": format!("wrongkind_{}@test.local", Uuid::new_v4()),
        "role": "secretary",
        "first_name": "Bob",
        "last_name": "Dupont"
    });

    let resp = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/cabinet/members")
                .header("content-type", "application/json")
                .header("Authorization", format!("Bearer {}", patient_token))
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(
        resp.status(),
        StatusCode::FORBIDDEN,
        "un token patient VALIDE (mauvais kind) doit renvoyer 403, pas 401"
    );
}
