// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/app_permission.dart';
import '../../../core/auth/app_role.dart';
import '../../../core/auth/authorization_policy.dart';
import '../../../core/auth/authorization_service.dart';

class DashboardMetrics {
  const DashboardMetrics({this.customers, this.activeFollowups, this.overdueFollowups, this.inventoryItems, this.lowStockItems});
  final int? customers;
  final int? activeFollowups;
  final int? overdueFollowups;
  final int? inventoryItems;
  final int? lowStockItems;
}

class DashboardMetricsRepository {
  DashboardMetricsRepository(this.database, this.authorization);
  final Database database;
  final AuthorizationService authorization;

  Future<DashboardMetrics> load() async {
    final context = await authorization.loadContext();
    const policy = AuthorizationPolicy();
    int? customers, active, overdue, inventory, lowStock;
    if (policy.hasPermission(context, AppPermission.customerRead)) {
      final scope = _scope(context);
      customers = await _count('customers', 'is_archived = 0${scope.sql}', scope.args);
    }
    if (policy.hasPermission(context, AppPermission.followupRead)) {
      final scope = _scope(context, nullable: true);
      active = await _count('followups', "status IN ('new','scheduled','postponed')${scope.sql}", scope.args);
      overdue = await _count('followups', "status IN ('new','scheduled','postponed') AND due_at < ?${scope.sql}", [DateTime.now().toUtc().toIso8601String(), ...scope.args]);
    }
    if (policy.hasPermission(context, AppPermission.inventoryRead)) {
      inventory = await _count('inventory_items', 'is_archived = 0', const []);
      lowStock = await _count('inventory_items', 'is_archived = 0 AND CAST(quantity AS REAL) <= CAST(minimum_quantity AS REAL)', const []);
    }
    return DashboardMetrics(customers: customers, activeFollowups: active, overdueFollowups: overdue, inventoryItems: inventory, lowStockItems: lowStock);
  }

  ({String sql, List<Object?> args}) _scope(AuthorizationContext context, {bool nullable = false}) {
    if (context.role == AppRole.manager || context.role == AppRole.employee) return (sql: '', args: <Object?>[]);
    final ids = context.scopedCustomerIds.toList(growable: false);
    if (ids.isEmpty) return (sql: nullable ? ' AND customer_id IS NULL' : ' AND 1 = 0', args: <Object?>[]);
    final placeholders = ids.map((_) => '?').join(',');
    return (sql: nullable ? ' AND (customer_id IS NULL OR customer_id IN ($placeholders))' : ' AND id IN ($placeholders)', args: ids);
  }

  Future<int> _count(String table, String where, List<Object?> args) async {
    final rows = await database.rawQuery('SELECT COUNT(*) AS count FROM $table WHERE $where', args);
    return (rows.single['count'] as int?) ?? 0;
  }
}
