use axum::{
    body::Body,
    http::{Request, StatusCode},
};
use tower::ServiceExt;

#[sqlx::test]
async fn health_db_returns_200_ok(pool: sqlx::PgPool) {
    use std::sync::Arc;
    let state = nubia_api::AppState {
        db: pool,
        jwt_secret: String::new(),
        mailer: Arc::new(nubia_api::StubMailer),
    };
    let app = nubia_api::app(state);
    let response = app
        .oneshot(
            Request::builder()
                .uri("/v1/health/db")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v["ok"], serde_json::json!(true));
    assert!(v["ms"].is_number());
}

#[tokio::test]
async fn health_returns_200_ok() {
    let app = nubia_api::router();
    let response = app
        .oneshot(
            Request::builder()
                .uri("/v1/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);

    let body = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let v: serde_json::Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(v, serde_json::json!({"status": "ok"}));
}
