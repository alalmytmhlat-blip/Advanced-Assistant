import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:advanced_assistant/core/database/database_provider.dart';
import 'package:advanced_assistant/core/database/database_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('creates the required core tables and indexes', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;

    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tables = rows.map((row) => row['name']).whereType<String>().toSet();
    expect(tables, containsAll([
      'app_users',
      'customers',
      'customer_notes',
      'contact_events',
      'customer_balance_changes',
      'inventory_categories',
      'inventory_items',
      'followups',
      'audit_events',
      'app_settings',
      'assistant_conversations',
      'assistant_messages',
      'user_permissions',
      'user_customer_scopes',
      'auth_sessions',
      'auth_login_attempts',
    ]));

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    final indexNames =
        indexes.map((row) => row['name']).whereType<String>().toSet();
    expect(indexNames, contains('idx_followups_due_status'));
    expect(indexNames, contains('idx_auth_sessions_user'));
    await provider.close();
  });

  test('enforces foreign keys and preserves signed balances as text', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;

    await db.insert('customers', {
      'id': 'customer-1',
      'name': 'عميل اختبار',
      'current_balance': '-1250.75',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
    });
    final customer = await db.query(
      'customers',
      columns: ['current_balance'],
      where: 'id = ?',
      whereArgs: ['customer-1'],
    );
    expect(customer.single['current_balance'], '-1250.75');

    await expectLater(
      db.insert('customer_notes', {
        'id': 'note-1',
        'customer_id': 'missing-customer',
        'body': 'يجب رفض السجل اليتيم',
        'created_at': '2026-01-01T00:00:00Z',
      }),
      throwsA(isA<DatabaseException>()),
    );
    await provider.close();
  });

  for (final oldVersion in [1, 2]) {
    test('upgrades database V$oldVersion to V3 without losing records', () async {
      final directory = await Directory.systemTemp.createTemp('assistant-migration-');
      final path = p.join(directory.path, 'legacy.db');
      final legacy = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: oldVersion,
          onCreate: (db, version) async {
            final statements = <String>[
              ...DatabaseSchema.createStatements,
              if (oldVersion >= 2) ...DatabaseSchema.migrationV2Statements,
            ];
            final batch = db.batch();
            for (final statement in statements) {
              batch.execute(statement);
            }
            await batch.commit(noResult: true);
          },
        ),
      );
      await legacy.insert('app_users', {
        'id': 'legacy-manager',
        'username': 'legacy',
        'display_name': 'مدير قديم',
        'password_hash': 'legacy-hash',
        'role': 'manager',
        'is_active': 1,
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      });
      await legacy.insert('customers', {
        'id': 'legacy-customer',
        'name': 'عميل محفوظ',
        'current_balance': '-87.50',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      });
      if (oldVersion >= 2) {
        await legacy.insert('user_permissions', {
          'id': 'legacy-grant',
          'user_id': 'legacy-manager',
          'permission': 'customer.read',
          'created_at': '2025-01-01T00:00:00Z',
        });
        await legacy.insert('user_customer_scopes', {
          'user_id': 'legacy-manager',
          'customer_id': 'legacy-customer',
          'created_at': '2025-01-01T00:00:00Z',
        });
      }
      await legacy.close();

      final provider = DatabaseProvider(databasePath: path);
      final upgraded = await provider.database;
      final userCount = await upgraded.rawQuery(
        "SELECT COUNT(*) AS n FROM app_users WHERE id = 'legacy-manager'",
      );
      final customerRows = await upgraded.query(
        'customers',
        columns: ['current_balance'],
        where: 'id = ?',
        whereArgs: ['legacy-customer'],
      );
      final newTables = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('auth_sessions', 'auth_login_attempts')",
      );
      expect(userCount.single['n'], 1);
      expect(customerRows.single['current_balance'], '-87.50');
      expect(newTables, hasLength(2));
      expect(await upgraded.getVersion(), DatabaseSchema.version);
      if (oldVersion >= 2) {
        final grants = await upgraded.query(
          'user_permissions',
          where: 'id = ?',
          whereArgs: ['legacy-grant'],
        );
        final scopes = await upgraded.query(
          'user_customer_scopes',
          where: 'user_id = ? AND customer_id = ?',
          whereArgs: ['legacy-manager', 'legacy-customer'],
        );
        expect(grants.single['permission'], 'customer.read');
        expect(scopes, hasLength(1));
      }

      await provider.close();
      await directory.delete(recursive: true);
    });
  }
}
