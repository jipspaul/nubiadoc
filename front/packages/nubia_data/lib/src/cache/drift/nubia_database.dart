import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_sqflite/drift_sqflite.dart';

/// Drift database used as the offline cache.
///
/// Tables are created via raw SQL in [migration]; no code generation is
/// required because we rely solely on [customStatement] / [customSelect].
class NubiaDatabase extends GeneratedDatabase {
  NubiaDatabase(super.e);

  factory NubiaDatabase.production() =>
      NubiaDatabase(SqfliteQueryExecutor.inDatabaseFolder(
        path: 'nubia_cache.db',
        logStatements: false,
      ));

  factory NubiaDatabase.inMemory() => NubiaDatabase(NativeDatabase.memory());

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => _createTables(),
        onUpgrade: (m, from, to) async {},
      );

  Future<void> _createTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS cached_appointments (
        id   TEXT NOT NULL PRIMARY KEY,
        json TEXT NOT NULL,
        list_key    TEXT,
        cached_at   INTEGER NOT NULL
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
