// Fallback pour les plateformes sans ffi ni web (jamais atteint en pratique) :
// satisfait l'analyseur pour l'import conditionnel de cache_executor.dart.
import 'package:drift/drift.dart';

QueryExecutor openCacheExecutor(String fileName) =>
    throw UnsupportedError('Aucun exécuteur de base disponible sur cette plateforme');

QueryExecutor inMemoryExecutor() =>
    throw UnsupportedError('Aucun exécuteur de base disponible sur cette plateforme');
