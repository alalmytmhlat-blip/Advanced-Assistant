import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:advanced_assistant/core/auth/auth_service.dart';
import 'package:advanced_assistant/core/auth/password_hasher.dart';
import 'package:advanced_assistant/core/auth/session_secret_store.dart';
import 'package:advanced_assistant/core/database/database_provider.dart';

class MemorySecretStore implements SessionSecretStore {
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

  test('creates first manager once and authenticates a persisted session', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final store = MemorySecretStore();
    final auth = AuthService(db, store, passwordHasher: PasswordHasher(iterations: 10000));
    final id = await auth.createInitialManager(
      username: ' Owner ', displayName: 'المدير', password: 'Strong-password-123',
    );
    expect(await auth.hasAnyUser(), isTrue);
    expect(id, isNotEmpty);
    await expectLater(
      auth.createInitialManager(
        username: 'second', displayName: 'مدير آخر', password: 'Strong-password-456',
      ),
      throwsA(isA<AuthException>()),
    );
    final user = await auth.login(username: 'OWNER', password: 'Strong-password-123');
    expect(user.id, id);
    expect((await auth.currentUser())?.id, id);
    await auth.logout();
    expect(await auth.currentUser(), isNull);
    await provider.close();
  });

  test('locks after five failures and rejects inactive accounts', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(
      db, MemorySecretStore(), passwordHasher: PasswordHasher(iterations: 10000),
    );
    final id = await auth.createInitialManager(
      username: 'manager', displayName: 'المدير', password: 'Strong-password-123',
    );
    for (var i = 0; i < AuthService.maxFailedAttempts; i++) {
      await expectLater(
        auth.login(username: 'manager', password: 'incorrect-password'),
        throwsA(isA<AuthException>()),
      );
    }
    await expectLater(
      auth.login(username: 'manager', password: 'Strong-password-123'),
      throwsA(isA<AuthException>()),
    );
    await db.update('app_users', {'is_active': 0}, where: 'id = ?', whereArgs: [id]);
    await db.update(
      'auth_login_attempts', {'locked_until': null, 'failed_attempts': 0},
      where: 'username = ?', whereArgs: ['manager'],
    );
    await expectLater(
      auth.login(username: 'manager', password: 'Strong-password-123'),
      throwsA(isA<AuthException>()),
    );
    await provider.close();
  });
}
