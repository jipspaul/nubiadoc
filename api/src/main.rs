use std::sync::Arc;

use nubia_api::{app, AppState, StubMailer};
use sqlx::PgPool;

#[tokio::main]
async fn main() {
    let pool =
        PgPool::connect(&std::env::var("APP_DATABASE_URL").expect("APP_DATABASE_URL must be set"))
            .await
            .expect("failed to connect to database");

    let state = AppState {
        db: pool,
        jwt_secret: std::env::var("JWT_SECRET").unwrap_or_default(),
        mailer: Arc::new(StubMailer),
    };

    let port: u16 = std::env::var("APP_PORT")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(3000);
    let bind = format!("0.0.0.0:{port}");
    let listener = tokio::net::TcpListener::bind(&bind).await.unwrap();
    println!("nubia-api listening on {bind}");
    axum::serve(listener, app(state)).await.unwrap();
}
