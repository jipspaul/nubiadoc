import 'package:drift/drift.dart';

import 'executor/cache_executor.dart';

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

  factory NubiaCacheDb.production() =>
      NubiaCacheDb(openCacheExecutor('nubia_cache.db'));

  factory NubiaCacheDb.inMemory() => NubiaCacheDb(inMemoryExecutor());

  @override
  int get schemaVersion => 1;
}
