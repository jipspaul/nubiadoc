class ApiConstants {
  ApiConstants._();

  // Overridden via --dart-define=API_BASE_URL=...
  // Défaut = backend de prod déployé (doc.nubia-link.com) pour que les builds
  // mobiles sans dart-define tapent quand même au bon endroit.
  static const String baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'https://api.doc.nubia-link.com/v1');

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Headers
  static const String contentType = 'application/json';
  static const String acceptLanguage = 'fr-FR';

  // Carte : clé MapTiler (tuiles raster). Surchargeable via
  // --dart-define=MAPTILER_KEY=...
  static const String mapTilerKey = String.fromEnvironment('MAPTILER_KEY',
      defaultValue: 'cnArmFSMqoCPGYrRKgeQ');

  /// URL template des tuiles raster MapTiler (streets), prête pour flutter_map.
  /// [dark] bascule sur le style sombre MapTiler (cohérence avec le thème
  /// sombre de l'app : sans ça la carte reste claire même en dark mode).
  static String mapTilerTilesUrl({bool dark = false}) => dark
      ? 'https://api.maptiler.com/maps/streets-v2-dark/{z}/{x}/{y}.png?key=$mapTilerKey'
      : 'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$mapTilerKey';
}
