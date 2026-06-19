// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'nubia_cache_db.dart';

// ignore_for_file: type=lint
class $AppointmentsCacheTable extends AppointmentsCache
    with TableInfo<$AppointmentsCacheTable, AppointmentsCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppointmentsCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, payload, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'appointments_cache';
  @override
  VerificationContext validateIntegrity(
      Insertable<AppointmentsCacheData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AppointmentsCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppointmentsCacheData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $AppointmentsCacheTable createAlias(String alias) {
    return $AppointmentsCacheTable(attachedDatabase, alias);
  }
}

class AppointmentsCacheData extends DataClass
    implements Insertable<AppointmentsCacheData> {
  final String id;
  final String payload;
  final DateTime updatedAt;
  const AppointmentsCacheData(
      {required this.id, required this.payload, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['payload'] = Variable<String>(payload);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  AppointmentsCacheCompanion toCompanion(bool nullToAbsent) {
    return AppointmentsCacheCompanion(
      id: Value(id),
      payload: Value(payload),
      updatedAt: Value(updatedAt),
    );
  }

  factory AppointmentsCacheData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppointmentsCacheData(
      id: serializer.fromJson<String>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'payload': serializer.toJson<String>(payload),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  AppointmentsCacheData copyWith(
          {String? id, String? payload, DateTime? updatedAt}) =>
      AppointmentsCacheData(
        id: id ?? this.id,
        payload: payload ?? this.payload,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  AppointmentsCacheData copyWithCompanion(AppointmentsCacheCompanion data) {
    return AppointmentsCacheData(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppointmentsCacheData(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, payload, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppointmentsCacheData &&
          other.id == this.id &&
          other.payload == this.payload &&
          other.updatedAt == this.updatedAt);
}

class AppointmentsCacheCompanion
    extends UpdateCompanion<AppointmentsCacheData> {
  final Value<String> id;
  final Value<String> payload;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const AppointmentsCacheCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppointmentsCacheCompanion.insert({
    required String id,
    required String payload,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        payload = Value(payload),
        updatedAt = Value(updatedAt);
  static Insertable<AppointmentsCacheData> custom({
    Expression<String>? id,
    Expression<String>? payload,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppointmentsCacheCompanion copyWith(
      {Value<String>? id,
      Value<String>? payload,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return AppointmentsCacheCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppointmentsCacheCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$NubiaCacheDb extends GeneratedDatabase {
  _$NubiaCacheDb(QueryExecutor e) : super(e);
  $NubiaCacheDbManager get managers => $NubiaCacheDbManager(this);
  late final $AppointmentsCacheTable appointmentsCache =
      $AppointmentsCacheTable(this);
  late final Index idxAcUpdatedAt = Index('idx_ac_updated_at',
      'CREATE INDEX idx_ac_updated_at ON appointments_cache (updated_at)');
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [appointmentsCache, idxAcUpdatedAt];
}

typedef $$AppointmentsCacheTableCreateCompanionBuilder
    = AppointmentsCacheCompanion Function({
  required String id,
  required String payload,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$AppointmentsCacheTableUpdateCompanionBuilder
    = AppointmentsCacheCompanion Function({
  Value<String> id,
  Value<String> payload,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$AppointmentsCacheTableFilterComposer
    extends Composer<_$NubiaCacheDb, $AppointmentsCacheTable> {
  $$AppointmentsCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$AppointmentsCacheTableOrderingComposer
    extends Composer<_$NubiaCacheDb, $AppointmentsCacheTable> {
  $$AppointmentsCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$AppointmentsCacheTableAnnotationComposer
    extends Composer<_$NubiaCacheDb, $AppointmentsCacheTable> {
  $$AppointmentsCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$AppointmentsCacheTableTableManager extends RootTableManager<
    _$NubiaCacheDb,
    $AppointmentsCacheTable,
    AppointmentsCacheData,
    $$AppointmentsCacheTableFilterComposer,
    $$AppointmentsCacheTableOrderingComposer,
    $$AppointmentsCacheTableAnnotationComposer,
    $$AppointmentsCacheTableCreateCompanionBuilder,
    $$AppointmentsCacheTableUpdateCompanionBuilder,
    (
      AppointmentsCacheData,
      BaseReferences<_$NubiaCacheDb, $AppointmentsCacheTable,
          AppointmentsCacheData>
    ),
    AppointmentsCacheData,
    PrefetchHooks Function()> {
  $$AppointmentsCacheTableTableManager(
      _$NubiaCacheDb db, $AppointmentsCacheTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppointmentsCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppointmentsCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppointmentsCacheTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AppointmentsCacheCompanion(
            id: id,
            payload: payload,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String payload,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AppointmentsCacheCompanion.insert(
            id: id,
            payload: payload,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AppointmentsCacheTableProcessedTableManager = ProcessedTableManager<
    _$NubiaCacheDb,
    $AppointmentsCacheTable,
    AppointmentsCacheData,
    $$AppointmentsCacheTableFilterComposer,
    $$AppointmentsCacheTableOrderingComposer,
    $$AppointmentsCacheTableAnnotationComposer,
    $$AppointmentsCacheTableCreateCompanionBuilder,
    $$AppointmentsCacheTableUpdateCompanionBuilder,
    (
      AppointmentsCacheData,
      BaseReferences<_$NubiaCacheDb, $AppointmentsCacheTable,
          AppointmentsCacheData>
    ),
    AppointmentsCacheData,
    PrefetchHooks Function()>;

class $NubiaCacheDbManager {
  final _$NubiaCacheDb _db;
  $NubiaCacheDbManager(this._db);
  $$AppointmentsCacheTableTableManager get appointmentsCache =>
      $$AppointmentsCacheTableTableManager(_db, _db.appointmentsCache);
}
