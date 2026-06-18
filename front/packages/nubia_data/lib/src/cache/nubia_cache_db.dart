import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_sqflite/drift_sqflite.dart';

/// Drift database for the appointments offline cache.
///
/// Uses raw SQL (no code generation) so the schema can be committed without
/// a build_runner step in CI.  Table: appointments_cache (id TEXT PK,
/// payload TEXT, updated_at INTEGER epoch-ms) + index idx_ac_updated_at.
class NubiaCacheDb extends GeneratedDatabase {
  NubiaCacheDb(super.e);

  factory NubiaCacheDb.production() => NubiaCacheDb(
        SqfliteQueryExecutor.inDatabaseFolder(
          path: 'nubia_cache.db',
          logStatements: false,
        ),
      );

  factory NubiaCacheDb.inMemory() => NubiaCacheDb(NativeDatabase.memory());

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => _createSchema(),
        onUpgrade: (m, from, to) async {},
      );

  Future<void> _createSchema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS appointments_cache (
        id         TEXT NOT NULL PRIMARY KEY,
        payload    TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS idx_ac_updated_at
        ON appointments_cache(updated_at)
    ''');
  }
}
