//! Minimal greeting library, PoC for the ci-rust stack.

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
