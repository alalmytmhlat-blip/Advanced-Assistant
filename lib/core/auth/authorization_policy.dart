import 'app_permission.dart';
import 'app_role.dart';

/// Immutable authorization snapshot for one authenticated local user.
class AuthorizationContext {
  const AuthorizationContext({
    required this.userId,
    required this.role,
    required this.isActive,
    this.grantedPermissions = const {},
    this.scopedCustomerIds = const {},
  });

  final String userId;
  final AppRole role;
  final bool isActive;
  final Set<String> grantedPermissions;
  final Set<String> scopedCustomerIds;
}

class AuthorizationException implements Exception {
  const AuthorizationException(this.message);
  final String message;

  @override
  String toString() => 'AuthorizationException: $message';
}

/// Central policy. UI visibility is never considered an authorization check.
class AuthorizationPolicy {
  const AuthorizationPolicy();

  static const _managerPermissions = AppPermission.all;

  static const _employeePermissions = <String>{
    AppPermission.customerRead,
    AppPermission.customerCreate,
    AppPermission.customerUpdate,
    AppPermission.customerNotesCreate,
    AppPermission.contactRecord,
    AppPermission.balanceRead,
    AppPermission.followupRead,
    AppPermission.followupCreate,
    AppPermission.followupUpdate,
    AppPermission.inventoryRead,
    AppPermission.reportsRead,
  };

  static const _inventoryPermissions = <String>{
    AppPermission.inventoryRead,
    AppPermission.inventoryManage,
    AppPermission.reportsRead,
  };

  static const _debtCollectorPermissions = <String>{
    AppPermission.customerRead,
    AppPermission.customerNotesCreate,
    AppPermission.contactRecord,
    AppPermission.balanceRead,
    AppPermission.followupRead,
    AppPermission.followupCreate,
    AppPermission.followupUpdate,
  };

  bool hasPermission(AuthorizationContext context, String permission) {
    if (!context.isActive || !AppPermission.all.contains(permission)) {
      return false;
    }

    final rolePermissions = switch (context.role) {
      AppRole.manager => _managerPermissions,
      AppRole.employee => _employeePermissions,
      AppRole.inventoryManager => _inventoryPermissions,
      AppRole.debtCollector => _debtCollectorPermissions,
    };

    return rolePermissions.contains(permission) ||
        context.grantedPermissions.contains(permission);
  }

  bool canAccessCustomer(
    AuthorizationContext context,
    String customerId,
  ) {
    if (!hasPermission(context, AppPermission.customerRead)) return false;

    // Managers and employees work across the customer directory.
    if (context.role == AppRole.manager ||
        context.role == AppRole.employee) {
      return true;
    }

    // Restricted roles need an explicit allow-list assignment.
    return context.scopedCustomerIds.contains(customerId);
  }

  void requirePermission(
    AuthorizationContext context,
    String permission,
  ) {
    if (!hasPermission(context, permission)) {
      throw const AuthorizationException('ليس لديك صلاحية لتنفيذ هذه العملية');
    }
  }

  void requireCustomerAccess(
    AuthorizationContext context,
    String customerId,
  ) {
    if (!canAccessCustomer(context, customerId)) {
      throw const AuthorizationException('لا تملك صلاحية الوصول إلى هذا العميل');
    }
  }
}
