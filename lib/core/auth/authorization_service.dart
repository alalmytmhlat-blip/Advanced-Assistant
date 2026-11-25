import 'package:sqflite/sqflite.dart';

import 'app_permission.dart';
import 'auth_service.dart';
import 'authorization_policy.dart';

/// Resolves authorization only from the currently authenticated session.
/// Callers cannot supply another user's ID.
class AuthorizationService {
  AuthorizationService(
    this.database,
    this.authService, {
    this.policy = const AuthorizationPolicy(),
  });

  final Database database;
  final AuthService authService;
  final AuthorizationPolicy policy;

  Future<AuthorizationContext> loadContext() async {
    final authenticatedUser = await authService.currentUser();
    if (authenticatedUser == null) {
      throw const AuthorizationException('يلزم تسجيل الدخول أولاً');
    }

    final users = await database.query(
      'app_users',
      columns: ['id', 'role', 'is_active'],
      where: 'id = ?',
      whereArgs: [authenticatedUser.id],
      limit: 1,
    );
    if (users.isEmpty || users.single['is_active'] != 1) {
      throw const AuthorizationException('الحساب غير موجود أو غير نشط');
    }

    final user = users.single;
    final role = AppRole.fromStorage(user['role']! as String);
    if (role == null || role != authenticatedUser.role) {
      throw const AuthorizationException('تعذر التحقق من دور الحساب');
    }

    final permissionRows = await database.query(
      'user_permissions',
      columns: ['permission'],
      where: 'user_id = ?',
      whereArgs: [authenticatedUser.id],
    );
    final scopeRows = await database.query(
      'user_customer_scopes',
      columns: ['customer_id'],
      where: 'user_id = ?',
      whereArgs: [authenticatedUser.id],
    );

    return AuthorizationContext(
      userId: authenticatedUser.id,
      role: role,
      isActive: true,
      grantedPermissions: permissionRows
          .map((row) => row['permission']! as String)
          .where(AppPermission.all.contains)
          .toSet(),
      scopedCustomerIds: scopeRows
          .map((row) => row['customer_id']! as String)
          .toSet(),
    );
  }

  Future<void> requirePermission(String permission) async {
    final context = await loadContext();
    policy.requirePermission(context, permission);
  }

  Future<void> requireCustomerAccess(String customerId) async {
    final context = await loadContext();
    policy.requireCustomerAccess(context, customerId);
  }
}
