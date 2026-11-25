import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:advanced_assistant/core/database/database_provider.dart';

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
    ]));

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    final indexNames =
        indexes.map((row) => row['name']).whereType<String>().toSet();
    expect(indexNames, contains('idx_followups_due_status'));

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

    expect(
      () => db.insert('customer_notes', {
        'id': 'note-1',
        'customer_id': 'missing-customer',
        'body': 'يجب رفض السجل اليتيم',
        'created_at': '2026-01-01T00:00:00Z',
      }),
      throwsA(isA<DatabaseException>()),
    );

    await provider.close();
  });
}
