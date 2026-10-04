//! Tests d'intégration : rotation concurrente du même refresh token (issue #7883).
//! Deux onglets du même compte qui partagent le même localStorage peuvent présenter
//! le même refresh token en même temps. Valide : un seul gagnant, et la chaîne de
//! sessions de l'utilisateur n'est pas détruite par les perdants.

use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use serde_json::json;
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use uuid::Uuid;

use nubia_api::{app, AppState, StubMailer};

fn db_available() -> bool {
    std::env::var("APP_DATABASE_URL").is_ok() && std::env::var("DATABASE_URL").is_ok()
}

async fn owner_pool() -> PgPool {
    let url = std::env::var("DATABASE_URL").unwrap();
    PgPool::connect(&url).await.unwrap()
}

async fn app_pool() -> PgPool {
    let url = std::env::var("APP_DATABASE_URL").unwrap();
    PgPool::connect(&url).await.unwrap()
}

#[tokio::test]
async fn concurrent_refresh_of_same_token_has_one_winner_and_preserves_other_sessions() {
    if !db_available() {
        return;
    }
    let db = owner_pool().await;
    let user_id = Uuid::new_v4();
    let raw_token = Uuid::new_v4().to_string();

    sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, 'hash', 'patient')",
    )
    .bind(user_id)
    .bind(format!("refresh-concurrency+{}@nubia.test", user_id))
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        "INSERT INTO patient_account (app_user_id, first_name, last_name) VALUES ($1, '', '')",
    )
    .bind(user_id)
    .execute(&db)
    .await
    .unwrap();

    sqlx::query(
        r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
           VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
    )
    .bind(user_id)
    .bind(&raw_token)
    .execute(&db)
    .await
    .unwrap();

    // Une deuxième session active (autre device) : NE DOIT PAS être cassée par
    // la course entre les deux "onglets" sur raw_token.
    let other_session_token = Uuid::new_v4().to_string();
    sqlx::query(
        r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
           VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
    )
    .bind(user_id)
    .bind(&other_session_token)
    .execute(&db)
    .await
    .unwrap();

    let state = AppState {
        db: app_pool().await,
        jwt_secret: "test-secret-refresh-concurrency".into(),
        mailer: Arc::new(StubMailer),
    };

    // 8 requêtes concurrentes avec EXACTEMENT le même refresh_token (2 onglets
    // qui partagent le même localStorage + retries réseau).
    let mut handles = Vec::new();
    for _ in 0..8 {
        let state = state.clone();
        let raw_token = raw_token.clone();
        handles.push(tokio::spawn(async move {
            app(state)
                .oneshot(
                    Request::builder()
                        .method("POST")
                        .uri("/v1/auth/refresh")
                        .header("Content-Type", "application/json")
                        .body(Body::from(json!({"refresh_token": raw_token}).to_string()))
                        .unwrap(),
                )
                .await
                .unwrap()
        }));
    }

    let mut ok_count = 0;
    let mut unauthorized_count = 0;
    for h in handles {
        let response = h.await.unwrap();
        match response.status() {
            StatusCode::OK => ok_count += 1,
            StatusCode::UNAUTHORIZED => unauthorized_count += 1,
            other => panic!("statut inattendu : {other}"),
        }
    }

    assert_eq!(
        ok_count, 1,
        "rotation non-atomique : {ok_count} gagnants au lieu d'1 seul"
    );
    assert_eq!(unauthorized_count, 7);

    // La session indépendante (other_session_token) doit toujours être valide :
    // la course sur raw_token ne doit PAS avoir déclenché une révocation en chaîne.
    let other_session_check = app(state)
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/v1/auth/refresh")
                .header("Content-Type", "application/json")
                .body(Body::from(
                    json!({"refresh_token": other_session_token}).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        other_session_check.status(),
        StatusCode::OK,
        "la course sur raw_token a cassé une AUTRE session valide (déconnexion générale)"
    );

    sqlx::query("DELETE FROM app_user WHERE id = $1")
        .bind(user_id)
        .execute(&db)
        .await
        .ok();
}
