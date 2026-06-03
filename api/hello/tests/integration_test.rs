use hello::greet;

#[test]
fn integration_greet() {
    assert_eq!(greet("CI"), "Hello, CI!");
}
