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
        pool,
        mailer: Arc::new(StubMailer),
    };

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    axum::serve(listener, app(state)).await.unwrap();
}
