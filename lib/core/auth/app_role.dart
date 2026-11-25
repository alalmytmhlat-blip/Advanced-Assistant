/// Roles stored in SQLite. Values are stable storage identifiers.
enum AppRole {
  manager,
  employee,
  inventoryManager,
  debtCollector;

  String get storageValue => switch (this) {
    AppRole.manager => 'manager',
    AppRole.employee => 'employee',
    AppRole.inventoryManager => 'inventory_manager',
    AppRole.debtCollector => 'debt_collector',
  };

  static AppRole? fromStorage(String value) {
    switch (value) {
      case 'manager':
        return AppRole.manager;
      case 'employee':
        return AppRole.employee;
      case 'inventory_manager':
        return AppRole.inventoryManager;
      case 'debt_collector':
        return AppRole.debtCollector;
      default:
        return null;
    }
  }
}
