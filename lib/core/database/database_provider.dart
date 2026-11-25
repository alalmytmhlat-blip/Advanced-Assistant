import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'database_schema.dart';

/// Owns the single local SQLite connection used by repositories.
class DatabaseProvider {
  DatabaseProvider({this.databasePath});
  static const String databaseFileName = 'advanced_assistant.db';
  final String? databasePath;
  Database? _database;

  Future<Database> get database async {
    final existing = _database;
    if (existing != null && existing.isOpen) return existing;
    final path = databasePath ?? p.join(await getDatabasesPath(), databaseFileName);
    final opened = await openDatabase(
      path,
      version: DatabaseSchema.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA busy_timeout = 5000');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final statement in [
          ...DatabaseSchema.createStatements,
          ...DatabaseSchema.migrationV2Statements,
          ...DatabaseSchema.migrationV3Statements,
        ]) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Each missing migration is applied exactly once; existing data stays.
        if (oldVersion < 1) {
          final batch = db.batch();
          for (final statement in DatabaseSchema.createStatements) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        }
        if (oldVersion < 2) {
          final batch = db.batch();
          for (final statement in DatabaseSchema.migrationV2Statements) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        }
        if (oldVersion < 3) {
          final batch = db.batch();
          for (final statement in DatabaseSchema.migrationV3Statements) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        }
      },
    );
    _database = opened;
    return opened;
  }

  Future<void> close() async {
    final current = _database;
    _database = null;
    if (current != null && current.isOpen) await current.close();
  }
}
