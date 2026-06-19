class ApiConstants {
  ApiConstants._();

  // Overridden via --dart-define=API_BASE_URL=...
  static const String baseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'https://api.nubia.health/v1');

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Headers
  static const String contentType = 'application/json';
  static const String acceptLanguage = 'fr-FR';
}
