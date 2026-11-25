import 'dart:convert';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/app_permission.dart';
import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_policy.dart';
import '../../../core/auth/authorization_service.dart';

class ManagedUser {
  const ManagedUser({required this.id, required this.username, required this.displayName, required this.role, required this.isActive, required this.createdAt});
  final String id, username, displayName, role;
  final bool isActive;
  final DateTime createdAt;
  factory ManagedUser.fromMap(Map<String,Object?> row)=>ManagedUser(
    id: row['id']! as String, username: row['username']! as String,
    displayName: row['display_name']! as String, role: row['role']! as String,
    isActive: row['is_active']==1, createdAt: DateTime.parse(row['created_at']! as String).toLocal(),
  );
}

class UserRepository {
  UserRepository(this.database,this.authorization,this.authService,{Random? random,DateTime Function()? clock})
    : _random=random??Random.secure(),_clock=clock??DateTime.now;
  final Database database;
  final AuthorizationService authorization;
  final AuthService authService;
  final Random _random;
  final DateTime Function() _clock;

  Future<List<ManagedUser>> list() async {
    final context=await authorization.loadContext();
    const policy=AuthorizationPolicy();
    policy.requirePermission(context,AppPermission.usersManage);
    final rows=await database.query('app_users',columns:['id','username','display_name','role','is_active','created_at'],orderBy:'created_at DESC');
    return rows.map(ManagedUser.fromMap).toList(growable:false);
  }

  Future<void> create({required String username,required String displayName,required String password,required AppRole role}) async {
    final context=await authorization.loadContext();
    const policy=AuthorizationPolicy();
    policy.requirePermission(context,AppPermission.usersManage);
    final cleanUsername=username.trim().toLowerCase();
    final cleanName=displayName.trim();
    if(!RegExp(r'^[a-z0-9_.-]{3,40}$').hasMatch(cleanUsername)) throw const UserValidationException('اسم المستخدم: 3 إلى 40 حرفاً إنجليزياً أو أرقاماً أو . _ -');
    if(cleanName.isEmpty||cleanName.length>100) throw const UserValidationException('الاسم الظاهر مطلوب وبحد أقصى 100 حرف');
    if(password.length<10) throw const UserValidationException('كلمة المرور يجب ألا تقل عن 10 أحرف');
    if(role==AppRole.manager) throw const UserValidationException('إنشاء مدير إضافي غير متاح من هذه الشاشة');
    final hash=await authService.passwordHasher.hash(password);
    final id=_id();
    final now=_clock().toUtc().toIso8601String();
    try {
      await database.transaction((txn) async {
        await txn.insert('app_users',{'id':id,'username':cleanUsername,'display_name':cleanName,'password_hash':hash,'role':role.storageValue,'is_active':1,'created_at':now,'updated_at':now});
        await txn.insert('audit_events',{'id':_id(),'actor_user_id':context.userId,'entity_type':'app_user','entity_id':id,'action':'user.create','after_json':jsonEncode({'username':cleanUsername,'display_name':cleanName,'role':role.storageValue,'is_active':true}),'occurred_at':now});
      });
    } on DatabaseException catch(e) {
      if(e.isUniqueConstraintError()) throw const UserValidationException('اسم المستخدم مستخدم بالفعل');
      rethrow;
    }
  }

  Future<void> setActive({required String userId,required bool active}) async {
    final context=await authorization.loadContext();
    const policy=AuthorizationPolicy();
    policy.requirePermission(context,AppPermission.usersManage);
    if(userId==context.userId&&!active) throw const UserValidationException('لا يمكنك إيقاف حسابك الحالي');
    final now=_clock().toUtc().toIso8601String();
    await database.transaction((txn) async {
      final rows=await txn.query('app_users',where:'id = ?',whereArgs:[userId],limit:1);
      if(rows.isEmpty) throw const UserValidationException('الحساب غير موجود');
      final current=rows.single;
      if(current['is_active']==(active?1:0)) return;
      if(!active&&current['role']=='manager') {
        final managers=Sqflite.firstIntValue(await txn.rawQuery("SELECT COUNT(*) FROM app_users WHERE role='manager' AND is_active=1"))??0;
        if(managers<=1) throw const UserValidationException('لا يمكن إيقاف آخر حساب مدير');
      }
      await txn.update('app_users',{'is_active':active?1:0,'updated_at':now},where:'id = ?',whereArgs:[userId]);
      if(!active) await txn.update('auth_sessions',{'revoked_at':now},where:'user_id = ? AND revoked_at IS NULL',whereArgs:[userId]);
      await txn.insert('audit_events',{'id':_id(),'actor_user_id':context.userId,'entity_type':'app_user','entity_id':userId,'action':active?'user.activate':'user.deactivate','before_json':jsonEncode({'is_active':current['is_active']}),'after_json':jsonEncode({'is_active':active}),'occurred_at':now});
    });
  }
  String _id()=>List<int>.generate(16,(_)=>_random.nextInt(256)).map((v)=>v.toRadixString(16).padLeft(2,'0')).join();
}
class UserValidationException implements Exception {
  const UserValidationException(this.message);
  final String message;
  @override String toString()=>message;
}
