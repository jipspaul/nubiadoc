// Exécuteur Drift web : sqlite3 compilé en WASM. Ouverture PARESSEUSE
// (LazyDatabase) -> la base n'est ouverte qu'au premier accès au cache, donc
// le démarrage de l'app (login, dashboard) n'est jamais bloqué par le WASM.
//
// Assets attendus à la racine web : `sqlite3.wasm` (obligatoire) et
// `drift_worker.js` (optionnel — si absent, Drift bascule en thread principal).
import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

QueryExecutor openCacheExecutor(String fileName) => _openWasm(fileName);

QueryExecutor inMemoryExecutor() => _openWasm('nubia_cache_mem.db');

LazyDatabase _openWasm(String fileName) => LazyDatabase(() async {
      final result = await WasmDatabase.open(
        databaseName: fileName.replaceAll('.db', ''),
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
      );
      return result.resolvedExecutor;
    });
