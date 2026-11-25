import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:advanced_assistant/core/auth/auth_service.dart';
import 'package:advanced_assistant/core/auth/authorization_policy.dart';
import 'package:advanced_assistant/core/auth/authorization_service.dart';
import 'package:advanced_assistant/core/auth/password_hasher.dart';
import 'package:advanced_assistant/core/auth/session_secret_store.dart';
import 'package:advanced_assistant/core/database/database_provider.dart';
import 'package:advanced_assistant/features/customers/data/customer_balance_repository.dart';
import 'package:advanced_assistant/features/customers/data/balance_change_model.dart';
import 'package:advanced_assistant/features/customers/data/customer_model.dart';
import 'package:advanced_assistant/features/customers/data/customer_repository.dart';

class _TestSecretStore implements SessionSecretStore {
  String? value;
  @override
  Future<void> delete() async => value = null;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('updates positive and negative balances exactly with audit history', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(
      db, _TestSecretStore(), passwordHasher: PasswordHasher(iterations: 10000),
    );
    await auth.createInitialManager(
      username: 'manager',
      displayName: 'المدير',
      password: 'Strong-password-123',
    );
    await auth.login(username: 'manager', password: 'Strong-password-123');
    final authz = AuthorizationService(db, auth);
    final customers = CustomerRepository(db, authz);
    final balances = CustomerBalanceRepository(db, authz);
    final customer = await customers.create(const CustomerDraft(name: 'عميل أرصدة'));

    final first = await balances.updateBalance(
      customerId: customer.id,
      newBalance: '-1250.7500',
      reason: 'رصيد افتتاحي مدين',
    );
    expect(first.previousBalance, '0');
    expect(first.newBalance, '-1250.75');
    expect(await balances.readBalance(customer.id), '-1250.75');

    final second = await balances.updateBalance(
      customerId: customer.id,
      newBalance: '+300.25',
      reason: 'تصحيح الرصيد',
    );
    expect(second.previousBalance, '-1250.75');
    expect(second.newBalance, '300.25');
    expect(await balances.readBalance(customer.id), '300.25');

    final history = await balances.history(customer.id);
    expect(history, hasLength(2));
    expect(history.first.newBalance, '300.25');
    final audit = await db.query(
      'audit_events',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: ['customer_balance', customer.id],
    );
    expect(audit, hasLength(2));
    expect(audit.first['operation_id'], isNotNull);
    await provider.close();
  });

  test('balance changes require an authenticated authorized session', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final store = _TestSecretStore();
    final auth = AuthService(
      db, store, passwordHasher: PasswordHasher(iterations: 10000),
    );
    await auth.createInitialManager(
      username: 'manager',
      displayName: 'المدير',
      password: 'Strong-password-123',
    );
    await auth.login(username: 'manager', password: 'Strong-password-123');
    final authz = AuthorizationService(db, auth);
    final customer = await CustomerRepository(db, authz).create(
      const CustomerDraft(name: 'عميل محمي'),
    );
    await auth.logout();

    final balances = CustomerBalanceRepository(db, authz);
    await expectLater(
      balances.updateBalance(
        customerId: customer.id,
        newBalance: '-10',
        reason: 'اختبار',
      ),
      throwsA(isA<AuthorizationException>()),
    );
    await provider.close();
  });

  test('invalid decimal and empty reason are rejected without mutation', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(
      db, _TestSecretStore(), passwordHasher: PasswordHasher(iterations: 10000),
    );
    await auth.createInitialManager(
      username: 'manager',
      displayName: 'المدير',
      password: 'Strong-password-123',
    );
    await auth.login(username: 'manager', password: 'Strong-password-123');
    final authz = AuthorizationService(db, auth);
    final customer = await CustomerRepository(db, authz).create(
      const CustomerDraft(name: 'عميل تحقق'),
    );
    final balances = CustomerBalanceRepository(db, authz);

    await expectLater(
      balances.updateBalance(customerId: customer.id, newBalance: '1e3', reason: 'سبب'),
      throwsA(isA<BalanceValidationException>()),
    );
    await expectLater(
      balances.updateBalance(customerId: customer.id, newBalance: '25', reason: '  '),
      throwsA(isA<BalanceValidationException>()),
    );
    expect(await balances.readBalance(customer.id), '0');
    expect(await balances.history(customer.id), isEmpty);
    await provider.close();
  });
}
