class ApiConstants {
  ApiConstants._();

  // Overridden via --dart-define=API_BASE_URL=...
  static const String baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'https://api.nubia.health/v1');

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Headers
  static const String contentType = 'application/json';
  static const String acceptLanguage = 'fr-FR';

  // Carte : clé MapTiler (tuiles raster). Surchargeable via
  // --dart-define=MAPTILER_KEY=...
  static const String mapTilerKey =
      String.fromEnvironment('MAPTILER_KEY', defaultValue: 'cnArmFSMqoCPGYrRKgeQ');

  /// URL template des tuiles raster MapTiler (streets), prête pour flutter_map.
  static String mapTilerTilesUrl() =>
      'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$mapTilerKey';
}
