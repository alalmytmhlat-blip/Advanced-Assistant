/// Stable permission identifiers persisted in user_permissions.
abstract final class AppPermission {
  static const customerRead = 'customer.read';
  static const customerCreate = 'customer.create';
  static const customerUpdate = 'customer.update';
  static const customerArchive = 'customer.archive';
  static const customerNotesCreate = 'customer.notes.create';
  static const contactRecord = 'contact.record';
  static const balanceRead = 'balance.read';
  static const balanceUpdate = 'balance.update';
  static const followupRead = 'followup.read';
  static const followupCreate = 'followup.create';
  static const followupUpdate = 'followup.update';
  static const inventoryRead = 'inventory.read';
  static const inventoryManage = 'inventory.manage';
  static const reportsRead = 'reports.read';
  static const usersManage = 'users.manage';
  static const settingsManage = 'settings.manage';

  static const all = <String>{
    customerRead,
    customerCreate,
    customerUpdate,
    customerArchive,
    customerNotesCreate,
    contactRecord,
    balanceRead,
    balanceUpdate,
    followupRead,
    followupCreate,
    followupUpdate,
    inventoryRead,
    inventoryManage,
    reportsRead,
    usersManage,
    settingsManage,
  };
}
