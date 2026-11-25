import 'package:sqflite/sqflite.dart';

import 'app_permission.dart';
import 'app_role.dart';
import 'authorization_policy.dart';

/// Loads current grants/scopes from SQLite for use by application use-cases.
class AuthorizationService {
  AuthorizationService(
    this.database, {
    this.policy = const AuthorizationPolicy(),
  });

  final Database database;
  final AuthorizationPolicy policy;

  Future<AuthorizationContext> loadContext(String userId) async {
    final users = await database.query(
      'app_users',
      columns: ['id', 'role', 'is_active'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (users.isEmpty) {
      throw const AuthorizationException('الحساب غير موجود');
    }

    final user = users.single;
    final role = AppRole.fromStorage(user['role']! as String);
    if (role == null) {
      throw const AuthorizationException('دور الحساب غير معروف');
    }

    final permissionRows = await database.query(
      'user_permissions',
      columns: ['permission'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final scopeRows = await database.query(
      'user_customer_scopes',
      columns: ['customer_id'],
      where: 'user_id = ?',
      whereArgs: [userId],
    );

    return AuthorizationContext(
      userId: userId,
      role: role,
      isActive: user['is_active'] == 1,
      grantedPermissions: permissionRows
          .map((row) => row['permission']! as String)
          .where(AppPermission.all.contains)
          .toSet(),
      scopedCustomerIds: scopeRows
          .map((row) => row['customer_id']! as String)
          .toSet(),
    );
  }

  Future<void> requirePermission(
    String userId,
    String permission,
  ) async {
    final context = await loadContext(userId);
    policy.requirePermission(context, permission);
  }

  Future<void> requireCustomerAccess(
    String userId,
    String customerId,
  ) async {
    final context = await loadContext(userId);
    policy.requireCustomerAccess(context, customerId);
  }
}
