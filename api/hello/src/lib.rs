//! Minimal greeting library, PoC for the ci-rust stack.

/// Returns a greeting for the given name.
pub fn greet(name: &str) -> String {
    format!("Hello, {name}!")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greet_world() {
        assert_eq!(greet("world"), "Hello, world!");
    }

    #[test]
    fn greet_empty() {
        assert_eq!(greet(""), "Hello, !");
    }
}
