// ignore_for_file: deprecated_member_use, curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/auth/auth_service.dart';
import '../../../core/auth/authorization_service.dart';
import '../data/dashboard_metrics_repository.dart';
import '../../assistant/presentation/assistant_page.dart';
import '../../customers/presentation/customers_page.dart';
import '../../reminders/presentation/reminders_page.dart';
import '../../inventory/presentation/inventory_page.dart';
import '../../users/presentation/users_page.dart';
import '../../reports/presentation/reports_page.dart';
import '../../backup/presentation/backup_page.dart';
import '../../../core/database/database_provider.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.onLogout, required this.database, required this.authService, required this.databaseProvider});
  final VoidCallback onLogout;
  final Database database;
  final AuthService authService;
  final DatabaseProvider databaseProvider;
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}
class _DashboardPageState extends State<DashboardPage> {
  late final DashboardMetricsRepository _metricsRepository;
  DashboardMetrics? _metrics;
  bool _loadingMetrics = true;
  @override
  void initState() {
    super.initState();
    _metricsRepository = DashboardMetricsRepository(widget.database, AuthorizationService(widget.database, widget.authService));
    _loadMetrics();
  }
  Future<void> _loadMetrics() async {
    try {
      final result = await _metricsRepository.load();
      if (mounted) setState(() { _metrics = result; _loadingMetrics = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingMetrics = false);
    }
  }
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppBar(title: const Text('المساعد الذكي', style: TextStyle(fontWeight: FontWeight.w700)), actions: [
        IconButton(tooltip: 'تحديث المؤشرات', onPressed: _loadMetrics, icon: const Icon(Icons.refresh)),
        IconButton(tooltip: 'تسجيل الخروج', onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
      ]),
      body: RefreshIndicator(
        onRefresh: _loadMetrics,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('مرحبًا بك', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('إدارة العملاء والأرصدة والمتابعات والمخزون من مكان واحد، مع حفظ البيانات محليًا.'),
          ]))),
          const SizedBox(height: 12),
          _metricsSection(context),
          const SizedBox(height: 12),
          _module(context, Icons.psychology_alt_outlined, 'المساعد الذكي المحلي', 'اسأل عن العملاء والأرصدة والمتابعات والمخزون دون إنترنت', () => AssistantPage(database: widget.database, authService: widget.authService)),
          _module(context, Icons.people_alt_outlined, 'إدارة العملاء', 'إضافة العملاء والبحث وتحديث بياناتهم', () => CustomersPage(database: widget.database, authService: widget.authService)),
          _module(context, Icons.notifications_active_outlined, 'المتابعات والتذكيرات', 'مواعيد العملاء والمهام والتنبيهات المحلية', () => RemindersPage(database: widget.database, authService: widget.authService)),
          _module(context, Icons.inventory_2_outlined, 'إدارة المخزون', 'الأصناف والكميات والفئات وحدود التنبيه', () => InventoryPage(database: widget.database, authService: widget.authService)),
          _module(context, Icons.manage_accounts_outlined, 'إدارة المستخدمين', 'إنشاء حسابات الموظفين وإيقافها وتفعيلها', () => UsersPage(database: widget.database, authService: widget.authService)),
          _module(context, Icons.assessment_outlined, 'التقارير والتصدير', 'تقارير العملاء والمتابعات والمخزون بصيغتي PDF وCSV', () => ReportsPage(database: widget.database, authService: widget.authService)),
          _module(context, Icons.backup_outlined, 'النسخ الاحتياطي', 'إنشاء نسخة آمنة أو استعادة نسخة سابقة', () => BackupPage(provider: widget.databaseProvider, authService: widget.authService, onRestored: widget.onLogout)),
        ]),
      ),
    ),
  );

  Widget _metricsSection(BuildContext context) {
    final m = _metrics;
    if (_loadingMetrics) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
    if (m == null) return const SizedBox.shrink();
    final tiles = <Widget>[];
    void add(String label, int? value, IconData icon) {
      if (value != null) tiles.add(_metricTile(context, label, value, icon));
    }
    add('العملاء', m.customers, Icons.people_outline);
    add('المتابعات النشطة', m.activeFollowups, Icons.pending_actions);
    add('المتابعات المتأخرة', m.overdueFollowups, Icons.warning_amber_outlined);
    add('أصناف المخزون', m.inventoryItems, Icons.inventory_2_outlined);
    add('أصناف عند حد التنبيه', m.lowStockItems, Icons.notifications_active_outlined);
    if (tiles.isEmpty) return const SizedBox.shrink();
    return GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.8, children: tiles);
  }

  Widget _metricTile(BuildContext context, String label, int value, IconData icon) => Card(
    child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 10),
      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value.toString(), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
      ])),
    ])),
  );

  Widget _module(BuildContext context, IconData icon, String title, String subtitle, Widget Function() page) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(child: ListTile(
      leading: CircleAvatar(child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle), trailing: const Icon(Icons.chevron_left),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page()));
        _loadMetrics();
      },
    )),
  );
}
