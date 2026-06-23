// Sélecteur d'exécuteur Drift par plateforme (compile-time conditional import).
//
//   * natif (VM/mobile/desktop) : sqlite3 via FFI / sqflite  -> cache_executor_native.dart
//   * web (Flutter web)         : sqlite3 WASM               -> cache_executor_web.dart
//   * autre                     : stub qui throw             -> cache_executor_stub.dart
//
// Sépare l'import de `dart:ffi` (drift/native, drift_sqflite) du graphe web :
// sans ça, dart2js échoue (« dart:ffi is not available on this platform »).
export 'cache_executor_stub.dart'
    if (dart.library.ffi) 'cache_executor_native.dart'
    if (dart.library.html) 'cache_executor_web.dart';
