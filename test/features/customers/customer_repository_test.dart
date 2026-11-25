import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:advanced_assistant/core/auth/auth_service.dart';
import 'package:advanced_assistant/core/auth/authorization_policy.dart';
import 'package:advanced_assistant/core/auth/authorization_service.dart';
import 'package:advanced_assistant/core/auth/password_hasher.dart';
import 'package:advanced_assistant/core/auth/session_secret_store.dart';
import 'package:advanced_assistant/core/database/database_provider.dart';
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

  test('manager can create, search, update and archive customers', () async {
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
    final repository = CustomerRepository(
      db, AuthorizationService(db, auth),
    );

    final created = await repository.create(
      const CustomerDraft(name: '  أحمد محمد  ', phone: ' 777 '),
    );
    expect(created.name, 'أحمد محمد');
    expect(created.phone, '777');
    expect(created.currentBalance, '0');

    final found = await repository.search('أحمد');
    expect(found, hasLength(1));
    final updated = await repository.update(
      created.id,
      const CustomerDraft(name: 'أحمد علي', address: 'صنعاء'),
    );
    expect(updated.address, 'صنعاء');
    expect(updated.currentBalance, '0');

    await repository.archive(created.id);
    expect(await repository.search('أحمد'), isEmpty);
    expect(await repository.search('أحمد', includeArchived: true), hasLength(1));
    await provider.close();
  });

  test('customer operations require a session and never edit balance', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(
      db,
      _TestSecretStore(),
      passwordHasher: PasswordHasher(iterations: 10000),
    );
    await auth.createInitialManager(
      username: 'manager',
      displayName: 'المدير',
      password: 'Strong-password-123',
    );
    final repository = CustomerRepository(db, AuthorizationService(db, auth));
    await expectLater(
      repository.create(const CustomerDraft(name: 'عميل')),
      throwsA(isA<AuthorizationException>()),
    );
    await auth.login(username: 'manager', password: 'Strong-password-123');
    final customer = await repository.create(
      const CustomerDraft(name: 'عميل',),
    );
    await db.update(
      'customers',
      {'current_balance': '-125.50'},
      where: 'id = ?',
      whereArgs: [customer.id],
    );
    final updated = await repository.update(
      customer.id,
      const CustomerDraft(name: 'عميل معدل'),
    );
    expect(updated.currentBalance, '-125.50');
    await provider.close();
  });
}
