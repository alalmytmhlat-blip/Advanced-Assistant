import 'package:flutter_test/flutter_test.dart';
import 'package:advanced_assistant/core/auth/app_permission.dart';
import 'package:advanced_assistant/core/auth/app_role.dart';
import 'package:advanced_assistant/core/auth/authorization_policy.dart';

void main() {
  const policy = AuthorizationPolicy();

  AuthorizationContext context(
    AppRole role, {
    bool active = true,
    Set<String> grants = const {},
    Set<String> customers = const {},
  }) {
    return AuthorizationContext(
      userId: 'user-1',
      role: role,
      isActive: active,
      grantedPermissions: grants,
      scopedCustomerIds: customers,
    );
  }

  test('manager has all known permissions', () {
    final manager = context(AppRole.manager);
    for (final permission in AppPermission.all) {
      expect(policy.hasPermission(manager, permission), isTrue);
    }
  });

  test('inventory manager cannot read customer records by default', () {
    final inventory = context(AppRole.inventoryManager);
    expect(
      policy.hasPermission(inventory, AppPermission.inventoryManage),
      isTrue,
    );
    expect(
      policy.hasPermission(inventory, AppPermission.customerRead),
      isFalse,
    );
    expect(policy.canAccessCustomer(inventory, 'customer-1'), isFalse);
  });

  test('debt collector is limited to explicitly assigned customers', () {
    final collector = context(
      AppRole.debtCollector,
      customers: {'customer-1'},
    );
    expect(policy.canAccessCustomer(collector, 'customer-1'), isTrue);
    expect(policy.canAccessCustomer(collector, 'customer-2'), isFalse);
    expect(
      policy.hasPermission(collector, AppPermission.balanceUpdate),
      isFalse,
    );
  });

  test('inactive accounts cannot use even role permissions or grants', () {
    final disabled = context(
      AppRole.manager,
      active: false,
      grants: {AppPermission.inventoryManage},
    );
    expect(
      policy.hasPermission(disabled, AppPermission.usersManage),
      isFalse,
    );
    expect(
      policy.hasPermission(disabled, AppPermission.inventoryManage),
      isFalse,
    );
  });

  test('unknown permission identifiers are rejected', () {
    final manager = context(AppRole.manager);
    expect(policy.hasPermission(manager, 'system.root'), isFalse);
  });

  test('explicit grants add permissions to a role', () {
    final employee = context(
      AppRole.employee,
      grants: {AppPermission.inventoryManage},
    );
    expect(
      policy.hasPermission(employee, AppPermission.inventoryManage),
      isTrue,
    );
  });

  test('restricted role still needs a customer scope after a grant', () {
    final inventory = context(
      AppRole.inventoryManager,
      grants: {AppPermission.customerRead},
    );
    expect(policy.canAccessCustomer(inventory, 'customer-1'), isFalse);
  });
}
