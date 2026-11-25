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
import 'package:advanced_assistant/features/reminders/data/reminder_repository.dart';

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
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });

  test('creates and completes customer follow-up with contact history and audit', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(db, _TestSecretStore(), passwordHasher: PasswordHasher(iterations: 10000));
    await auth.createInitialManager(username: 'manager', displayName: 'المدير', password: 'Strong-password-123');
    await auth.login(username: 'manager', password: 'Strong-password-123');
    final authz = AuthorizationService(db, auth);
    final customer = await CustomerRepository(db, authz).create(const CustomerDraft(name: 'عميل متابعة'));
    final repo = ReminderRepository(db, authz);
    final item = await repo.create(title: 'الاتصال بالعميل', dueAt: DateTime.utc(2026, 11, 26, 9), customerId: customer.id, note: 'متابعة');
    expect(item.customerName, 'عميل متابعة');
    expect(item.status, 'new');
    await repo.updateStatus(id: item.id, status: 'completed', outcome: 'تم التواصل');
    expect((await repo.list(status: 'completed')), hasLength(1));
    expect(await db.query('contact_events', where: 'customer_id = ?', whereArgs: [customer.id]), hasLength(1));
    expect(await db.query('audit_events', where: 'entity_type = ?', whereArgs: ['followup']), hasLength(2));
    await provider.close();
  });

  test('active filter returns only new and scheduled reminders', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(db, _TestSecretStore(), passwordHasher: PasswordHasher(iterations: 10000));
    await auth.createInitialManager(username: 'manager', displayName: 'المدير', password: 'Strong-password-123');
    await auth.login(username: 'manager', password: 'Strong-password-123');
    final repo = ReminderRepository(db, AuthorizationService(db, auth));
    final first = await repo.create(title: 'جديدة', dueAt: DateTime.utc(2026, 11, 26));
    final second = await repo.create(title: 'مجدولة', dueAt: DateTime.utc(2026, 11, 27));
    final third = await repo.create(title: 'مكتملة', dueAt: DateTime.utc(2026, 11, 28));
    await repo.updateStatus(id: second.id, status: 'scheduled');
    await repo.updateStatus(id: third.id, status: 'completed');
    final active = await repo.list(status: 'active');
    expect(active.map((item) => item.id).toSet(), {first.id, second.id});
    expect(active.any((item) => item.id == third.id), isFalse);
    await provider.close();
  });

  test('requires authentication and rejects empty title', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(db, _TestSecretStore(), passwordHasher: PasswordHasher(iterations: 10000));
    await auth.createInitialManager(username: 'manager', displayName: 'المدير', password: 'Strong-password-123');
    final repo = ReminderRepository(db, AuthorizationService(db, auth));
    await expectLater(repo.create(title: 'x', dueAt: DateTime.now()), throwsA(isA<AuthorizationException>()));
    await auth.login(username: 'manager', password: 'Strong-password-123');
    await expectLater(repo.create(title: ' ', dueAt: DateTime.now()), throwsA(isA<ReminderValidationException>()));
    await provider.close();
  });
}
