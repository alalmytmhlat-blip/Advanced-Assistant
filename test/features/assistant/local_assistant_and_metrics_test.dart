import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:advanced_assistant/core/auth/auth_service.dart';
import 'package:advanced_assistant/core/auth/authorization_service.dart';
import 'package:advanced_assistant/core/auth/password_hasher.dart';
import 'package:advanced_assistant/core/auth/session_secret_store.dart';
import 'package:advanced_assistant/core/database/database_provider.dart';
import 'package:advanced_assistant/features/assistant/data/local_assistant_service.dart';
import 'package:advanced_assistant/features/customers/data/customer_model.dart';
import 'package:advanced_assistant/features/customers/data/customer_repository.dart';
import 'package:advanced_assistant/features/dashboard/data/dashboard_metrics_repository.dart';
import 'package:advanced_assistant/features/inventory/data/inventory_repository.dart';
import 'package:advanced_assistant/features/reminders/data/reminder_repository.dart';

class _Secret implements SessionSecretStore {
  String? value;
  @override Future<void> delete() async { value = null; }
  @override Future<String?> read() async => value;
  @override Future<void> write(String value) async { this.value = value; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; });

  test('dashboard metrics and local Arabic assistant read real authorized records', () async {
    final provider = DatabaseProvider(databasePath: inMemoryDatabasePath);
    final db = await provider.database;
    final auth = AuthService(db, _Secret(), passwordHasher: PasswordHasher(iterations: 10000));
    await auth.createInitialManager(username: 'manager', displayName: 'المدير', password: 'Strong-password-123');
    await auth.login(username: 'manager', password: 'Strong-password-123');
    final authz = AuthorizationService(db, auth);

    final customer = await CustomerRepository(db, authz).create(const CustomerDraft(name: 'عميل تجريبي', phone: '700000001'));
    await InventoryRepository(db, authz).create(name: 'صنف اختبار', quantity: '1', minimumQuantity: '2');
    await ReminderRepository(db, authz).create(title: 'متابعة متأخرة', customerId: customer.id, dueAt: DateTime.now().subtract(const Duration(days: 1)));

    final metrics = await DashboardMetricsRepository(db, authz).load();
    expect(metrics.customers, 1);
    expect(metrics.activeFollowups, 1);
    expect(metrics.overdueFollowups, 1);
    expect(metrics.inventoryItems, 1);
    expect(metrics.lowStockItems, 1);

    final assistant = LocalAssistantService(db, authz);
    final count = await assistant.ask('عدد العملاء');
    expect(count.message, contains('1'));
    final balance = await assistant.ask('رصيد عميل تجريبي');
    expect(balance.details.single, contains('عميل تجريبي'));
    final overdue = await assistant.ask('المتابعات المتأخرة');
    expect(overdue.details.single, contains('متابعة متأخرة'));
    await provider.close();
  });
}
