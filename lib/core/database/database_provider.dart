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

    final path = databasePath ?? p.join(
      await getDatabasesPath(),
      databaseFileName,
    );

    final opened = await openDatabase(
      path,
      version: DatabaseSchema.version,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA busy_timeout = 5000');
      },
      onCreate: (db, version) async {
        final batch = db.batch();
        for (final statement in DatabaseSchema.createStatements) {
          batch.execute(statement);
        }
        await batch.commit(noResult: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Add a new, explicit migration block for every future schema version.
        // Never drop user data as a generic upgrade strategy.
        if (oldVersion < 1) {
          final batch = db.batch();
          for (final statement in DatabaseSchema.createStatements) {
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
    if (current != null && current.isOpen) {
      await current.close();
    }
  }
}
