// Exécuteur Drift natif (VM/mobile/desktop) : sqlite3 via sqflite (prod) ou
// NativeDatabase mémoire (tests). N'est JAMAIS importé par le build web.
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_sqflite/drift_sqflite.dart';

QueryExecutor openCacheExecutor(String fileName) =>
    SqfliteQueryExecutor.inDatabaseFolder(path: fileName, logStatements: false);

QueryExecutor inMemoryExecutor() => NativeDatabase.memory();
