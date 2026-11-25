/// Roles stored in SQLite. Values are stable storage identifiers.
enum AppRole {
  manager,
  employee,
  inventoryManager,
  debtCollector;

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
