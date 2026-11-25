import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:advanced_assistant/core/auth/auth_service.dart';
import 'package:advanced_assistant/core/auth/authorization_service.dart';
import 'package:advanced_assistant/core/auth/password_hasher.dart';
import 'package:advanced_assistant/core/auth/session_secret_store.dart';
import 'package:advanced_assistant/core/database/database_provider.dart';
import 'package:advanced_assistant/features/inventory/data/inventory_repository.dart';

class _SecretStore implements SessionSecretStore {
  String? value;
  @override Future<void> delete() async => value = null;
  @override Future<String?> read() async => value;
  @override Future<void> write(String value) async => this.value = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
  test('creates exact item labels and audits quantity changes', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(db, _SecretStore(), passwordHasher: PasswordHasher(iterations: 10000));
    await auth.createInitialManager(username: 'manager', displayName: 'المدير', password: 'Strong-password-123');
    await auth.login(username: 'manager', password: 'Strong-password-123');
    final repo = InventoryRepository(db, AuthorizationService(db, auth));
    await repo.create(name: 'ماسورة 4 هـ 2,2 أسود', code: '04-A', size: '2,2', unit: 'متر', category: 'مواسير', quantity: '12.500', minimumQuantity: '3');
    final item = (await repo.list()).single;
    expect(item.name, 'ماسورة 4 هـ 2,2 أسود');
    expect(item.quantity, '12.5');
    await repo.updateQuantity(itemId: item.id, quantity: '2', reason: 'جرد فعلي');
    final updated = (await repo.list()).single;
    expect(updated.quantity, '2');
    expect(updated.isLowStock, isTrue);
    final audit = await db.query('audit_events', where: 'action = ?', whereArgs: ['inventory.quantity.update']);
    expect(audit, hasLength(1));
    expect(audit.single['reason'], 'جرد فعلي');
    await provider.close();
  });
  test('rejects negative quantities and missing adjustment reason', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(db, _SecretStore(), passwordHasher: PasswordHasher(iterations: 10000));
    await auth.createInitialManager(username: 'manager', displayName: 'المدير', password: 'Strong-password-123');
    await auth.login(username: 'manager', password: 'Strong-password-123');
    final repo = InventoryRepository(db, AuthorizationService(db, auth));
    await expectLater(repo.create(name: 'صنف', quantity: '-1'), throwsA(isA<InventoryValidationException>()));
    await repo.create(name: 'صنف', quantity: '1');
    final item = (await repo.list()).single;
    await expectLater(repo.updateQuantity(itemId: item.id, quantity: '2', reason: ' '), throwsA(isA<InventoryValidationException>()));
    await provider.close();
  });
}
