import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:advanced_assistant/core/auth/app_role.dart';
import 'package:advanced_assistant/core/auth/auth_service.dart';
import 'package:advanced_assistant/core/auth/authorization_service.dart';
import 'package:advanced_assistant/core/auth/password_hasher.dart';
import 'package:advanced_assistant/core/auth/session_secret_store.dart';
import 'package:advanced_assistant/core/database/database_provider.dart';
import 'package:advanced_assistant/features/users/data/user_repository.dart';

class _Store implements SessionSecretStore {
 String? value;
 @override Future<void> delete() async=>value=null;
 @override Future<String?> read() async=>value;
 @override Future<void> write(String value) async=>this.value=value;
}
void main(){
 TestWidgetsFlutterBinding.ensureInitialized();
 setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });
 test('manager creates users and deactivation revokes their sessions',() async {
  final provider=DatabaseProvider(databasePath:inMemoryDatabasePath);final db=await provider.database;
  final auth=AuthService(db,_Store(),passwordHasher:PasswordHasher(iterations:10000));
  await auth.createInitialManager(username:'manager',displayName:'المدير',password:'Strong-password-123');
  await auth.login(username:'manager',password:'Strong-password-123');
  final repo=UserRepository(db,AuthorizationService(db,auth),auth);
  await repo.create(username:'staff01',displayName:'موظف',password:'Staff-password-123',role:AppRole.employee);
  final staff=(await repo.list()).firstWhere((u)=>u.username=='staff01');
  expect(staff.isActive,isTrue);
  final sessions=await db.query('auth_sessions',where:'user_id = ?',whereArgs:[staff.id]);
  await repo.setActive(userId:staff.id,active:false);
  expect((await repo.list()).firstWhere((u)=>u.id==staff.id).isActive,isFalse);
  expect(await db.query('audit_events',where:'action = ?',whereArgs:['user.deactivate']),hasLength(1));
  expect(sessions,isEmpty);
  await provider.close();
 });
 test('rejects weak password and manager role escalation',() async {
  final provider=DatabaseProvider(databasePath:inMemoryDatabasePath);final db=await provider.database;
  final auth=AuthService(db,_Store(),passwordHasher:PasswordHasher(iterations:10000));
  await auth.createInitialManager(username:'manager',displayName:'المدير',password:'Strong-password-123');
  await auth.login(username:'manager',password:'Strong-password-123');
  final repo=UserRepository(db,AuthorizationService(db,auth),auth);
  await expectLater(repo.create(username:'staff',displayName:'موظف',password:'short',role:AppRole.employee),throwsA(isA<UserValidationException>()));
  await expectLater(repo.create(username:'boss',displayName:'مدير آخر',password:'Staff-password-123',role:AppRole.manager),throwsA(isA<UserValidationException>()));
  await provider.close();
 });
}
