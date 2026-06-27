import 'package:drift/drift.dart';

import '../executor/cache_executor.dart';

/// Drift database used as the offline cache.
///
/// Tables are created via raw SQL in [migration]; no code generation is
/// required because we rely solely on [customStatement] / [customSelect].
class NubiaDatabase extends GeneratedDatabase {
  NubiaDatabase(super.e);

  factory NubiaDatabase.production() =>
      NubiaDatabase(openCacheExecutor('nubia_cache.db'));

  factory NubiaDatabase.inMemory() => NubiaDatabase(inMemoryExecutor());

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => _createTables(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await customStatement('DROP TABLE IF EXISTS cached_appointments');
            await customStatement('DROP TABLE IF EXISTS cache_timestamps');
            await _createTables();
          }
        },
      );

  Future<void> _createTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS cached_appointments (
        id        TEXT NOT NULL,
        json      TEXT NOT NULL,
        list_key  TEXT NOT NULL,
        cached_at INTEGER NOT NULL,
        PRIMARY KEY (id, list_key)
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS cache_timestamps (
        cache_key TEXT NOT NULL PRIMARY KEY,
        cached_at INTEGER NOT NULL
      )
    ''');
  }
}
