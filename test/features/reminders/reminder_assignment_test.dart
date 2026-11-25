import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:advanced_assistant/core/auth/app_role.dart';
import 'package:advanced_assistant/core/auth/auth_service.dart';
import 'package:advanced_assistant/core/auth/authorization_service.dart';
import 'package:advanced_assistant/core/auth/password_hasher.dart';
import 'package:advanced_assistant/core/auth/session_secret_store.dart';
import 'package:advanced_assistant/core/database/database_provider.dart';
import 'package:advanced_assistant/features/reminders/data/reminder_repository.dart';
import 'package:advanced_assistant/features/users/data/user_repository.dart';

class _Store implements SessionSecretStore {
  String? value;
  @override Future<void> delete() async => value = null;
  @override Future<String?> read() async => value;
  @override Future<void> write(String value) async => this.value = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });

  test('manager assigns follow-up to an active employee and audit records it', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(db, _Store(), passwordHasher: PasswordHasher(iterations: 10000));
    await auth.createInitialManager(username: 'manager', displayName: 'المدير', password: 'Strong-password-123');
    await auth.login(username: 'manager', password: 'Strong-password-123');
    final authz = AuthorizationService(db, auth);
    final users = UserRepository(db, authz, auth);
    await users.create(username: 'worker1', displayName: 'موظف أول', password: 'Worker-password-123', role: AppRole.employee);
    final worker = (await users.list()).singleWhere((u) => u.username == 'worker1');
    final reminders = ReminderRepository(db, authz);
    final followup = await reminders.create(title: 'اتصال تجريبي', dueAt: DateTime.utc(2026, 11, 27));
    await reminders.assign(followupId: followup.id, userId: worker.id);
    final row = (await db.query('followups', where: 'id = ?', whereArgs: [followup.id])).single;
    expect(row['assigned_to'], worker.id);
    final events = await db.query('audit_events', where: 'action = ?', whereArgs: ['followup.assign']);
    expect(events, hasLength(1));
    await provider.close();
  });

  test('non-manager cannot assign follow-ups', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(db, _Store(), passwordHasher: PasswordHasher(iterations: 10000));
    await auth.createInitialManager(username: 'manager', displayName: 'المدير', password: 'Strong-password-123');
    await auth.login(username: 'manager', password: 'Strong-password-123');
    final managerAuthz = AuthorizationService(db, auth);
    await UserRepository(db, managerAuthz, auth).create(username: 'worker1', displayName: 'موظف أول', password: 'Worker-password-123', role: AppRole.employee);
    final worker = (await db.query('app_users', where: 'username = ?', whereArgs: ['worker1'])).single;
    await auth.logout();
    await auth.login(username: 'worker1', password: 'Worker-password-123');
    final repo = ReminderRepository(db, AuthorizationService(db, auth));
    final followup = await repo.create(title: 'اتصال تجريبي', dueAt: DateTime.utc(2026, 11, 27));
    await expectLater(repo.assign(followupId: followup.id, userId: worker['id']! as String), throwsA(isA<Exception>()));
    await provider.close();
  });
}
