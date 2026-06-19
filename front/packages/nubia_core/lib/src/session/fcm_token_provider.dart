/// Abstraction for obtaining the device FCM push token.
///
/// Inject a mock in tests; in production use a Firebase-backed implementation
/// or [NoopFcmTokenProvider] before Firebase is integrated.
abstract class FcmTokenProvider {
  /// Returns the current FCM token, or null if unavailable / not yet fetched.
  Future<String?> getToken();

  /// Target platform string: `"ios"`, `"android"`, or `"web"`.
  String get platform;
}

/// No-op implementation — always returns null (no FCM registration).
/// Used until a real Firebase-backed provider is wired in production.
class NoopFcmTokenProvider implements FcmTokenProvider {
  const NoopFcmTokenProvider();

  @override
  Future<String?> getToken() async => null;

  @override
  String get platform => 'android';
}
