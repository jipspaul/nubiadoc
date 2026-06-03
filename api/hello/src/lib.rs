//! Minimal greeting library, PoC for the ci-rust stack.

use axum::{routing::get, Json, Router};
use serde_json::{json, Value};

/// Returns the Axum router for the API.
pub fn router() -> Router {
    Router::new().route("/health", get(health))
}

async fn health() -> Json<Value> {
    Json(json!({"status": "ok"}))
}

/// Returns the application version string.
///
/// This value MUST match the `version` key in `app_metadata` (see #20).
pub fn app_version() -> &'static str {
    "0.1.0"
}

/// Returns a greeting for the given name.
///
/// Used by the rust-ci proof-of-concept.
pub fn greet(name: &str) -> String {
    format!("Hello, {name}!")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_version_is_semver() {
        assert_eq!(app_version(), "0.1.0");
    }

    #[test]
    fn greet_world() {
        assert_eq!(greet("world"), "Hello, world!");
    }

    #[test]
    fn greet_empty() {
        assert_eq!(greet(""), "Hello, !");
    }
}
