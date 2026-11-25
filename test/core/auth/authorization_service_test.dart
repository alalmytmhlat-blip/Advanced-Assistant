import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:advanced_assistant/core/auth/app_permission.dart';
import 'package:advanced_assistant/core/auth/auth_service.dart';
import 'package:advanced_assistant/core/auth/authorization_policy.dart';
import 'package:advanced_assistant/core/auth/authorization_service.dart';
import 'package:advanced_assistant/core/auth/password_hasher.dart';
import 'package:advanced_assistant/core/auth/session_secret_store.dart';
import 'package:advanced_assistant/core/database/database_provider.dart';

class _MemorySecretStore implements SessionSecretStore {
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

  Future<({DatabaseProvider provider, AuthService auth, _MemorySecretStore store, String userId})>
      setup() async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final store = _MemorySecretStore();
    final auth = AuthService(
      db,
      store,
      passwordHasher: PasswordHasher(iterations: 10000),
    );
    final userId = await auth.createInitialManager(
      username: 'manager',
      displayName: 'المدير',
      password: 'Strong-password-123',
    );
    return (provider: provider, auth: auth, store: store, userId: userId);
  }

  test('authorization requires a valid authenticated session', () async {
    final state = await setup();
    final db = await state.provider.database;
    final authorization = AuthorizationService(db, state.auth);

    await expectLater(
      authorization.loadContext(),
      throwsA(isA<AuthorizationException>()),
    );

    await state.auth.login(
      username: 'manager',
      password: 'Strong-password-123',
    );
    expect((await authorization.loadContext()).userId, state.userId);
    await state.auth.logout();

    await expectLater(
      authorization.requirePermission(AppPermission.customerRead),
      throwsA(isA<AuthorizationException>()),
    );
    await state.provider.close();
  });

  test('revoked and inactive sessions cannot authorize operations', () async {
    final state = await setup();
    final db = await state.provider.database;
    final authorization = AuthorizationService(db, state.auth);

    await state.auth.login(
      username: 'manager',
      password: 'Strong-password-123',
    );
    await db.update(
      'auth_sessions',
      {'revoked_at': DateTime.now().toUtc().toIso8601String()},
    );
    await expectLater(
      authorization.loadContext(),
      throwsA(isA<AuthorizationException>()),
    );

    await state.auth.login(
      username: 'manager',
      password: 'Strong-password-123',
    );
    await db.update(
      'app_users',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [state.userId],
    );
    await expectLater(
      authorization.requirePermission(AppPermission.customerRead),
      throwsA(isA<AuthorizationException>()),
    );
    await state.provider.close();
  });

  test('customer access uses the authenticated user scope', () async {
    final state = await setup();
    final db = await state.provider.database;
    await db.update(
      'app_users',
      {'role': 'debt_collector'},
      where: 'id = ?',
      whereArgs: [state.userId],
    );
    await db.insert('customers', {
      'id': 'customer-allowed',
      'name': 'عميل',
      'current_balance': '0',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    await db.insert('user_permissions', {
      'id': 'grant-customer-read',
      'user_id': state.userId,
      'permission': AppPermission.customerRead,
      'created_at': '2026-01-01T00:00:00.000Z',
    });
    await db.insert('user_customer_scopes', {
      'user_id': state.userId,
      'customer_id': 'customer-allowed',
      'created_at': '2026-01-01T00:00:00.000Z',
    });

    await state.auth.login(
      username: 'manager',
      password: 'Strong-password-123',
    );
    final authorization = AuthorizationService(db, state.auth);
    await authorization.requireCustomerAccess('customer-allowed');
    await expectLater(
      authorization.requireCustomerAccess('customer-outside-scope'),
      throwsA(isA<AuthorizationException>()),
    );
    await state.provider.close();
  });
}
