import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_sqflite/drift_sqflite.dart';

part 'nubia_cache_db.g.dart';

@TableIndex(name: 'idx_ac_updated_at', columns: {#updatedAt})
class AppointmentsCache extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [AppointmentsCache])
class NubiaCacheDb extends _$NubiaCacheDb {
  NubiaCacheDb(super.e);

  factory NubiaCacheDb.production() => NubiaCacheDb(
        SqfliteQueryExecutor.inDatabaseFolder(
          path: 'nubia_cache.db',
          logStatements: false,
        ),
      );

  factory NubiaCacheDb.inMemory() => NubiaCacheDb(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
